enum CompactActivity: String, CaseIterable, Identifiable {
    // Declaration order is the default priority; Settings can override it.
    case timer, stopwatch, codex, media

    var id: String { rawValue }
}

extension CompactActivity {
    /// Preferred side when split across the cutout, and ordering within a paired wing.
    var primarySide: CompactActivityLayout.Side {
        switch self {
        case .media: .left
        case .timer, .stopwatch, .codex: .right
        }
    }

    var title: String {
        switch self {
        case .media: "Now Playing"
        case .timer: "Timer"
        case .stopwatch: "Stopwatch"
        case .codex: "Code tasks"
        }
    }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .timer: "timer"
        case .stopwatch: "stopwatch"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }
}
