import SwiftUI

struct LyricsView: View {
    @ObservedObject var model: LyricsViewModel
    var shadowed = false
    var rowHeight: CGFloat = 44
    @Environment(\.notchReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Text(model.text)
            .font(.system(size: 13, weight: model.status == .ready ? .medium : .regular))
            .foregroundStyle(.white.opacity(model.status == .ready ? 0.95 : 0.65))
            .shadow(color: .black.opacity(shadowed ? 0.85 : 0), radius: 1, y: 1)
            .shadow(color: .black.opacity(shadowed ? 0.55 : 0), radius: 4, y: 2)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight)
            .id(model.text)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 8).combined(with: .opacity),
                                                            removal: .offset(y: -8).combined(with: .opacity)))
            .accessibilityLabel("Lyrics: \(model.text)")
            .help(model.text + (model.source.map { " · Lyrics from " + $0.rawValue } ?? ""))
        }
            .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.28), value: model.text)
            .padding(.horizontal, 20)
            .clipped()
    }
}

struct FloatingLyricsView: View {
    @ObservedObject var music: MusicViewModel
    var notchWidth: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        LyricsView(model: music.lyrics, shadowed: true, rowHeight: 36)
            .background(alignment: .top) {
                GeometryReader { geometry in
                    Group {
                        if let backdrop = music.backdrop {
                            Image(nsImage: backdrop).resizable().scaledToFill()
                        } else {
                            music.accentColor
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .opacity(reduceTransparency ? 1 : 0.60)
                    .mask { NotchLyricsCloud() }
                }
                .frame(width: max(notchWidth, 400) + 48, height: 80)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

/// A broad, elliptical falloff centered on the notch edge, like a cloud of blurred album color.
private struct NotchLyricsCloud: View {
    var body: some View {
        Canvas { context, size in
            // Scale a circular blur into a wide cloud. The upper half stays behind the notch.
            context.scaleBy(x: size.width / 2, y: size.height)
            let fade = Gradient(stops: [
                .init(color: .white, location: 0),
                .init(color: .white.opacity(0.88), location: 0.25),
                .init(color: .white.opacity(0.42), location: 0.55),
                .init(color: .white.opacity(0.08), location: 0.82),
                .init(color: .clear, location: 1)
            ])
            context.fill(Path(CGRect(x: 0, y: 0, width: 2, height: 1)),
                         with: .radialGradient(fade, center: CGPoint(x: 1, y: 0), startRadius: 0, endRadius: 1))
        }
    }
}
