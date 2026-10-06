import SwiftUI

private struct NotchMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var notchReduceMotion: Bool {
        get { self[NotchMotionKey.self] }
        set { self[NotchMotionKey.self] = newValue }
    }
}

struct NotchHoverEffect: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.notchReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var hovered = false
    var pressed = false
    var cornerRadius: CGFloat = 8
    private var active: Bool { hovered && enabled }
    func body(content: Content) -> some View {
        content
            .background(.white.opacity(active ? 0.09 : 0), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(reduceMotion || systemReduceMotion ? 1 : (pressed && enabled ? 0.95 : (active ? 1.045 : 1)))
            .brightness(active ? 0.06 : 0)
            .animation(reduceMotion || systemReduceMotion ? nil : .smooth(duration: 0.18), value: active)
            .animation(reduceMotion || systemReduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
            .onHover { hovered = $0 }
            .pointingCursor()
    }
}
struct NotchHoverButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(NotchHoverEffect(pressed: configuration.isPressed, cornerRadius: cornerRadius))
    }
}
