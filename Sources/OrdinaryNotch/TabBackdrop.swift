import SwiftUI

/// Full-width color beneath the content. The header remains solid black, while the
/// wash reaches the silhouette's sides and bottom without an inset panel edge.
/// Music follows the available album artwork, including while paused.
/// Music without artwork and other tabs keep their default accents.
struct NotchContentBackdrop: View {
    @Environment(\.notchReduceMotion) private var reduceMotion
    let tab: NotchViewModel.Tab
    var albumColors: [NSColor]? = nil

    private var colors: [Color] {
        if tab == .overview, let albumColors, !albumColors.isEmpty {
            return albumColors.map { Color(nsColor: $0) }
        }
        return [color, color]
    }

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
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    .opacity(0.20).id(colors).transition(.opacity)
            }
            .animation(NotchMotion.content(reduceMotion: reduceMotion), value: tab)
            .animation(NotchMotion.content(reduceMotion: reduceMotion), value: colors)
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
