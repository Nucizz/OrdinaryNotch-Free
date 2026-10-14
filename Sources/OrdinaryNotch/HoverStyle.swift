import SwiftUI
struct NotchHoverButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8
    func makeBody(configuration: Configuration) -> some View {
        NotchButtonLayout { configuration.label }
            .modifier(NotchHoverEffect(pressed: configuration.isPressed, cornerRadius: cornerRadius))
    }
}
