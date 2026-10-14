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

/// Keep both dimensions in one animation, independent of the island's reveal mask.
struct FloatingLyricsLayer: View, Animatable {
    @ObservedObject var music: MusicViewModel
    var width: CGFloat
    var top: CGFloat
    var glowHeight: CGFloat
    let textWidth: CGFloat
    var showsText = true
    var showsGlow = true
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(width, top), glowHeight) }
        set { width = newValue.first.first; top = newValue.first.second; glowHeight = newValue.second }
    }
    var body: some View {
        ZStack(alignment: .top) {
            if showsGlow {
                FloatingLyricsGlow(music: music, width: max(0, width), height: max(0, glowHeight))
                    .offset(y: -max(0, glowHeight) / 2)
            }
            if showsText { LyricsView(model: music.lyrics, shadowed: true, rowHeight: 36).frame(width: textWidth) }
        }
        .frame(width: textWidth, height: 112, alignment: .top)
        .offset(y: top)
        .allowsHitTesting(false)
    }
}

struct FloatingLyricsGlow: View {
    @ObservedObject var music: MusicViewModel
    let width: CGFloat
    let height: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                music.accentColor
                if let backdrop = music.backdrop {
                    Image(nsImage: backdrop).resizable().scaledToFill()
                        .opacity(0.65)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .opacity(reduceTransparency ? 0 : 0.38)
            .mask {
                NotchLyricsCloud()
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// An elliptical falloff below the centered surface group.
private struct NotchLyricsCloud: View {
    var body: some View {
        Canvas { context, size in
            // Fit the whole ellipse; every edge fades out before the view ends.
            context.scaleBy(x: size.width / 2, y: size.height / 2)
            let fade = Gradient(stops: [
                .init(color: .white, location: 0),
                .init(color: .white.opacity(0.94), location: 0.25),
                .init(color: .white.opacity(0.65), location: 0.55),
                .init(color: .white.opacity(0.16), location: 0.82),
                .init(color: .clear, location: 1)
            ])
            context.fill(Path(CGRect(x: 0, y: 0, width: 2, height: 2)),
                         with: .radialGradient(fade, center: CGPoint(x: 1, y: 1), startRadius: 0, endRadius: 1))
        }
    }
}
