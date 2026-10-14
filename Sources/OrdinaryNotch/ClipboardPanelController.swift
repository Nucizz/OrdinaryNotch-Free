import AppKit

private final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        let content = contentViewController as? ClipboardContentController
        if event.type == .flagsChanged { content?.modifiersChanged(event.modifierFlags) }
        if event.type == .keyDown, content?.handleKey(event) == true { return }
        super.sendEvent(event)
    }
}

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    var openPreferences: () -> Void = {}
    private var panel: NSPanel?
    private var content: ClipboardContentController?
    private let pasteService: ClipboardPasting
    private var pasteTask: Task<Void, Never>?
    private(set) var isPresented = false
    init(pasteService: ClipboardPasting? = nil) {
        self.pasteService = pasteService ?? ClipboardPasteService()
        super.init()
    }
    func toggle(model: ClipboardViewModel) {
        if isPresented { close(); return }
        let session = SessionLockSnapshot.read()
        guard model.enabled, !session.locked, session.currentConsoleUser else { return }
        pasteTask?.cancel()
        pasteService.captureDestination()
        model.prepareToShow()
        if panel == nil {
            let window = ClipboardPanel(contentRect: NSRect(x: 0, y: 0, width: 450, height: 240),
                                        styleMask: [.nonactivatingPanel, .resizable, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            // Match Maccy's floating-panel presentation, including inactive-app and Space handling.
            window.animationBehavior = .none
            window.isFloatingPanel = true
            window.acceptsMouseMovedEvents = true
            window.level = NotchWindowPolicy.clipboardLevel
            window.collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
            window.title = "Clipboard History"
            // Adapted from Maccy's FloatingPanel (MIT, Resources/Maccy-LICENSE.txt).
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear; window.isOpaque = false
            window.titlebarSeparatorStyle = .none
            window.hasShadow = true; window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false; window.delegate = self
            let content = ClipboardContentController(model: model, close: { [weak self] in self?.close() },
                paste: { [weak self] in self?.pasteSelected(model: model) },
                preferences: { [weak self] in self?.openPreferences() })
            window.contentViewController = content
            window.setContentSize(NSSize(width: 450, height: 240))
            window.contentMinSize = NSSize(width: 360, height: 180)
            // The native material supplies the rounded edge. Masking the window's
            // frame view clips Liquid Glass highlights and its system shadow.
            content.sizeChanged = { [weak self] height, preview in self?.resize(height: height, preview: preview) }
            self.content = content
            panel = window
        }
        guard let panel else { return }
        content?.prepareForPresentation()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen {
            let area = screen.visibleFrame
            panel.setFrameOrigin(Self.popupOrigin(size: panel.frame.size, cursor: NSEvent.mouseLocation, visibleFrame: area))
        }
        isPresented = true
        panel.orderFrontRegardless()
        panel.makeKey()
        content?.prepareForPresentation()
    }
    private func resize(height: CGFloat, preview: Bool) {
        guard let panel else { return }
        let screen = panel.screen ?? NSScreen.main
        let maxHeight = min(800, (screen?.visibleFrame.height ?? 820) - 20)
        let size = NSSize(width: preview ? 730 : 450, height: min(maxHeight, max(preview ? 280 : 180, height)))
        var frame = NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height)
        if let area = screen?.visibleFrame {
            frame.origin.x = max(area.minX, min(frame.minX, area.maxX - size.width))
            frame.origin.y = max(area.minY, min(frame.minY, area.maxY - size.height))
        }
        panel.setFrame(frame, display: isPresented)
    }
    static func popupOrigin(size: NSSize, cursor: NSPoint, visibleFrame: NSRect) -> NSPoint {
        NSPoint(x: max(visibleFrame.minX, min(cursor.x, visibleFrame.maxX - size.width)),
                y: max(visibleFrame.minY, min(cursor.y - size.height, visibleFrame.maxY - size.height)))
    }
    func close() {
        dismiss()
    }
    private func pasteSelected(model: ClipboardViewModel) {
        if let failure = pasteService.prepareToPaste() { model.reportPasteResult(failure); return }
        hidePanel()
        pasteTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.pasteService.paste()
            guard !Task.isCancelled else { return }
            model.reportPasteResult(result)
        }
    }
    private func hidePanel() { isPresented = false; panel?.orderOut(nil) }
    func dismiss() { pasteTask?.cancel(); pasteService.cancel(); hidePanel() }
    func windowDidResignKey(_ notification: Notification) { if isPresented { dismiss() } }
    func windowWillClose(_ notification: Notification) { pasteTask?.cancel(); pasteService.cancel(); isPresented = false }
}
