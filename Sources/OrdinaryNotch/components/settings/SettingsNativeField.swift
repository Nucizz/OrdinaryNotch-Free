import SwiftUI

/// Use AppKit's own bezel, focus ring, field editor, and capsule border.
@MainActor enum SettingsNativeField {
    static func configure(_ field: NSTextField) {
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.controlSize = .large
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if #available(macOS 26, *) { field.borderShape = .capsule }
    }
    static func size(_ control: NSControl, proposal: ProposedViewSize) -> CGSize {
        CGSize(width: proposal.width ?? max(64, control.intrinsicContentSize.width),
               height: control.intrinsicContentSize.height)
    }
}

struct SettingsNumberField: NSViewRepresentable {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        SettingsNativeField.configure(field)
        field.alignment = .right
        field.formatter = context.coordinator.formatter
        field.delegate = context.coordinator
        field.setAccessibilityLabel(title)
        field.integerValue = value
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        field.isEnabled = enabled
        field.setAccessibilityLabel(title)
        if coordinator.lastValue != value {
            coordinator.lastValue = value
            field.integerValue = value
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        SettingsNativeField.size(nsView, proposal: proposal)
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SettingsNumberField
        var lastValue: Int
        let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.allowsFloats = false
            formatter.maximumFractionDigits = 0
            formatter.usesGroupingSeparator = false
            return formatter
        }()
        init(_ parent: SettingsNumberField) { self.parent = parent; lastValue = parent.value }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let number = formatter.number(from: field.stringValue)?.intValue,
                  parent.range.contains(number) else { return }
            lastValue = number
            parent.value = number
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            commit(field)
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)), let field = control as? NSTextField {
                commit(field)
            }
            return false
        }
        private func commit(_ field: NSTextField) {
            let number = formatter.number(from: field.stringValue)?.intValue ?? parent.value
            let clamped = min(parent.range.upperBound, max(parent.range.lowerBound, number))
            lastValue = clamped
            parent.value = clamped
            field.integerValue = clamped
        }
    }
}

struct SettingsSecureField: NSViewRepresentable {
    let title: String
    let placeholder: String
    @Binding var text: String
    var submit: () -> Void = {}
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        SettingsNativeField.configure(field)
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: NSSecureTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = enabled
        field.placeholderString = placeholder
        field.setAccessibilityLabel(title)
        if field.stringValue != text { field.stringValue = text }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSecureTextField, context: Context) -> CGSize? {
        SettingsNativeField.size(nsView, proposal: proposal)
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SettingsSecureField
        init(_ parent: SettingsSecureField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSecureTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.submit(); return true }
            return false
        }
    }
}
