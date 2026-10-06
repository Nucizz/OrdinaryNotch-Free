import AppKit
import Foundation
import SQLite3

struct CodexSessionStatus {
    var state = "idle"
    var detail = "Waiting for a task"
    var updatedAt = Date.distantPast
    var startedAt: Date?
    var goalStartedAt: Date?
    var finishedAt: Date?
    var taskName: String?
    var usage: CodexUsage?
    var hasUserInteraction = false
    var attention = CodexAttention()

    /// Reads lifecycle, request IDs, usage metadata, and a short user task label.
    static func parse(_ data: Data, continuing previous: CodexSessionStatus = CodexSessionStatus()) -> CodexSessionStatus {
        var status = previous
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        for line in data.split(separator: 10) {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = event["payload"] as? [String: Any],
                  let stamp = event["timestamp"] as? String,
                  let date = fractional.date(from: stamp) ?? plain.date(from: stamp) else { continue }
            if event["type"] as? String == "response_item" {
                let before = status.attention.reason
                status.attention.observe(payload)
                if before != status.attention.reason { status.updatedAt = date }
                if let goal = goalUpdate(in: payload) {
                    switch goal {
                    case .active(let startedAt): status.goalStartedAt = startedAt
                    case .inactive: status.goalStartedAt = nil
                    }
                    status.updatedAt = max(status.updatedAt, date)
                }
            }
            if event["type"] as? String == "response_item", payload["role"] as? String == "user", status.taskName == nil,
               let content = payload["content"] as? [[String: Any]] {
                for part in content where part["type"] as? String == "input_text" {
                    guard let rawText = part["text"] as? String else { continue }
                    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Context envelopes and approval replies are not task names.
                    guard !text.hasPrefix("<"), !text.isEmpty else { continue }
                    let request = text.components(separatedBy: "## My request:").last ?? text
                    if let first = request.split(separator: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        status.taskName = String(first.prefix(180)); status.hasUserInteraction = true; break
                    }
                }
                continue
            }
            guard event["type"] as? String == "event_msg", let type = payload["type"] as? String else { continue }
            switch type {
            case "task_started", "turn_started":
                status.attention.finishTurn()
                status.state = "running"; status.detail = "Working in Codex"
                status.startedAt = (payload["started_at"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? date
                status.finishedAt = nil; status.taskName = nil
            case "task_complete", "turn_complete":
                // Terminal lifecycle events supersede unanswered prompts from this turn.
                status.attention.clearPendingRequests()
                status.state = "complete"; status.detail = "Task completed"; status.finishedAt = date
                if let started = payload["started_at"] as? Double { status.startedAt = Date(timeIntervalSince1970: started) }
            case "turn_aborted":
                status.attention.clearPendingRequests()
                status.state = "stopped"; status.detail = "Task stopped"; status.finishedAt = date
            case "error", "task_failed", "turn_failed":
                // Retriable transport errors are still working; terminal errors need attention.
                if payload["will_retry"] as? Bool == true { continue }
                status.attention.clearPendingRequests()
                status.state = "failed"; status.detail = "Task failed"; status.finishedAt = date
            case "task_blocked", "turn_blocked", "rate_limit_reached", "usage_limit_reached":
                status.attention.clearPendingRequests()
                status.state = "blocked"; status.detail = "Blocked or limit reached"; status.finishedAt = date
            case "user_message":
                if let message = payload["message"] as? String {
                    let before = status.attention.reason
                    status.attention.observe(["role": "user", "content": [["text": message]]])
                    if before != status.attention.reason { status.updatedAt = date }
                }
                if let message = payload["message"] as? String, !message.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<"),
                   let first = message.split(separator: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    status.taskName = String(first.prefix(180))
                    status.hasUserInteraction = true
                }
                continue
            case "item_completed", "token_count", "agent_message", "agent_reasoning":
                // A bounded tail may begin after task_started in a long-running turn.
                if status.state == "idle" { status.state = "running"; status.detail = "Working in Codex" }
            default: continue
            }
            if type == "token_count", let limits = payload["rate_limits"] as? [String: Any],
               let usage = CodexUsage.parse(limits, at: date) { status.usage = usage }
            status.updatedAt = date
        }
        return status
    }
    private enum GoalUpdate { case active(Date), inactive }
    private static func goalUpdate(in value: Any) -> GoalUpdate? {
        if let dictionary = value as? [String: Any] {
            if dictionary.keys.contains("goal") {
                guard let goal = dictionary["goal"] as? [String: Any] else { return .inactive }
                guard goal["status"] as? String == "active",
                      let createdAt = (goal["createdAt"] as? NSNumber)?.doubleValue else { return .inactive }
                return .active(Date(timeIntervalSince1970: createdAt))
            }
            for child in dictionary.values {
                if let update = goalUpdate(in: child) { return update }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let update = goalUpdate(in: child) { return update }
            }
        } else if let text = value as? String,
                  let data = text.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) {
            return goalUpdate(in: decoded)
        }
        return nil
    }
    func activity(title: String, now: Date) -> CodexActivity {
        let stale = state == "running" && attention.reason == nil && now.timeIntervalSince(updatedAt) > 300
        return CodexActivity(title: title, detail: stale ? "No recent activity · status unavailable" : detail,
                             state: stale ? "unknown" : state, updatedAt: updatedAt, startedAt: startedAt, goalStartedAt: goalStartedAt,
                             finishedAt: finishedAt, taskName: taskName, usage: usage, attention: attention.reason)
    }
}

/// Queries Codex's local thread index read-only and tails changed session files.
/// No credentials, app settings, or remote APIs are accessed.
final class CodexActivityReader: @unchecked Sendable {
    private let lock = NSLock() // Serializes the mutable tail cache, including diagnostic callers.
    struct Entry { let threadID: String?; let title: String; let path: URL; let model: String?; let project: String?; let requiresUserInteraction: Bool; let hasUserEvent: Bool }
    private let logs = IncrementalJSONLog<CodexSessionStatus>()
    private let readState = CodexReadStateReader()
    private let replies = CodexQuestionReplyReader()
    let roots: [URL]

    init(roots: [URL] = CodexActivityReader.discoverRoots()) { self.roots = roots }
    static func discoverRoots() -> [URL] {
        let profiles = CodeProfiles()
        return CodeAccount.allCases.map { profiles.profile($0).root }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    func read(now: Date = Date()) -> CodexActivity {
        CodeDashboard(tasks: readTasks(now: now)).primary?.activity ?? .idle
    }
    func readTasks(now: Date = Date(), profileRoots: [URL]? = nil) -> [CodeTask] {
        lock.lock(); defer { lock.unlock() }
        var activities: [CodeTask] = []
        var seenPaths = Set<String>()
        for root in profileRoots ?? roots {
            let databases = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
                .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            guard let database = databases.first, let entries = entries(database: database, root: root) else { continue }
            let unread = readState.unreadThreads(in: root)
            let submitted = replies.read(root: root, now: now)
            let firstActivity = activities.count
            for entry in entries where seenPaths.insert(entry.path.path).inserted {
                guard var status = logs.read(entry.path, initial: CodexSessionStatus(), bootstrap: { handle, size in
                    CodexLogBootstrap.read(handle, size: size, hasUserEvent: entry.hasUserEvent)
                }, parse: { data, prior in
                    CodexSessionStatus.parse(data, continuing: prior)
                }) else { continue }
                for reply in submitted[entry.threadID ?? ""] ?? [] {
                    let before = status.attention.reason
                    status.attention.acknowledge(call: reply.callID, index: reply.index)
                    if before != status.attention.reason { status.updatedAt = max(status.updatedAt, reply.date) }
                }
                if status.updatedAt != .distantPast, !entry.requiresUserInteraction || status.hasUserInteraction {
                    var activity = status.activity(title: entry.title, now: now)
                    activity.model = entry.model; activity.project = entry.project
                    activities.append(CodeTask(id: entry.path.path, provider: .codex, activity: activity, profileID: root.standardizedFileURL.resolvingSymlinksInPath().path, completionWasRead: CodexReadStateReader.wasRead(threadID: entry.threadID, activity: activity, unread: unread, now: now), threadID: entry.threadID, pendingQuestions: status.attention.pendingAsyncQuestions))
                }
            }
            // Usage is account-wide. Use the newest snapshot from this profile only.
            let indices = firstActivity..<activities.count
            if let usage = indices.compactMap({ activities[$0].activity.usage }).max(by: { $0.updatedAt < $1.updatedAt }) {
                for index in indices { activities[index].activity.usage = usage }
            }
        }
        logs.retain(paths: seenPaths)
        return activities
    }
    private func entries(database: URL, root: URL) -> [Entry]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }; return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        var statement: OpaquePointer?
        var schema: OpaquePointer?
        var columns = Set<String>()
        if sqlite3_prepare_v2(db, "PRAGMA table_info(threads)", -1, &schema, nil) == SQLITE_OK {
            while sqlite3_step(schema) == SQLITE_ROW {
                if let bytes = sqlite3_column_text(schema, 1) { columns.insert(String(cString: bytes)) }
            }
        }
        sqlite3_finalize(schema)
        let titleColumn = columns.contains("name") ? "COALESCE(NULLIF(name, ''), title)" : "title"
        let modelColumn = columns.contains("model") ? "model" : "NULL"
        let cwdColumn = columns.contains("cwd") ? "cwd" : "NULL"
        // ChatGPT handoffs are user-owned tasks; review/subagent sessions are not.
        let visibleTasks = columns.contains("thread_source") ? " AND thread_source IN ('user', 'chatgpt_handoff')" : ""
        let visibleSources = columns.contains("source") ? " AND COALESCE(source, '') NOT LIKE '%subagent%'" : ""
        let visibleModels = columns.contains("model") ? " AND COALESCE(model, '') != 'codex-auto-review'" : ""
        let userFlag = columns.contains("has_user_event") ? "COALESCE(has_user_event, 0)" : "0"
        let userColumn = columns.contains("first_user_message") ? "(\(userFlag) OR length(COALESCE(first_user_message, '')) > 0)" : userFlag
        let idColumn = columns.contains("id") ? "id" : "NULL"
        let sourceColumn = columns.contains("thread_source") ? "thread_source" : "NULL"
        let sql = "SELECT \(titleColumn), rollout_path, \(modelColumn), \(cwdColumn), \(idColumn), \(userColumn), \(sourceColumn) FROM threads WHERE archived = 0\(visibleTasks)\(visibleModels)\(visibleSources) ORDER BY updated_at DESC LIMIT 32"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        var entries: [Entry] = []
        let prefix = root.appendingPathComponent("sessions").resolvingSymlinksInPath().path + "/"
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pathBytes = sqlite3_column_text(statement, 1) else { continue }
            let path = URL(fileURLWithPath: String(cString: pathBytes)).resolvingSymlinksInPath()
            guard path.path.hasPrefix(prefix), path.pathExtension == "jsonl" else { continue }
            let title = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "Codex task"
            let model = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let project = sqlite3_column_text(statement, 3).map { URL(fileURLWithPath: String(cString: $0)).lastPathComponent }
            let threadID = sqlite3_column_text(statement, 4).map { String(cString: $0) }
            let isHandoff = sqlite3_column_text(statement, 6).map { String(cString: $0) } == "chatgpt_handoff"
            entries.append(Entry(threadID: threadID, title: title.isEmpty ? "Codex task" : String(title.prefix(200)), path: path, model: model, project: project, requiresUserInteraction: columns.contains("thread_source") && !isHandoff, hasUserEvent: sqlite3_column_int(statement, 5) != 0))
        }
        return entries
    }
}
