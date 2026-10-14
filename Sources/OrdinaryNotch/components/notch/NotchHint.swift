import SwiftUI

extension View {
    /// Notch help has a fixed delay and never changes the notch's layout or focus.
    func notchHint(_ text: String) -> some View { modifier(NotchHintModifier(text: text)) }
}

private struct NotchHintModifier: ViewModifier {
    let text: String
    @Environment(\.isEnabled) private var enabled
    @Environment(\.notchIsPreview) private var preview
    @State private var anchor = NotchHintAnchorView()
    func body(content: Content) -> some View {
        content.background(NotchHintAnchor(view: anchor))
            .onHover { hovering in
                if hovering && enabled && !preview {
                    NotchHintPresenter.shared.request(text, anchor: anchor)
                } else { NotchHintPresenter.shared.cancel(anchor: anchor) }
            }
            .onChange(of: text) { _, _ in NotchHintPresenter.shared.cancel(anchor: anchor) }
            .onChange(of: enabled) { _, _ in NotchHintPresenter.shared.cancel(anchor: anchor) }
            .onDisappear { NotchHintPresenter.shared.cancel(anchor: anchor) }
            .accessibilityHint(text)
    }
}

private struct NotchHintAnchor: NSViewRepresentable {
    let view: NotchHintAnchorView
    func makeNSView(context: Context) -> NotchHintAnchorView { view }
    func updateNSView(_ nsView: NotchHintAnchorView, context: Context) {}
}
private final class NotchHintAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// One pending hint at a time, canceled by leaving, clicking, scrolling, or typing.
@MainActor final class NotchHintPresenter {
    static let shared = NotchHintPresenter()
    static let delay: Duration = .milliseconds(1500)
    private let wait: (Duration) async throws -> Void
    private let show: (String, NSView) -> Void
    private let hide: () -> Void
    private weak var anchor: NSView?
    private var pending: Task<Void, Never>?
    private var inputMonitor: Any?
    private var generation = 0
    init(wait: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         show: ((String, NSView) -> Void)? = nil,
         hide: (() -> Void)? = nil) {
        self.wait = wait
        self.show = show ?? { NotchHintPanel.shared.show($0, below: $1) }
        self.hide = hide ?? { NotchHintPanel.shared.hide() }
    }
    func request(_ text: String, anchor: NSView) {
        dismiss()
        guard !text.isEmpty else { return }
        self.anchor = anchor
        let generation = generation
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            self?.dismiss()
            return event
        }
        pending = Task { [weak self, weak anchor, wait] in
            do { try await wait(Self.delay) } catch { return }
            guard let self, let anchor, !Task.isCancelled, self.generation == generation,
                  self.anchor === anchor, anchor.window?.isVisible == true else { return }
            self.show(text, anchor)
        }
    }
    func cancel(anchor: NSView) { if self.anchor === anchor { dismiss() } }
    func dismiss() {
        generation += 1
        pending?.cancel(); pending = nil; anchor = nil
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor); self.inputMonitor = nil }
        hide()
    }
}

@MainActor private final class NotchHintPanel {
    static let shared = NotchHintPanel()
    private let panel: NSPanel
    private let label = NSTextField(wrappingLabelWithString: "")
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        let material = NSVisualEffectView()
        material.material = .toolTip; material.state = .active; material.blendingMode = .behindWindow
        material.wantsLayer = true; material.layer?.cornerRadius = 8; material.layer?.masksToBounds = true
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .labelColor
        material.addSubview(label); panel.contentView = material
    }
    func show(_ text: String, below anchor: NSView) {
        guard let window = anchor.window, window.isVisible, let screen = window.screen else { return }
        label.stringValue = text
        let measured = label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: 300, height: 1000))
        let size = CGSize(width: ceil(measured.width) + 20, height: ceil(measured.height) + 14)
        let target = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let frame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let origin = CGPoint(x: min(frame.maxX - size.width, max(frame.minX, target.midX - size.width / 2)),
                             y: max(frame.minY, target.minY - size.height - 6))
        panel.appearance = window.effectiveAppearance
        panel.level = NSWindow.Level(rawValue: max(window.level.rawValue + 1, NSWindow.Level.popUpMenu.rawValue))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        label.frame = NSRect(x: 10, y: 7, width: size.width - 20, height: size.height - 14)
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
    }
    func hide() { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
}

/// Native collection items share the same timer and presenter as SwiftUI controls.
final class NotchHintTrackingView: NSView {
    var hint = "" { didSet { if hint != oldValue { NotchHintPresenter.shared.cancel(anchor: self) } } }
    private var hintTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hintTracking { removeTrackingArea(hintTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hintTracking = area
    }
    override func mouseEntered(with event: NSEvent) { NotchHintPresenter.shared.request(hint, anchor: self) }
    override func mouseExited(with event: NSEvent) { NotchHintPresenter.shared.cancel(anchor: self) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { NotchHintPresenter.shared.cancel(anchor: self) }
    }
}
