import Foundation

public enum ClaudeHookSetup {
    public static let events = ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SessionEnd", "Elicitation", "ElicitationResult"]
    public static var configURL: URL {
        let root = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return root.appendingPathComponent("settings.json")
    }
    public static func configuration(_ data: Data?, executable: URL, enabled: Bool) throws -> Data {
        var config: [String: Any] = [:]
        if let data {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.propertyListReadCorrupt) }
            config = decoded
        }
        if let hooks = config["hooks"], !(hooks is [String: [[String: Any]]]) { throw CocoaError(.propertyListReadCorrupt) }
        var hooks = config["hooks"] as? [String: [[String: Any]]] ?? [:]
        let path = executable.path.replacingOccurrences(of: "'", with: "'\\''")
        for event in events {
            var entries = hooks[event] ?? []
            entries = entries.compactMap { entry in
                var entry = entry
                guard let original = entry["hooks"] as? [[String: Any]] else { return entry }
                let remaining = original.filter {
                    !(($0["command"] as? String ?? "").contains("/OrdinaryActivityBridge"))
                }
                guard !remaining.isEmpty else { return nil }
                entry["hooks"] = remaining
                return entry
            }
            if enabled {
                let interactive = event == "PermissionRequest" || event == "PreToolUse"
                var entry: [String: Any] = ["hooks": [["type": "command", "command": "'\(path)'" + (interactive ? " --interactive" : ""), "timeout": interactive ? 600 : 3]]]
                if event == "Notification" { entry["matcher"] = "permission_prompt" }
                entries.append(entry)
            }
            if entries.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = entries }
        }
        config["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }
    public static func installed(at url: URL = configURL) -> Bool {
        guard let data = try? Data(contentsOf: url), let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = config["hooks"] as? [String: [[String: Any]]] else { return false }
        return events.allSatisfy { event in
            (hooks[event] ?? []).contains { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String ?? "").contains("/OrdinaryActivityBridge") }
            }
        }
    }
    public static func install(executable: URL, at url: URL = configURL, enabled: Bool = true) throws {
        let existing = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        let updated = try configuration(existing, executable: executable, enabled: enabled)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing {
            let backup = url.deletingLastPathComponent().appendingPathComponent("settings.before-ordinary-notch-\(UUID().uuidString).json")
            try existing.write(to: backup, options: .withoutOverwriting)
        }
        try updated.write(to: url, options: .atomic)
    }
}
