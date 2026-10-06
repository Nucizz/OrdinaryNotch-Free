import AppKit
import SwiftUI
import Combine

@main struct OrdinaryNotchFreeApp: App {
    @NSApplicationDelegateAdaptor(FreeAppDelegate.self) var delegate
    var body: some Scene { Settings { FreeSettingsView(model: delegate.model, showClipboard: delegate.showClipboard) } }
}
private final class FreePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@MainActor final class FreeAppDelegate: NSObject, NSApplicationDelegate {
    let model = NotchViewModel()
    private let guardInstance = SingleInstanceGuard(bundleIdentifier: "dev.ordinary.notch.free")
    private var panel: NSPanel?
    private var settings: NSWindow?
    private var status: NSStatusItem?
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private let clipboardPanel = ClipboardPanelController()
    private let shortcut = ClipboardShortcutService()
    private let border = PhysicalNotchBorderController()
    private let focus = FocusCoordinator()
    private var lastScreenGeometry: String?
    private var hoverSince: Date?
    private var outsideSince: Date?
    private var screen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard guardInstance.acquire() else { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        let panel = FreePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.level = .statusBar; panel.hidesOnDeactivate = false; panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .stationary]
        panel.contentView = NSHostingView(rootView: NotchView(model: model)); self.panel = panel
        model.openSettings = { [weak self] in self?.openSettings() }
        model.expandFromClick = { [weak self] in self?.expand(true) }
        model.agentActions.focus = { [weak self] in self?.expand(true); self?.panel?.makeKey() }
        focus.settingsAreOpen = { [weak self] in self?.settings?.isVisible == true }
        focus.otherPanelIsPresented = { [weak self] in self?.clipboardPanel.isPresented == true }
        focus.start(); model.clock.focusReturnApplication = { [weak self] in self?.focus.previousApp }
        model.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.resize() }.store(in: &subscriptions)
        model.preferences.$values.map(\.clipboardHistoryEnabled).removeDuplicates().sink { [weak self] enabled in
            guard let self else { return }
            self.model.clipboard.setEnabled(enabled)
            if enabled { _ = self.shortcut.start { [weak self] in self?.showClipboard() } }
            else { self.shortcut.stop(); self.clipboardPanel.close() }
        }.store(in: &subscriptions)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status?.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Ordinary Notch Free")
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Clipboard History", action: #selector(showClipboard), keyEquivalent: "")
        menu.addItem(.separator()); menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }; status?.menu = menu
        NotificationCenter.default.addObserver(self, selector: #selector(resize), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        model.start(); resize()
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in Task { @MainActor in self?.track() } }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    @objc private func resize() {
        guard let panel, let screen else { return }
        let geometry = "\(screen.frame) \(screen.safeAreaInsets.top) \(screen.auxiliaryTopLeftArea as Any) \(screen.auxiliaryTopRightArea as Any) \(screen.backingScaleFactor)"
        if lastScreenGeometry != geometry {
            lastScreenGeometry = geometry
            model.updateDisplayGeometry(frame: screen.frame, safeAreaTop: screen.safeAreaInsets.top, left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea, scale: screen.backingScaleFactor)
        }
        let frame = NotchGeometry.frame(size: model.canvasSize, in: screen.frame).offsetBy(dx: 0, dy: -model.surfaceTopInset)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
    private func track() {
        guard let panel, let screen else { return }
        let session = SessionLockSnapshot.read()
        let hidden = session.locked || !session.currentConsoleUser || NSApp.currentSystemPresentationOptions.contains(.fullScreen)
        model.clipboard.suspend(session.locked || !session.currentConsoleUser)
        border.update(screen: screen, settings: model.preferences.values, canPresent: !hidden)
        status?.isVisible = model.preferences.values.showMenuBarIcon
        if hidden { panel.orderOut(nil); model.camera.stop(); hoverSince = nil; outsideSince = nil; return }
        if !panel.isVisible { panel.orderFrontRegardless() }
        let frame = NotchGeometry.frame(size: model.surfaceSize, in: screen.frame).offsetBy(dx: model.surfaceOffset, dy: -model.surfaceTopInset)
        let inside = frame.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        if model.agentActions.current != nil { expand(true); return }
        if inside {
            outsideSince = nil; hoverSince = hoverSince ?? Date()
            if !model.expanded && Date().timeIntervalSince(hoverSince!) >= model.preferences.values.openDelay { expand(true) }
        } else {
            hoverSince = nil; outsideSince = outsideSince ?? Date()
            if model.expanded && !model.pinned && !panel.isKeyWindow && Date().timeIntervalSince(outsideSince!) >= model.preferences.values.closeDelay { expand(false) }
        }
    }
    private func expand(_ value: Bool) {
        model.setExpanded(value)
        if !value, let panel { focus.restore(from: panel) }
    }
    @objc func openSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Ordinary Notch Free Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: FreeSettingsView(model: model, showClipboard: showClipboard))
            window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    @objc func showClipboard() { clipboardPanel.toggle(model: model.clipboard) }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return false }
    func applicationWillTerminate(_ notification: Notification) { model.camera.stop(); model.clipboard.setEnabled(false); shortcut.stop(); timer?.invalidate() }
}
