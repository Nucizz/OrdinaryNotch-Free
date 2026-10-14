import SwiftUI

/// Highlight the complete row, including help controls and the card's content insets.
struct SettingsHoverEffect: ViewModifier {
    var cornerRadius: CGFloat = SettingsStyle.controlRadius
    var horizontalInset: CGFloat = 0
    var verticalInset: CGFloat = 0
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalInset).padding(.vertical, verticalInset)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovered && enabled ? 0.06 : 0))
                    .allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .padding(.horizontal, -horizontalInset).padding(.vertical, -verticalInset)
    }
}
