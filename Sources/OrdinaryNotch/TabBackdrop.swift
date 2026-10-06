import SwiftUI

/// Full-width color beneath the content. The header remains solid black, while the
/// wash reaches the silhouette's sides and bottom without an inset panel edge.
/// Each tab keeps a distinct accent, independent of the current album artwork.
struct NotchContentBackdrop: View {
    @Environment(\.notchReduceMotion) private var reduceMotion
    let tab: NotchViewModel.Tab

    private var color: Color {
        switch tab {
        case .overview: Color(nsColor: .systemTeal)
        case .focus: Color(nsColor: .systemOrange)
        case .fans: Color(nsColor: .systemRed)
        case .codex: Color(nsColor: .systemPurple)
        case .shelf: Color(nsColor: .systemBlue)
        case .mirror: .clear
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                color.opacity(0.20).id(tab).transition(.opacity)
            }
            .animation(NotchMotion.content(reduceMotion: reduceMotion), value: tab)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.4), location: 0.35),
                    .init(color: .white, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
