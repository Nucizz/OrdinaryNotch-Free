import AppKit

@MainActor
extension CompactActivity {
    var detailTab: NotchViewModel.Tab {
        switch self {
        case .media: .overview
        case .timer, .stopwatch: .focus
        case .codex: .codex
        }
    }

    func isActive(in model: NotchViewModel) -> Bool {
        switch self {
        case .media: model.hasMusic && (model.music.isPlaying || model.preferences.values.showPausedMedia)
        case .timer: model.clock.primaryTimer != nil
        case .stopwatch: model.hasStopwatch
        case .codex: model.codex.showsCompactStatus(at: model.now)
        }
    }

    /// The text used for primary time/status content and its measured width.
    func primaryText(in model: NotchViewModel) -> String {
        switch self {
        case .media: ""
        case .timer: ClockFormat.format(model.clock.primaryTimer?.value(at: model.now) ?? 0)
        case .stopwatch: ClockFormat.format(model.clock.stopwatch.value(at: model.now).rounded(.down))
        case .codex: model.codex.elapsed(at: model.now).map(CodexDuration.format) ?? "—"
        }
    }

    func content(in model: NotchViewModel, paired: Bool) -> CompactActivityLayout.Content {
        let iconWidth: CGFloat
        switch self {
        case .media: iconWidth = NotchGeometry.compactMediaSize
        case .codex: iconWidth = paired ? 12 : max(20, model.compactHeight - 2 * NotchGeometry.compactContentInset)
        case .timer, .stopwatch: iconWidth = paired ? 14 : max(20, model.compactHeight - 2 * NotchGeometry.compactContentInset)
        }
        let valueWidth: CGFloat
        switch self {
        case .media: valueWidth = 20
        case .codex:
            valueWidth = model.codex.presentation(at: model.now) == .working
                ? model.compactTextWidth(primaryText(in: model)) : (paired ? 14 : 20)
        case .timer, .stopwatch:
            valueWidth = max(paired ? 14 : 54, model.compactTextWidth(primaryText(in: model)))
        }
        return .init(activity: self, primaryWidth: self == .media ? iconWidth : valueWidth,
                     secondaryWidth: self == .media ? valueWidth : iconWidth)
    }
}
