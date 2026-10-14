import AppKit
import SwiftUI

struct NotchButtonMenuItem {
    var title: String
    var selected = false
    var symbol: String?
    var enabled = true
    var action: () -> Void
}

/// Input only. NotchIconButton owns the icon, size, background and hover effects.
struct NotchPressAndHoldTarget: NSViewRepresentable {
    var label: String
    var value: String
    var hint: String
    var menuLabel: String
    var menuItems: [NotchButtonMenuItem]
    var action: () -> Void
    var menuOnClick = false
    var loadMenuItems: (() -> [NotchButtonMenuItem])?
    var menuVisibilityChanged: (Bool) -> Void = { _ in }
    @Binding var pressed: Bool
    @Binding var focused: Bool
    @Environment(\.isEnabled) private var enabled

    func makeNSView(context: Context) -> NotchPressAndHoldControl { NotchPressAndHoldControl() }
    static func dismantleNSView(_ button: NotchPressAndHoldControl, coordinator: ()) {
        button.cancelMenu()
    }
    func updateNSView(_ button: NotchPressAndHoldControl, context: Context) {
        button.isEnabled = enabled
        button.activate = action
        button.menuOnClick = menuOnClick
        button.loadMenuItems = loadMenuItems
        button.menuVisibilityChanged = menuVisibilityChanged
        button.menuItems = menuItems
        button.menuLabel = menuLabel
        button.pressedChanged = { pressed = $0 }
        button.focusChanged = { focused = $0 }
        button.toolTip = nil
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(value)
        button.setAccessibilityHelp(hint)
        button.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: menuLabel) { [weak button] in
            guard let button, button.isEnabled else { return false }
            button.showMenu(); return true
        }])
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchPressAndHoldControl, context: Context) -> CGSize? {
        let height = proposal.height ?? NotchControlMetrics.size
        return CGSize(width: max(height, proposal.width ?? NotchControlMetrics.size), height: height)
    }
}

/// Native tracking prevents a completed hold from also firing a short click.
class NotchPressAndHoldControl: NSButton {
    var activate: () -> Void = {}
    var menuItems: [NotchButtonMenuItem] = []
    var menuLabel = "More options"
    var menuOnClick = false
    var loadMenuItems: (() -> [NotchButtonMenuItem])?
    var menuVisibilityChanged: (Bool) -> Void = { _ in }
    var pressedChanged: (Bool) -> Void = { _ in }
    var focusChanged: (Bool) -> Void = { _ in }
    private var menuActions: [() -> Void] = []
    private var activeMenu: NSMenu?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false; title = ""; imagePosition = .noImage
        focusRingType = .none
        target = self; action = #selector(performAction)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NotchControlMetrics.size, height: NotchControlMetrics.size)
    }
    override func draw(_ dirtyRect: NSRect) {} // The shared SwiftUI surface draws everything.
    override func highlight(_ flag: Bool) { pressedChanged(flag) }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged(false) }
        return accepted
    }
    @objc private func performAction() {
        guard isEnabled else { return }
        if menuOnClick { showMenu() } else { activate() }
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else { return }
        if menuOnClick { showMenu(); return }
        if event.modifierFlags.contains(.control) { showMenu(); return }
        let deadline = Date().addingTimeInterval(0.5)
        highlight(true)
        defer { highlight(false) }
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: deadline,
                                          inMode: .eventTracking, dequeue: true) {
            let inside = bounds.contains(convert(next.locationInWindow, from: nil))
            if next.type == .leftMouseUp {
                if inside { performClick(nil) }
                return
            }
            if !inside { return }
        }
        showMenu()
    }
    override func rightMouseDown(with event: NSEvent) { if isEnabled { showMenu() } }
    func showMenu() {
        guard isEnabled else { return }
        if let loadMenuItems { menuItems = loadMenuItems() }
        guard !menuItems.isEmpty else { return }
        highlight(true)
        menuVisibilityChanged(true)
        let menu = makeMenu()
        activeMenu = menu
        defer { activeMenu = nil; highlight(false); menuVisibilityChanged(false) }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + 4), in: self)
    }
    func cancelMenu() { activeMenu?.cancelTrackingWithoutAnimation() }
    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: menuLabel)
        menu.autoenablesItems = false
        menuActions = menuItems.map(\.action)
        for (index, option) in menuItems.enumerated() {
            let item = NSMenuItem(title: option.title, action: #selector(selectMenuItem(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.state = option.selected ? .on : .off
            item.isEnabled = option.enabled
            if let symbol = option.symbol {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            menu.addItem(item)
        }
        return menu
    }
    @objc private func selectMenuItem(_ sender: NSMenuItem) {
        guard isEnabled, sender.isEnabled, menuActions.indices.contains(sender.tag) else { return }
        menuActions[sender.tag]()
    }
}
