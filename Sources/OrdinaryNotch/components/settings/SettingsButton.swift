import SwiftUI

/// Shared settings actions retain SwiftUI button semantics, shortcuts, and accessibility.
struct SettingsButtonStyle: PrimitiveButtonStyle {
    enum Appearance { case standard, icon, plain, borderless }
    var appearance: Appearance = .standard
    init(_ appearance: Appearance = .standard) { self.appearance = appearance }
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        switch appearance {
        case .standard, .icon:
            Button(configuration).buttonStyle(.bordered).buttonBorderShape(.capsule).pointingCursor()
        case .plain: Button(configuration).buttonStyle(.plain).pointingCursor()
        case .borderless: Button(configuration).buttonStyle(.borderless).pointingCursor()
        }
    }
}

struct SettingsIconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).frame(minWidth: 20, minHeight: 20) }
            .buttonStyle(SettingsButtonStyle(.icon)).help(label).accessibilityLabel(label)
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var detail: String? = nil
    var body: some View {
        SettingsRow(title, detail: detail) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).pointingCursor()
        }
    }
}
