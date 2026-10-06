import Foundation

public struct ClaudeUsageSnapshot: Codable, Equatable {
    public struct Window: Codable, Equatable {
        public let id: String
        public let used: Double
        public let resetsAt: TimeInterval
    }
    public let updatedAt: TimeInterval
    public let windows: [Window]
    public static func parse(_ input: [String: Any], now: Date = Date()) -> Self {
        let rates = input["rate_limits"] as? [String: [String: Any]] ?? [:]
        let windows = ["five_hour", "seven_day"].compactMap { id -> Window? in
            guard let rate = rates[id], let used = rate["used_percentage"] as? Double,
                  let resets = rate["resets_at"] as? Double, used.isFinite, resets.isFinite,
                  (0...100).contains(used), resets > now.timeIntervalSince1970 else { return nil }
            return Window(id: id, used: used, resetsAt: resets)
        }
        return Self(updatedAt: now.timeIntervalSince1970, windows: windows)
    }
    public static func file(in root: URL) -> URL { root.appendingPathComponent("ordinary-notch/usage.json") }
}
