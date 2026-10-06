import SwiftUI

@MainActor
extension CompactActivity {
    /// Artwork for media; time or status for clocks and Code tasks.
    @ViewBuilder func primary(in model: NotchViewModel) -> some View {
        switch self {
        case .media:
            Artwork(image: model.music.artwork, size: NotchGeometry.compactMediaSize,
                    cornerRadius: NotchGeometry.insetRadius(NotchGeometry.compactBottomRadius, padding: NotchGeometry.compactContentInset))
        case .timer, .stopwatch:
            Text(primaryText(in: model)).foregroundStyle(Color(nsColor: .systemOrange))
        case .codex:
            CodexStatusValue(activity: model.codex, now: model.now)
        }
    }

    /// A waveform for media; identifying icons for clocks and Code tasks.
    @ViewBuilder func secondary(in model: NotchViewModel) -> some View {
        switch self {
        case .media:
            Waveform(active: model.music.isPlaying, visible: !model.expanded, colors: model.music.waveformColors,
                     reduceMotionOverride: model.preferences.values.reduceMotion)
        case .timer, .stopwatch:
            Image(systemName: symbol).foregroundStyle(Color(nsColor: .systemOrange))
        case .codex:
            CodeLogo(provider: model.codeProvider, working: model.codex.isWorking, visible: !model.expanded)
                .frame(width: 12, height: 12)
        }
    }
}
