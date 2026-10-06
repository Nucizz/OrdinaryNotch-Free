import Foundation
import ActivityCore
import Darwin

// Status observation is silent. Interactive hooks return only an explicit user response from the notch.
if CommandLine.arguments.contains("--install") {
    do { try ClaudeHookSetup.install(executable: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL) }
    catch { FileHandle.standardError.write(Data("Could not configure Claude status hooks: \(error.localizedDescription)\n".utf8)); exit(1) }
    exit(0)
}
let input = FileHandle.standardInput.readDataToEndOfFile()
if CommandLine.arguments.contains("--usage") {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: "--config-dir"), args.indices.contains(index + 1), args[index + 1].hasPrefix("/"),
          let value = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { exit(0) }
    let root = URL(fileURLWithPath: args[index + 1])
    let snapshot = ClaudeUsageSnapshot.parse(value)
    let file = ClaudeUsageSnapshot.file(in: root)
    umask(0o077)
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
    if let saved = try? Data(contentsOf: root.appendingPathComponent("ordinary-notch/previous-status-line.json")),
       let line = try? JSONSerialization.jsonObject(with: saved) as? [String: Any],
       let command = line["command"] as? String, !command.isEmpty, !command.contains("OrdinaryActivityBridge") {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh"); process.arguments = ["-c", command]
        process.standardInput = pipe
        do {
            try process.run()
            try pipe.fileHandleForWriting.write(contentsOf: input)
            try pipe.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch { /* Preserve Claude's operation even if an existing status line fails. */ }
    } else {
        print(snapshot.windows.map { "\($0.id == "five_hour" ? "5h" : "7d"): \(Int($0.used.rounded()))% used" }.joined(separator: " · "))
    }
    exit(0)
}
guard let value = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
      value["agent_id"] == nil,
      let rawID = value["session_id"] as? String, let id = UUID(uuidString: rawID),
      let event = value["hook_event_name"] as? String, ClaudeHookSetup.events.contains(event) else { exit(0) }
let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
var record: [String: String] = ["event": event, "timestamp": formatter.string(from: Date())]
if let cwd = value["cwd"] as? String { record["project"] = URL(fileURLWithPath: cwd).lastPathComponent }
if event == "UserPromptSubmit", let prompt = value["prompt"] as? String {
    record["title"] = String(prompt.split(separator: "\n").first?.prefix(180) ?? "Claude Code task")
}
if let tool = value["tool_name"] as? String { record["tool"] = String(tool.prefix(100)) }
if let type = value["notification_type"] as? String { record["notification"] = type }
let folder = ClaudeHookSetup.configURL.deletingLastPathComponent().appendingPathComponent("ordinary-notch/activity")
umask(0o077)
do {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]); bytes.append(10)
    let path = folder.appendingPathComponent(id.uuidString.lowercased() + ".jsonl").path
    let fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0o600)
    if fd >= 0 { _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }; close(fd) }
} catch { /* Observation must never block or fail a Claude task. */ }

if CommandLine.arguments.contains("--interactive"),
   event == "PermissionRequest" || (event == "PreToolUse" && value["tool_name"] as? String == "AskUserQuestion") {
    do {
        let fd = try AgentActionWire.connect(AgentActionWire.socketURL.path, timeout: 600)
        defer { close(fd) }
        try AgentActionWire.send(["profile": ClaudeHookSetup.configURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path,
                                  "request": value], to: fd)
        let response = try AgentActionWire.receive(from: fd)
        if !response.isEmpty {
            let data = try JSONSerialization.data(withJSONObject: response)
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
        }
    } catch { /* No response means the provider keeps its original prompt. Never approve on failure. */ }
}
