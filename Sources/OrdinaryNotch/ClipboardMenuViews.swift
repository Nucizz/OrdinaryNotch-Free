import AppKit

// Layout adapted from Maccy's ListItemView and Popup (MIT, Alex Rodionov).
// See Resources/Maccy-LICENSE.txt and docs/clipboard-history.md.
enum ClipboardMenuMetrics {
    static var rowHeight: CGFloat { if #available(macOS 26, *) { return 24 }; return 22 }
    static var cornerRadius: CGFloat { if #available(macOS 26, *) { return 7 }; return 4 }
}

final class ClipboardMenuRowView: NSTableRowView {
    var separator = false
    var hovered: () -> Void = {}
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseMoved(with event: NSEvent) { hovered() }
    override func drawBackground(in dirtyRect: NSRect) {
        if separator {
            NSColor.separatorColor.setFill()
            NSRect(x: 6, y: 6, width: bounds.width - 12, height: 1).fill()
        }
    }
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.8).setFill()
        let rect = NSRect(x: 0, y: separator ? 13 : 0, width: bounds.width, height: bounds.height - (separator ? 13 : 0))
        NSBezierPath(roundedRect: rect, xRadius: ClipboardMenuMetrics.cornerRadius, yRadius: ClipboardMenuMetrics.cornerRadius).fill()
    }
    override var isEmphasized: Bool { get { true } set {} }
}

final class ClipboardMenuButton: NSButton {
    let caption = NSTextField(labelWithString: "")
    let shortcut = NSTextField(labelWithString: "")
    var selected = false { didSet { refresh() } }
    var hovered: () -> Void = {}
    private var tracking: NSTrackingArea?
    init(_ title: String, shortcut: String) {
        super.init(frame: .zero)
        self.title = ""; isBordered = false
        setAccessibilityLabel(title)
        caption.stringValue = title; self.shortcut.stringValue = shortcut
        for label in [caption, self.shortcut] {
            label.font = .systemFont(ofSize: 13)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        wantsLayer = true; layer?.cornerRadius = ClipboardMenuMetrics.cornerRadius
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: ClipboardMenuMetrics.rowHeight),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            caption.centerYAnchor.constraint(equalTo: centerYAnchor),
            self.shortcut.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            self.shortcut.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Use init(_:shortcut:)") }
    private func refresh() {
        layer?.backgroundColor = (selected ? NSColor.controlAccentColor.withAlphaComponent(0.8) : .clear).cgColor
        caption.textColor = selected ? .white : .labelColor
        shortcut.textColor = selected ? .white : .labelColor
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseMoved(with event: NSEvent) { hovered() }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
}
