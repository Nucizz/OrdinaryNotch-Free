import SwiftUI

/// Contextual explanations use a tooltip on hover and a keyboard-accessible popover on click.
struct SettingsHelpButton: View {
    let title: String
    let text: String
    @State private var presented = false
    var body: some View {
        SettingsHelpControl(title: title, text: text) { presented.toggle() }
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 13)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(16).frame(width: 300, alignment: .leading)
        }
        .environment(\.isEnabled, true)
    }
}

private struct SettingsHelpControl: NSViewRepresentable {
    let title: String
    let text: String
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.show))
        button.bezelStyle = .helpButton
        button.setButtonType(.momentaryPushIn)
        button.controlSize = .small
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.toolTip = text
        button.setAccessibilityLabel("About " + title)
        button.setAccessibilityHelp("Show an explanation")
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
    final class Coordinator: NSObject {
        var action: () -> Void = {}
        @objc func show() { action() }
    }
}
