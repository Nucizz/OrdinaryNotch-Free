import Foundation

public enum ClaudeMonitoringSetup {
    private static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func installed(root: URL) -> Bool {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("settings.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let line = json["statusLine"] as? [String: Any], let command = line["command"] as? String else { return false }
        return command.contains("/OrdinaryActivityBridge'") && command.contains(" --usage ")
    }
    public static func install(root: URL, executable: URL) throws {
        guard !installed(root: root) else { return }
        let file = root.appendingPathComponent("settings.json")
        let data = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
        var json = try JSONSerialization.jsonObject(with: ClaudeHookSetup.configuration(data, executable: executable, enabled: true)) as! [String: Any]
        let previous = json["statusLine"] as? [String: Any] ?? [:]
        let folder = root.appendingPathComponent("ordinary-notch")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let data { try data.write(to: folder.appendingPathComponent("settings-before-\(UUID().uuidString).json"), options: .withoutOverwriting) }
        // Keep the user's existing status-line command and all of its options.
        try JSONSerialization.data(withJSONObject: previous).write(to: folder.appendingPathComponent("previous-status-line.json"), options: .atomic)
        var line = previous
        line["type"] = "command"
        line["command"] = quote(executable.path) + " --usage --config-dir " + quote(root.path)
        json["statusLine"] = line
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
    }
    public static func remove(root: URL) throws {
        guard installed(root: root) else { return }
        let file = root.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: file)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let previous = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("ordinary-notch/previous-status-line.json"))) as? [String: Any] else { return }
        json["statusLine"] = previous.isEmpty ? nil : previous
        try data.write(to: root.appendingPathComponent("ordinary-notch/settings-before-\(UUID().uuidString).json"), options: .withoutOverwriting)
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
        try? FileManager.default.removeItem(at: ClaudeUsageSnapshot.file(in: root))
    }
}
