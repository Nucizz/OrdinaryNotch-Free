import SwiftUI

/// A consistent symbol box leaves an even border of color around wide and tall glyphs.
struct SettingsMenuIcon: View {
    let page: SettingsPage
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: page.icon)
            .resizable().scaledToFit().symbolRenderingMode(.monochrome)
            .fontWeight(.regular)
            .foregroundStyle(.white)
            .frame(width: size * 0.60, height: size * 0.60)
            .frame(width: size, height: size)
            .background(page.tint, in: RoundedRectangle(cornerRadius: size * 0.23))
            .accessibilityHidden(true)
    }
}

private extension SettingsPage {
    var tint: Color {
        switch self {
        case .general, .camera: .gray
        case .layout: .blue
        case .media: .pink
        case .timer, .code: .orange
        case .fans: .green
        case .clipboard: .teal
        case .permissions: .cyan
        }
    }
    var icon: String {
        switch self {
        case .general: "gearshape"; case .media: "music.note"; case .permissions: "hand.raised"
        case .layout: "rectangle.split.3x1"
        case .timer: "timer"; case .code: "chevron.left.forwardslash.chevron.right"; case .fans: "fan"
        case .clipboard: "doc.on.clipboard"
        case .camera: "web.camera"
        }
    }
}
