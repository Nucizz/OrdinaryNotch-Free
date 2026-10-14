import AppKit

enum LockScreenActivityMode: String, Codable, CaseIterable {
    case none, notch, screen
    var title: String {
        switch self {
        case .none: "None"
        case .notch: "Show on Notch"
        case .screen: "Show on Screen"
        }
    }
}

struct LockScreenActivityRow: Identifiable, Equatable {
    struct Media: Equatable {
        let identity: MusicContentIdentity
        let isPlaying: Bool
        let source: String
        let remaining: String?
        var outputName: String?
        var outputSymbol = "speaker.wave.2.fill"
        var position: Double = 0
        var duration: Double = 0
        var canSeek: Bool { identity.hasTrack && duration.isFinite && duration > 0 }
    }
    struct Code: Equatable {
        let provider: String
        let account: String
        let needsInput: Bool
        let statusSymbol: String
        var canOpen = true
        var canReview = true
        var detail = ""
    }
    let id: String
    let kind: CompactActivity
    let title: String
    let subtitle: String
    let value: String
    var progress: Double?
    var artwork: NSImage?
    var media: Media?
    var code: Code?
    var clockDetail: String?

    var preferredHeight: CGFloat {
        switch kind {
        case .media: 160
        case .codex: code?.detail.isEmpty == false ? 112 : 88
        case .timer, .stopwatch: 90
                }
    }
}

struct LockScreenActivitySnapshot: Equatable {
    var rows: [LockScreenActivityRow] = []

    @MainActor static func read(_ model: NotchViewModel, at now: Date) -> Self {
        var groups: [[LockScreenActivityRow]] = []
        // Lock-screen details are independent of which compact notch items are hidden.
        for kind in model.preferences.values.orderedActivities {
            let rows: [LockScreenActivityRow]
            switch kind {
            case .timer:
                rows = model.clock.timers.map { timer in
                    let remaining = timer.value(at: now)
                    return .init(id: "timer/" + timer.id, kind: kind, title: timer.title,
                        subtitle: timer.isPaused ? "Timer paused" : remaining == 0 ? "Timer finished" : "Timer running",
                        value: ClockFormat.format(remaining),
                        progress: timer.duration > 0 ? min(1, max(0, 1 - remaining / timer.duration)) : nil,
                        clockDetail: "of \(ClockFormat.format(timer.duration))")
                }
            case .stopwatch:
                let watch = model.clock.stopwatch
                rows = model.hasStopwatch ? [.init(id: "stopwatch", kind: kind, title: "Stopwatch",
                    subtitle: watch.isRunning ? "Running" : "Paused", value: ClockFormat.format(watch.value(at: now).rounded(.down)),
                    clockDetail: watch.laps.isEmpty ? "Elapsed time" : "\(watch.laps.count) \(watch.laps.count == 1 ? "lap" : "laps") · Last \(ClockFormat.format(watch.laps.last ?? 0))")] : []
            case .media:
                let music = model.music
                // The screen player stays available to resume a paused track.
                // The compact notch keeps its separate paused-media preference.
                rows = music.hasTrack
                    ? [.init(id: "media", kind: kind, title: music.title,
                        subtitle: music.artist,
                        value: ClockFormat.format(music.position.rounded(.down)),
                        progress: music.canSeek ? min(1, max(0, music.position / music.duration)) : nil, artwork: music.artwork,
                        media: .init(identity: music.contentIdentity, isPlaying: music.isPlaying, source: music.sourceTitle,
                            remaining: music.canSeek ? "−" + ClockFormat.format(max(0, music.duration - music.position).rounded(.down)) : nil,
                            outputName: music.outputName, outputSymbol: music.outputSymbol,
                            position: music.position, duration: music.duration))] : []
            case .codex:
                let dashboard = model.codeDashboard
                rows = dashboard.ordered.filter { $0.activity.presentation(at: now) != .idle }.map { task in
                    let activity = task.activity
                    let prompt = model.agentActions.prompts.first { codeID($0.task, in: dashboard) == codeID(task, in: dashboard) }
                    let detail = codeDetail(activity: activity, prompt: prompt)
                    let provider = task.provider == .claude ? "Claude" : "GPT"
                    let account = dashboard.account(for: task) ?? task.account
                    // taskName is the latest user message; title is the saved chat name.
                    return .init(id: codeID(task, in: dashboard), kind: kind, title: activity.title,
                        subtitle: activity.presentation(at: now) == .working ? "" : activity.presentationLabel(at: now),
                        value: activity.elapsed(at: now).map { ClockFormat.format($0.rounded(.down)) } ?? "",
                        progress: activity.fraction,
                        code: .init(provider: provider, account: account.title, needsInput: activity.needsInput,
                            statusSymbol: activity.statusSymbolName ?? "hammer.fill", canOpen: task.conversationURL != nil,
                            canReview: task.conversationURL != nil || prompt != nil, detail: detail))
                }

            }
            if !rows.isEmpty { groups.append(rows) }
        }
        // Give each configured activity one row before showing additional tasks.
        var rows: [LockScreenActivityRow] = []
        for index in 0..<(groups.map(\.count).max() ?? 0) {
            for group in groups where index < group.count { rows.append(group[index]) }
        }
        return Self(rows: rows)
    }

    static func codeDetail(activity: CodexActivity, prompt: AgentPrompt?) -> String {
        // Keep request content, without repeating normal running status or metadata.
        let detail = activity.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let routineStatus = ["Working", "Working in Codex"].contains(detail)
        var sections = [routineStatus ? nil : detail, prompt?.kind == .handoff ? nil : prompt?.detail].compactMap { $0 }
        for question in prompt?.questions ?? [] {
            let options = question.options.enumerated().map { index, option in
                let description = question.descriptions.indices.contains(index) ? question.descriptions[index] : ""
                return description.isEmpty ? option : "\(option) — \(description)"
            }
            sections.append(([question.title] + options).joined(separator: "\n"))
        }
        var unique: [String] = []
        for section in sections where !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !unique.contains(section) { unique.append(section) }
        }
        return unique.joined(separator: "\n")
    }

    static func codeID(_ task: CodeTask, in dashboard: CodeDashboard) -> String {
        "code/\(task.provider.rawValue)/\(task.profileID ?? (dashboard.account(for: task) ?? task.account).rawValue)/\(task.id)"
    }

    static let preview = Self(rows: [
        .init(id: "media", kind: .media, title: "Evening Light", subtitle: "Ordinary Sessions", value: "01:24", progress: 0.4,
            media: .init(identity: .init(source: "preview", title: "Evening Light", artist: "Ordinary Sessions", hasTrack: true),
                isPlaying: true, source: "Apple Music", remaining: "−02:06", outputName: "MacBook Speakers", outputSymbol: "laptopcomputer", position: 84, duration: 210)),
        .init(id: "code", kind: .codex, title: "Improve Clock controls", subtitle: "", value: "04:12",
            code: .init(provider: "GPT", account: "Personal", needsInput: false, statusSymbol: "hammer.fill")),
        .init(id: "timer", kind: .timer, title: "Focus", subtitle: "Timer running", value: "18:42", progress: 0.38, clockDetail: "of 30:00"),
        .init(id: "stopwatch", kind: .stopwatch, title: "Stopwatch", subtitle: "Running", value: "08:36", clockDetail: "3 laps · Last 02:48")
    ])
}

struct LockScreenActivityLayout: Equatable {
    let frame: CGRect
    static let width: CGFloat = 520
    static let cardSpacing: CGFloat = 10
    static let edgeInset: CGFloat = 10
    static let scrollEdgeHeight: CGFloat = 32
    static let previewHeight: CGFloat = 492

    static func make(screen: CGRect, snapshot: LockScreenActivitySnapshot, loginAreaVisible: Bool = true) -> Self? {
        guard !snapshot.rows.isEmpty, screen.width >= 360, screen.height >= 540 else { return nil }
        // Keep a stable viewport between the clock and login area as activities
        // come and go. Short stacks align at the bottom, above the account name.
        // Use screen.frame, not visibleFrame: the Dock/menu bar aren't lock-screen guides.
        let topReserve = max(190, screen.height * 0.28)
        let bottomReserve = loginAreaVisible
            ? max(170, min(220, screen.height * 0.22))
            : max(40, min(70, screen.height * 0.07))
        let height = screen.height - topReserve - bottomReserve
        let width = min(Self.width, screen.width - 64)
        return Self(frame: CGRect(x: screen.midX - width / 2, y: screen.minY + bottomReserve, width: width, height: height))
    }
}

enum LockScreenActivityPolicy {
    static func allowed(lock: SessionLockSnapshot, inactiveReasons: Set<String>, displayAwake: Bool = true) -> Bool {
        displayAwake && lock.locked && lock.currentConsoleUser && inactiveReasons.subtracting(["lock"]).isEmpty
    }
}
