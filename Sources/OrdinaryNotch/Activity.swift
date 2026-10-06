import Foundation

enum ClockFormat {
    static func format(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds).rounded(.up))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct CodexActivity: Codable, Equatable {
    var title: String
    var detail: String
    var state: String
    var progress: Double?
    var updatedAt: Date
    var startedAt: Date?
    var goalStartedAt: Date?
    var finishedAt: Date?
    var taskName: String?
    var model: String?
    var project: String?
    var usage: CodexUsage?
    var attention: String?
    enum Presentation: Equatable { case working, complete, input, warning, stopped, idle }
    var isBlocked: Bool {
        ["blocked", "limited", "rate_limited", "usage_limit_reached", "failed"].contains(state)
            || ["blocked", "limit", "rate_limit"].contains(attention ?? "")
    }
    var needsInput: Bool { attention != nil && !["complete", "stopped", "failed"].contains(state) && !isBlocked }
    var isWorking: Bool { isRunning && !needsInput && !isBlocked }
    func presentation(at now: Date) -> Presentation {
        if isBlocked { return .warning }
        if needsInput { return .input }
        if state == "complete" { return .complete }
        if isRunning { return .working }
        if state == "stopped" { return .stopped }
        return .idle
    }
    func showsCompactStatus(at now: Date) -> Bool {
        // The dashboard filters read completions and closed apps before this check.
        let state = presentation(at: now)
        return state == .working || state == .input || state == .complete
    }
    func presentationLabel(at now: Date) -> String {
        guard presentation(at: now) == .warning else { return displayStatus }
        return state == "failed" ? "Failed" : "Blocked or limit reached"
    }
    func elapsed(at now: Date) -> TimeInterval? {
        timerStartedAt.map { max(0, (isRunning ? now : (finishedAt ?? updatedAt)).timeIntervalSince($0)) }
    }
    var timerStartedAt: Date? { goalStartedAt ?? startedAt }
    var statusSymbolName: String? {
        if state == "failed" { return "xmark.octagon.fill" }
        if isBlocked { return "exclamationmark.triangle.fill" }
        if needsInput { return attention == "approval" ? "hand.raised.fill" : "questionmark.bubble.fill" }
        if state == "complete" { return "checkmark.circle.fill" }
        return nil
    }
    var isRunning: Bool { state == "running" }
    var displayStatus: String {
        if needsInput, let attention { return attention == "approval" ? "Needs approval" : "Waiting for your answer" }
        switch state {
        case "running": return "Working"
        case "complete": return "Completed"
        case "stopped": return "Stopped"
        case "failed": return "Failed"
        case "unknown": return "Status unavailable"
        default: return "No ongoing task"
        }
    }
    var fraction: Double? { progress.map { min(1, max(0, $0)) } }
    static let idle = CodexActivity(title: "Ready when you are", detail: "Watching local Codex activity", state: "idle", updatedAt: Date())
}

struct CodexUsage: Codable, Equatable {
    struct Window: Codable, Identifiable, Equatable {
        var id: String
        var usedPercent: Double
        var minutes: Int
        var resetsAt: Date?
        func isLow(at now: Date) -> Bool { remaining < 10 && (resetsAt.map { $0 > now } ?? true) }
        var remaining: Double { max(0, min(100, 100 - usedPercent)) }
        var label: String { minutes == 10080 ? "Weekly" : minutes == 300 ? "5 hours" : "\(minutes / 60) hours" }
    }
    var windows: [Window]
    var updatedAt: Date
    static func parse(_ value: [String: Any], at date: Date) -> CodexUsage? {
        let windows = ["primary", "secondary"].compactMap { key -> Window? in
            guard let item = value[key] as? [String: Any], let used = (item["used_percent"] as? NSNumber)?.doubleValue,
                  used.isFinite, let minutes = (item["window_minutes"] as? NSNumber)?.intValue, minutes > 0 else { return nil }
            return Window(id: key, usedPercent: used, minutes: minutes,
                          resetsAt: (item["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:)))
        }
        return windows.isEmpty ? nil : CodexUsage(windows: windows, updatedAt: date)
    }
}


enum CodexDuration {
    static func format(_ duration: TimeInterval) -> String {
        let seconds = duration.isFinite ? Int(min(Double(Int.max / 2), max(0, duration))) : 0
        let days = seconds / 86400, hours = seconds / 3600, minutes = seconds % 3600 / 60
        if days > 0 { return "\(days)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds % 60)s" }
        return "\(seconds)s"
    }
}
