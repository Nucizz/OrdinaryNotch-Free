import Foundation
import ActivityCore
import Darwin

final class ClaudePromptService: @unchecked Sendable {
    private struct Pending { let prompt: AgentPrompt; let fd: Int32; let input: [String: Any]; var reply: [String: Any]? }
    private let lock = NSLock()
    private var pending: [String: Pending] = [:]
    private var profiles: [CodeProfile] = []
    private var configurationGeneration = UUID()
    private var listener: Int32 = -1
    private var started = false
    private let socketURL: URL
    private let waitDuration: TimeInterval
    init(socketURL: URL = AgentActionWire.socketURL, waitDuration: TimeInterval = 590) {
        self.socketURL = socketURL; self.waitDuration = waitDuration
    }
    func stop() {
        if listener >= 0 { shutdown(listener, SHUT_RDWR); close(listener); listener = -1; unlink(socketURL.path) }
        lock.lock(); profiles = []; lock.unlock()
    }
    func suspend() {
        lock.lock(); defer { lock.unlock() }
        profiles = []; configurationGeneration = UUID()
        for id in pending.keys where pending[id]?.reply == nil { pending[id]?.reply = [:] }
    }
    func configure(profiles: [CodeProfile]) {
        lock.lock(); self.profiles = profiles; lock.unlock()
        guard !started else { return }; started = true
        let url = socketURL
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var info = stat()
            guard lstat(directory.path, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR else { return }
            chmod(directory.path, 0o700)
            // Never take over another running instance's socket.
            if let existing = try? AgentActionWire.connect(url.path, timeout: 1) { close(existing); return }
            if lstat(url.path, &info) == 0 {
                guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else { return }
                unlink(url.path)
            }
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return }
            var address = try AgentActionWire.address(url.path)
            let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard result == 0 else { close(fd); return }
            chmod(url.path, 0o600)
            guard listen(fd, 8) == 0 else { close(fd); return }
            listener = fd
            DispatchQueue.global(qos: .utility).async { [weak self] in
                while true {
                    let client = accept(fd, nil, nil)
                    guard client >= 0 else { return }
                    guard AgentActionWire.sameUser(client) else { close(client); continue }
                    DispatchQueue.global(qos: .utility).async { [weak self] in self?.handle(client) }
                }
            }
        } catch { /* The original agent prompt remains available if the bridge cannot start. */ }
    }
    var prompts: [AgentPrompt] {
        lock.lock(); defer { lock.unlock() }
        return pending.values.filter { $0.reply == nil }.map(\.prompt).sorted { $0.id < $1.id }
    }
    func respond(_ prompt: AgentPrompt, answer: AgentAnswer?) throws {
        lock.lock(); defer { lock.unlock() }
        guard var item = pending[prompt.id], item.reply == nil, item.prompt == prompt else { throw AgentActionWire.Failure.expired }
        item.reply = try Self.response(prompt, input: item.input, answer: answer)
        pending[prompt.id] = item
    }
    static func response(_ prompt: AgentPrompt, input: [String: Any], answer: AgentAnswer?) throws -> [String: Any] {
        guard let answer else { return [:] } // Fall through to the original prompt.
        if prompt.kind == .claudeQuestion {
            guard !answer.alwaysAllow else { throw AgentActionWire.Failure.invalid }
            guard prompt.questions.allSatisfy({ !(answer.answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw AgentActionWire.Failure.invalid }
            var updated = input
            updated["answers"] = Dictionary(uniqueKeysWithValues: prompt.questions.map { ($0.title, answer.answers[$0.id]!) })
            return ["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": updated]]
        }
        guard let approve = answer.approve else { throw AgentActionWire.Failure.invalid }
        var decision: [String: Any] = ["behavior": approve ? "allow" : "deny"]
        if answer.alwaysAllow {
            guard approve, prompt.kind == .claudePermission, let payload = prompt.alwaysAllowPayload else { throw AgentActionWire.Failure.invalid }
            decision["updatedPermissions"] = try JSONSerialization.jsonObject(with: payload)
        }
        return ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
    }
    /// Offer only explicit, additive rules for this tool, never a permission-mode change.
    static func reusablePermission(_ value: [String: Any]) -> (payload: Data, scope: String)? {
        guard let tool = value["tool_name"] as? String,
              let suggestions = value["permission_suggestions"] as? [[String: Any]] else { return nil }
        for suggestion in suggestions {
            guard suggestion["type"] as? String == "addRules", suggestion["behavior"] as? String == "allow",
                  let destination = suggestion["destination"] as? String,
                  ["localSettings", "projectSettings", "userSettings"].contains(destination),
                  let rules = suggestion["rules"] as? [[String: Any]], !rules.isEmpty,
                  rules.allSatisfy({ $0["toolName"] as? String == tool }),
                  let payload = try? JSONSerialization.data(withJSONObject: [suggestion], options: .sortedKeys) else { continue }
            let scope = rules.map { rule in
                (rule["ruleContent"] as? String).map { tool + "(" + $0 + ")" } ?? "All " + tool + " actions"
            }.joined(separator: ", ")
            let location = destination == "userSettings" ? "all projects" : (destination == "projectSettings" ? "shared project settings" : "this project")
            return (payload, scope + " · " + location)
        }
        return nil
    }
    private func handle(_ fd: Int32) {
        defer { close(fd) }
        AgentActionWire.configure(fd, timeout: 3)
        guard let envelope = try? AgentActionWire.receive(from: fd),
              let root = envelope["profile"] as? String,
              let value = envelope["request"] as? [String: Any],
              let session = value["session_id"] as? String, UUID(uuidString: session) != nil,
              let input = value["tool_input"] as? [String: Any] else { return }
        lock.lock()
        let profile = profiles.first { $0.id == URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath().path }
        let configuration = configurationGeneration
        lock.unlock()
        guard let profile else { try? AgentActionWire.send([:], to: fd); return }
        let event = value["hook_event_name"] as? String
        let tool = value["tool_name"] as? String ?? "Tool"
        let question = event == "PreToolUse" && tool == "AskUserQuestion"
        guard question || event == "PermissionRequest" else { return }
        let id = UUID().uuidString
        var activity = CodexActivity.idle
        activity.title = "Claude task"
        activity.taskName = (value["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude Code"
        let task = CodeTask(id: profile.id + ":" + session, provider: .claude, activity: activity,
                            profileID: profile.id, threadID: session, account: profile.account, sourceApplication: profile.runtime)
        var prompt = AgentPrompt(id: id, task: task, kind: question ? .claudeQuestion : .claudePermission, requestID: id)
        if !question, let permission = Self.reusablePermission(value) {
            prompt.alwaysAllowPayload = permission.payload; prompt.alwaysAllowScope = permission.scope
        }
        if question {
            guard let questions = input["questions"] as? [[String: Any]], !questions.isEmpty else { return }
            prompt.questions = questions.enumerated().compactMap { index, q in
                guard let title = q["question"] as? String else { return nil }
                let options = q["options"] as? [[String: Any]] ?? []
                return AgentQuestion(id: String(index), title: title, options: options.compactMap { $0["label"] as? String },
                                     descriptions: options.map { $0["description"] as? String ?? "" }, multiple: q["multiSelect"] as? Bool ?? false)
            }
            guard prompt.questions.count == questions.count, Set(prompt.questions.map(\.title)).count == questions.count else { return }
        } else {
            guard let bytes = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]) else { return }
            prompt.detail = tool + "\n\n" + (value["cwd"] as? String ?? "") + "\n\n" + String(decoding: bytes, as: UTF8.self)
        }
        lock.lock()
        guard configuration == configurationGeneration, profiles.contains(where: { $0.id == profile.id }) else {
            lock.unlock(); try? AgentActionWire.send([:], to: fd); return
        }
        pending[id] = Pending(prompt: prompt, fd: fd, input: input); lock.unlock()
        defer { lock.lock(); pending.removeValue(forKey: id); lock.unlock() }
        let deadline = Date().addingTimeInterval(waitDuration)
        while Date() < deadline {
            var byte: UInt8 = 0
            let peek = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
            if peek == 0 || (peek < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) { return }
            lock.lock()
            let reply = pending[id]?.reply
            let monitored = profiles.contains { $0.id == profile.id }
            lock.unlock()
            if let reply { try? AgentActionWire.send(reply, to: fd); return }
            if !monitored { try? AgentActionWire.send([:], to: fd); return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        try? AgentActionWire.send([:], to: fd)
    }
}
