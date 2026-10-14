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
@MainActor final class FreeAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
    private let lockActivity = LockScreenActivityController()
    private let fullscreen = FullScreenMediaService()
    private var wasLocked = false
    private var notchLockTask: Task<Void, Never>?
    private var notchDelegated = false
    private lazy var lockActions = LockScreenActivityActions(context: { [weak self] in
        guard let self else { return .init(lock: .init(locked: false, currentConsoleUser: false), enabled: false, sessionAvailable: false) }
        return .init(lock: SessionLockSnapshot.read(), enabled: model.preferences.values.lockScreenActivity == .screen,
            sessionAvailable: DisplayPowerService.isAwake(on: screen))
    }, snapshot: { [weak self] in self.map { .read($0.model, at: Date()) } ?? .init() },
    media: { [weak self] in self?.model.music.command($0.rawValue) },
    open: { [weak self] id, review in
        guard let self else { return }
        if let task = model.codeDashboard.ordered.first(where: { LockScreenActivitySnapshot.codeID($0, in: self.model.codeDashboard) == id }) {
            if review { model.agentActions.showPending() }
            else { model.codexMonitor.openTask(task) }
        } else { model.clock.openClock(stopwatch: id == "stopwatch") }
    }, output: { [weak self] device in
        guard let self, AudioOutput.select(device) else { return false }
        model.music.refresh(); return true
    }, seek: { [weak self] seconds, identity in
        guard let music = self?.model.music, music.contentIdentity == identity else { return }
        music.previewSeek(to: seconds); music.finishSeeking()
    })
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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
            else { self.shortcut.stop(); self.clipboardPanel.dismiss() }
        }.store(in: &subscriptions)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status?.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Ordinary Notch Free")
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Clipboard History", action: #selector(showClipboard), keyEquivalent: "")
        menu.addItem(.separator()); menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }; status?.menu = menu
        NotificationCenter.default.addObserver(self, selector: #selector(resize), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        lockActivity.onAction = { [weak self] in self?.lockActions.perform($0) }
        lockActivity.onSelectOutput = { [weak self] device, identity in self?.lockActions.selectOutput(device, for: identity) ?? false }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(lockChanged(_:)), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(lockChanged(_:)), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        model.music.startLidMonitoring(); model.start(); resize()
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in Task { @MainActor in self?.track() } }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    @objc private func lockChanged(_ notification: Notification) {
        if notification.name.rawValue == "com.apple.screenIsLocked" { lockActivity.beginLockedSession() }
        else { lockActivity.beginUnlockAttempt(reduceMotion: model.preferences.values.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
        track()
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
        if session.locked && !wasLocked { lockActivity.beginLockedSession() }
        wasLocked = session.locked
        let awake = DisplayPowerService.isAwake(on: screen)
        let locked = session.locked && session.currentConsoleUser && awake
        lockActions.update()
        lockActivity.update(visible: locked && model.preferences.values.lockScreenActivity == .screen,
            snapshot: locked ? .read(model, at: Date()) : .init(), screen: screen.frame,
            animateExit: !session.locked, reduceMotion: model.preferences.values.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            pendingAction: lockActions.message)
        if locked && model.preferences.values.lockScreenActivity == .notch {
            model.setExpanded(false); model.camera.stop(); model.settingsCamera.stop(); model.clipboard.suspend(true); clipboardPanel.dismiss()
            panel.ignoresMouseEvents = true
            if notchLockTask == nil && !notchDelegated, let space = LockScreenSpace.shared {
                notchLockTask = Task { [weak self] in
                    let placed = await space.delegate(panel)
                    guard let self else { return }
                    notchLockTask = nil
                    let current = SessionLockSnapshot.read()
                    if placed && current.locked && current.currentConsoleUser && model.preferences.values.lockScreenActivity == .notch {
                        notchDelegated = true; panel.orderFrontRegardless()
                    } else { space.undelegate(panel) }
                }
            }
            return
        }
        if notchDelegated || notchLockTask != nil {
            notchLockTask?.cancel(); notchLockTask = nil; notchDelegated = false
            panel.orderOut(nil); LockScreenSpace.shared?.undelegate(panel)
        }
        let systemFullScreen = NSApp.currentSystemPresentationOptions.contains(.fullScreen)
        let mediaFullScreen = fullscreen.read(screen: screen, systemFullScreen: systemFullScreen,
            enabled: model.preferences.values.fullScreenVisibility != .always && !session.locked)
        let hidden = session.locked || !session.currentConsoleUser || !awake || SystemPromptPresentationService.shared.shouldYield() ||
            (model.toast.notice?.postponesFullScreenHide != true && model.preferences.values.fullScreenVisibility.hidesNotch(appFullScreen: systemFullScreen, mediaFullScreen: mediaFullScreen))
        model.clipboard.suspend(session.locked || !session.currentConsoleUser)
        if session.locked || !session.currentConsoleUser { model.settingsCamera.stop(); clipboardPanel.dismiss() }
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
            if model.preferences.values.openOnHover && !model.expanded && Date().timeIntervalSince(hoverSince!) >= model.preferences.values.openDelay { expand(true) }
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 870, height: 680), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Ordinary Notch"; window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView: FreeSettingsView(model: model, showClipboard: showClipboard))
            window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settings else { return }
        model.settingsCamera.stop(); settings = nil
    }
    @objc func showClipboard() { clipboardPanel.toggle(model: model.clipboard) }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return false }
    func applicationWillTerminate(_ notification: Notification) { lockActivity.hide(); notchLockTask?.cancel(); if let panel { LockScreenSpace.shared?.undelegate(panel) }; model.clock.stopMonitoring(); model.codexMonitor.stopMonitoring(); model.music.stop(); model.camera.stop(); model.clipboard.setEnabled(false); shortcut.stop(); timer?.invalidate() }
}
