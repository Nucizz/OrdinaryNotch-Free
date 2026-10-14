import Foundation
import ActivityCore

struct ClaudeSessionStatus {
    var title = "Claude Code task"
    var named = false
    var hasUser = false
    var activity = CodexActivity(title: "Claude Code task", detail: "", state: "idle", updatedAt: .distantPast)
    private var questions = Set<String>()
    private var computerControl = ComputerControlState()
    static func parse(_ data: Data, continuing previous: Self = Self()) -> Self {
        var result = previous
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        for line in data.split(separator: 10) {
            guard let item = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], item["isSidechain"] as? Bool != true else { continue }
            let type = item["type"] as? String ?? ""
            if let name = (item["customTitle"] ?? item["aiTitle"]) as? String, !name.isEmpty {
                result.title = String(name.prefix(180)); result.named = true
            }
            guard let stamp = item["timestamp"] as? String, let date = fractional.date(from: stamp) ?? plain.date(from: stamp) else { continue }
            if let cwd = item["cwd"] as? String { result.activity.project = URL(fileURLWithPath: cwd).lastPathComponent }
            let message = item["message"] as? [String: Any] ?? [:]
            let parts = message["content"] as? [[String: Any]] ?? []
            if type == "user" {
                let toolResults = parts.filter { $0["type"] as? String == "tool_result" }
                for part in toolResults {
                    if let id = part["tool_use_id"] as? String {
                        result.questions.remove(id)
                        result.computerControl.finish(id, at: date)
                    }
                }
                let prompt = (message["content"] as? String) ?? parts.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.first
                var submitted = false
                if toolResults.isEmpty, let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<"), !prompt.isEmpty {
                    submitted = true; result.hasUser = true; result.questions.removeAll()
                    result.computerControl.reset()
                    result.activity.startedAt = date; result.activity.finishedAt = nil
                    result.activity.taskName = String(prompt.split(separator: "\n").first?.prefix(180) ?? "Task")
                    if !result.named { result.title = result.activity.taskName ?? result.title }
                }
                if !toolResults.isEmpty || submitted {
                    result.activity.state = "running"; result.activity.attention = result.questions.isEmpty ? nil : "question"
                    result.activity.updatedAt = date
                }
            } else if type == "assistant" {
                result.activity.state = "running"
                for part in parts where part["type"] as? String == "tool_use" {
                    if let id = part["id"] as? String, let name = part["name"] as? String,
                       ComputerControlTool.isControl(name: name, input: part["input"] as? [String: Any] ?? [:]) {
                        result.computerControl.start(id, at: date)
                    }
                    if ["AskUserQuestion", "ExitPlanMode"].contains(part["name"] as? String ?? ""), let id = part["id"] as? String { result.questions.insert(id) }
                }
                result.activity.attention = result.questions.isEmpty ? nil : "question"
                if ["end_turn", "stop_sequence"].contains(message["stop_reason"] as? String ?? "") {
                    result.activity.state = "complete"; result.activity.finishedAt = date
                    result.questions.removeAll(); result.activity.attention = nil
                }
                if item["isApiErrorMessage"] as? Bool == true {
                    result.activity.state = "failed"; result.activity.finishedAt = date; result.activity.attention = nil
                }
                result.activity.updatedAt = date
            } else if type == "system", item["subtype"] as? String == "stop_hook_summary", item["preventedContinuation"] as? Bool != true {
                result.activity.state = "complete"; result.activity.finishedAt = date; result.activity.attention = nil
                result.questions.removeAll(); result.activity.updatedAt = date
            }
        }
        result.activity.title = result.title
        result.activity.computerControl = result.computerControl
        return result
    }
    static func hook(_ data: Data, continuing previous: Self = Self()) -> Self {
        var result = previous
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in data.split(separator: 10) {
            guard let item = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let event = item["event"] as? String, let stamp = item["timestamp"] as? String,
                  let date = fractional.date(from: stamp) ?? formatter.date(from: stamp) else { continue }
            if let project = item["project"] as? String { result.activity.project = project }
            if let title = item["title"] as? String, !title.isEmpty { result.title = title; result.activity.taskName = title }
            switch event {
            case "UserPromptSubmit":
                result.computerControl.reset()
                result.hasUser = true; result.activity.state = "running"; result.activity.attention = nil
                result.activity.startedAt = date; result.activity.finishedAt = nil
            case "PreToolUse", "PostToolUse", "PostToolUseFailure", "ElicitationResult":
                if let id = item["toolCallID"] as? String {
                    if event == "PreToolUse", item["computerControl"] as? String == "true" {
                        result.computerControl.start(id, at: date)
                    } else if event == "PostToolUse" || event == "PostToolUseFailure" {
                        result.computerControl.finish(id, at: date)
                    }
                }
                result.activity.state = "running"
                result.activity.attention = ["AskUserQuestion", "ExitPlanMode"].contains(item["tool"] as? String ?? "") && event == "PreToolUse" ? "question" : nil
            case "PermissionRequest": result.activity.state = "running"; result.activity.attention = "approval"
            case "Elicitation": result.activity.state = "running"; result.activity.attention = "question"
            case "Notification":
                guard item["notification"] as? String == "permission_prompt" else { continue }
                result.activity.state = "running"; result.activity.attention = "approval"
            case "Stop": result.activity.state = "complete"; result.activity.attention = nil; result.activity.finishedAt = date
            case "StopFailure": result.activity.state = "failed"; result.activity.attention = nil; result.activity.finishedAt = date
            case "SessionEnd":
                if result.activity.state != "complete" { result.activity.state = "stopped" }
                result.activity.attention = nil; result.activity.finishedAt = date
            default: continue
            }
            result.activity.updatedAt = date
        }
        result.activity.title = result.title
        result.activity.computerControl = result.computerControl
        return result
    }
}

final class ClaudeActivityReader: @unchecked Sendable {
    private let lock = NSLock()
    private let root: URL
    private let hooks: URL
    private let additionalHooks: [URL]
    private let logs = IncrementalJSONLog<ClaudeSessionStatus>()
    private let hookLogs = IncrementalJSONLog<ClaudeSessionStatus>()
    private var paths: [URL] = []
    private var scanAvailable = false
    private(set) var monitoringAvailable = false
    private var nextScan = Date.distantPast
    init(root: URL? = nil, hooks: URL? = nil, additionalHooks: [URL] = []) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.root = root ?? ClaudeHookSetup.configURL.deletingLastPathComponent().appendingPathComponent("projects")
        self.hooks = hooks ?? home.appendingPathComponent("Library/Application Support/OrdinaryNotch/ClaudeActivity")
        self.additionalHooks = additionalHooks
    }
    func readTasks(now: Date = Date()) -> [CodeTask] {
        lock.lock(); defer { lock.unlock() }
        if now >= nextScan {
            nextScan = now.addingTimeInterval(5)
            var health = CodeMonitoringHealth()
            let folders = health.contents(of: root).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            paths = folders.flatMap { health.contents(of: $0) }
                .filter { $0.pathExtension == "jsonl" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
                .sorted { (($0.modificationDate) ?? .distantPast) > (($1.modificationDate) ?? .distantPast) }
            paths = Array(paths.prefix(32))
            scanAvailable = health.available
        }
        var health = CodeMonitoringHealth(available: scanAvailable)
        var tasks: [String: ClaudeSessionStatus] = [:]
        for path in paths {
            guard let state = logs.read(path, initial: ClaudeSessionStatus(), parse: { ClaudeSessionStatus.parse($0, continuing: $1) }) else { health.available = false; continue }
            if !logs.lastReadComplete { health.available = false }
            guard state.hasUser else { continue }
            tasks[path.deletingPathExtension().lastPathComponent.lowercased()] = state
        }
        logs.retain(paths: Set(paths.map(\.path)))
        let hookFiles: [URL] = ([hooks] + additionalHooks).flatMap { folder in
            health.contents(of: folder)
        }
        let hookPaths = hookFiles.filter { $0.pathExtension == "jsonl" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }.prefix(64)
        for path in hookPaths {
            guard let hook = hookLogs.read(path, initial: ClaudeSessionStatus(), parse: { ClaudeSessionStatus.hook($0, continuing: $1) }) else { health.available = false; continue }
            if !hookLogs.lastReadComplete { health.available = false }
            let id = path.deletingPathExtension().lastPathComponent.lowercased()
            if let transcript = tasks[id] {
                if hook.activity.updatedAt >= transcript.activity.updatedAt {
                    var combined = hook
                    combined.hasUser = transcript.hasUser || hook.hasUser
                    combined.title = transcript.named ? transcript.title : hook.title
                    combined.activity.title = combined.title
                    combined.activity.startedAt = hook.activity.startedAt ?? transcript.activity.startedAt
                    if (transcript.activity.computerControl?.lastActionAt ?? .distantPast) >
                        (hook.activity.computerControl?.lastActionAt ?? .distantPast) {
                        combined.activity.computerControl = transcript.activity.computerControl
                    }
                    tasks[id] = combined
                }
            } else if hook.hasUser { tasks[id] = hook }
        }
        monitoringAvailable = health.available
        hookLogs.retain(paths: Set(hookPaths.map(\.path)))
        return tasks.map { id, status in
            var activity = status.activity
            if activity.isRunning && !activity.needsInput && now.timeIntervalSince(activity.updatedAt) > 900 { activity.state = "unknown" }
            return CodeTask(id: "claude:" + id, provider: .claude, activity: activity, threadID: id)
        }.sorted { $0.id < $1.id }
    }
}
private extension URL {
    var modificationDate: Date? { (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
}
