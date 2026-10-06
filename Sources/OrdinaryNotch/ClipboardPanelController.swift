import AppKit

private final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
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
            let window = ClipboardPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 430),
                                        styleMask: [.titled, .nonactivatingPanel, .resizable, .closable], backing: .buffered, defer: false)
            // Match Maccy's floating-panel presentation, including inactive-app and Space handling.
            window.animationBehavior = .none
            window.isFloatingPanel = true
            window.level = .screenSaver
            window.collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
            window.title = "Clipboard History"
            // AppKit owns the title bar, close button, background, and rounded window frame.
            window.hasShadow = true; window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false; window.delegate = self
            let content = ClipboardContentController(model: model, close: { [weak self] in self?.close() },
                paste: { [weak self] in self?.pasteSelected(model: model) })
            window.contentViewController = content
            window.setContentSize(NSSize(width: 440, height: 430))
            window.contentMinSize = NSSize(width: 360, height: 240)
            self.content = content
            panel = window
        }
        guard let panel else { return }
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
