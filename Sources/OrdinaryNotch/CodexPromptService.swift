import Foundation
import ActivityCore
import Darwin

/// Uses the running app's local request channel; never edits transcripts or task databases.
/// Unknown protocol versions and request types remain in the source app.
final class CodexPromptService: Sendable {
    private let readCurrentTask: @Sendable (CodeTask) -> CodeTask?
    init(readCurrentTask: @escaping @Sendable (CodeTask) -> CodeTask? = { task in
        guard let root = task.profileID else { return nil }
        return CodexActivityReader().readTasks(profileRoots: [URL(fileURLWithPath: root)]).first { $0.id == task.id }
    }) { self.readCurrentTask = readCurrentTask }
    func prompts(for task: CodeTask) -> [AgentPrompt] {
        if !task.pendingQuestions.isEmpty {
            return [AgentPrompt(id: task.id + ":" + task.pendingQuestions.map(\.id).joined(separator: ":"), task: task,
                                kind: .asyncQuestion, requestID: "async", questions: task.pendingQuestions)]
        }
        guard let client = try? Client(task: task) else { return [] }
        defer { client.closeConnection() }
        guard let snapshot = try? client.snapshot() else { return [] }
        return Self.parse(snapshot, task: task)
    }
    static func handoff(_ task: CodeTask) -> AgentPrompt {
        AgentPrompt(id: task.id + ":handoff", task: task, kind: .handoff, requestID: "handoff",
                    detail: "Open this task to review and respond to its pending request.", canApprove: false)
    }
    static func parse(_ snapshot: [String: Any], task: CodeTask) -> [AgentPrompt] {
        (snapshot["requests"] as? [[String: Any]] ?? []).compactMap { request in
            guard let rawID = request["id"], let bytes = try? JSONSerialization.data(withJSONObject: rawID, options: [.fragmentsAllowed, .sortedKeys]),
                  let params = request["params"] as? [String: Any], let method = request["method"] as? String else { return nil }
            let id = String(decoding: bytes, as: UTF8.self)
            var result = AgentPrompt(id: task.id + ":" + id, task: task, kind: .question, requestID: id)
            switch method {
            case "item/tool/requestUserInput":
                guard let questions = params["questions"] as? [[String: Any]], !questions.isEmpty else { return nil }
                result.questions = questions.compactMap { q in
                    guard let id = q["id"] as? String, let title = q["question"] as? String else { return nil }
                    let options = q["options"] as? [[String: Any]] ?? []
                    return AgentQuestion(id: id, title: title, options: options.compactMap { $0["label"] as? String },
                                         descriptions: options.map { $0["description"] as? String ?? "" })
                }
                guard result.questions.count == questions.count else { return nil }
            case "item/commandExecution/requestApproval":
                result.kind = .command
                let command = params["command"] as? String ?? (params["command"] as? [String]).flatMap {
                    (try? JSONSerialization.data(withJSONObject: $0)).map { String(decoding: $0, as: UTF8.self) }
                }
                guard let command, !command.isEmpty else { return nil }
                result.detail = [params["reason"] as? String, params["cwd"] as? String, command].compactMap { $0 }.joined(separator: "\n\n")
                if let decisions = params["availableDecisions"] as? [Any] {
                    result.canApprove = decisions.contains { ($0 as? String) == "accept" }
                }
                let decisions = params["availableDecisions"] as? [Any]
                let offered = decisions?.compactMap { $0 as? [String: Any] }.first { $0["acceptWithExecpolicyAmendment"] != nil }
                let amendment = offered?["acceptWithExecpolicyAmendment"] as? [String: Any]
                let prefix = amendment?["execpolicy_amendment"] as? [String] ?? params["proposedExecpolicyAmendment"] as? [String]
                let allowsRule = decisions == nil || offered != nil || decisions?.contains { $0 as? String == "acceptWithExecpolicyAmendment" } == true
                if allowsRule, let prefix, !prefix.isEmpty, prefix.allSatisfy({ !$0.isEmpty }) {
                    result.alwaysAllowPayload = try? JSONSerialization.data(withJSONObject:
                        ["acceptWithExecpolicyAmendment": ["execpolicy_amendment": prefix]], options: .sortedKeys)
                    result.alwaysAllowScope = "Commands starting with " + prefix.joined(separator: " ")
                }
            case "item/fileChange/requestApproval":
                guard let itemID = params["itemId"] as? String,
                      let turns = snapshot["turns"] as? [[String: Any]],
                      let item = turns.flatMap({ $0["items"] as? [[String: Any]] ?? [] }).first(where: { $0["id"] as? String == itemID }),
                      item["type"] as? String == "fileChange",
                      let changes = item["changes"] as? [[String: Any]], !changes.isEmpty,
                      changes.allSatisfy({ $0["diff"] is String && $0["path"] is String }) else { return Self.handoff(task) }
                result.kind = .fileChange
                result.detail = changes.map { ($0["path"] as! String) + "\n" + ($0["diff"] as! String) }.joined(separator: "\n\n")
            default: return nil // Background protocol requests are not user decisions.
            }
            if result.kind == .command || result.kind == .fileChange {
                let decisions = params["availableDecisions"] as? [Any]
                if let decisions { result.canApprove = decisions.contains { $0 as? String == "accept" } }
                if result.alwaysAllowPayload == nil,
                   decisions?.contains(where: { $0 as? String == "acceptForSession" }) == true {
                    result.alwaysAllowPayload = try? JSONSerialization.data(withJSONObject: "acceptForSession", options: .fragmentsAllowed)
                    result.alwaysAllowScope = result.kind == .fileChange ? "This and future file edits in this task" : "This action for the current task"
                }
                let metadata = params.filter { !["threadId", "turnId", "itemId", "command", "cwd", "reason", "availableDecisions", "proposedExecpolicyAmendment"].contains($0.key) }
                if !metadata.isEmpty, let bytes = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]) {
                    result.detail += "\n\n" + String(decoding: bytes, as: UTF8.self)
                }
            }
            return result
        }
    }
    func respond(_ prompt: AgentPrompt, answer: AgentAnswer) throws {
        let client = try Client(task: prompt.task)
        defer { client.closeConnection() }
        guard let threadID = prompt.task.threadID else { throw AgentActionWire.Failure.invalid }
        if prompt.kind == .asyncQuestion {
            guard !answer.alwaysAllow else { throw AgentActionWire.Failure.invalid }
            guard let current = readCurrentTask(prompt.task), current.activity.state == "running",
                  prompt.questions.allSatisfy({ current.pendingQuestions.contains($0) }) else { throw AgentActionWire.Failure.expired }
            let replies = prompt.questions.map { ["questionItemId": $0.id, "question": $0.title, "answer": answer.answers[$0.id] ?? ""] }
            guard replies.allSatisfy({ !$0["answer"]!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw AgentActionWire.Failure.invalid }
            let body = String(decoding: try JSONSerialization.data(withJSONObject: replies), as: UTF8.self)
            let text = "<send_user_message_question_reply>\n" + body + "\n</send_user_message_question_reply>"
            let messageID = UUID().uuidString
            // Codex uses this composer context to render and restore a steering message,
            // even when the answer contains only text. Omitting it rejects the request.
            let restore: [String: Any] = ["id": messageID, "text": text,
                "createdAt": Date().timeIntervalSince1970 * 1000,
                "context": ["prompt": text, "addedFiles": [], "fileAttachments": [],
                            "ideContext": NSNull(), "imageAttachments": [], "commentAttachments": []]]
            _ = try client.request("thread-follower-steer-turn", params: ["conversationId": threadID,
                "input": [["type": "text", "text": text, "text_elements": []]],
                "restoreMessage": restore, "attachments": [], "clientUserMessageId": messageID],
                target: client.owner, timeout: 30)
            return
        }
        let current = Self.parse(try client.snapshot(), task: prompt.task)
        guard current.contains(prompt) else { throw AgentActionWire.Failure.expired }
        let rawID = try JSONSerialization.jsonObject(with: Data(prompt.requestID.utf8), options: .fragmentsAllowed)
        var params: [String: Any] = ["conversationId": threadID, "requestId": rawID]
        let method: String
        if prompt.kind == .question {
            guard !answer.alwaysAllow else { throw AgentActionWire.Failure.invalid }
            guard prompt.questions.allSatisfy({ !(answer.answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw AgentActionWire.Failure.invalid }
            params["response"] = ["answers": answer.answers.mapValues { ["answers": [$0]] }]
            method = "thread-follower-submit-user-input"
        } else {
            guard let approve = answer.approve else { throw AgentActionWire.Failure.invalid }
            if answer.alwaysAllow {
                guard approve, [.command, .fileChange].contains(prompt.kind), let payload = prompt.alwaysAllowPayload else { throw AgentActionWire.Failure.invalid }
                params["decision"] = try JSONSerialization.jsonObject(with: payload, options: .fragmentsAllowed)
            } else {
                guard !approve || prompt.canApprove else { throw AgentActionWire.Failure.invalid }
                params["decision"] = approve ? "accept" : "decline"
            }
            method = prompt.kind == .fileChange ? "thread-follower-file-approval-decision" : "thread-follower-command-approval-decision"
        }
        _ = try client.request(method, params: params, target: client.owner, timeout: 30)
    }

    private final class Client {
        let fd: Int32
        let task: CodeTask
        var clientID = "initializing-client"
        var owner: String?
        var following = false
        init(task: CodeTask) throws {
            guard let profile = task.profileID, let thread = task.threadID, UUID(uuidString: thread) != nil else { throw AgentActionWire.Failure.invalid }
            self.task = task
            fd = try AgentActionWire.connect(URL(fileURLWithPath: profile).appendingPathComponent("ipc/ipc.sock").path, timeout: 2)
            do {
                let initial = try request("initialize", params: ["clientType": "ordinary-notch"], version: 0)
                guard let result = initial["result"] as? [String: Any], let id = result["clientId"] as? String else { throw AgentActionWire.Failure.invalid }
                clientID = id
                let discovered = try request("thread-owner-discovery", params: ["hostId": "local", "conversationId": thread])
                guard let target = discovered["handledByClientId"] as? String else { throw AgentActionWire.Failure.unavailable }
                owner = target
            } catch { Darwin.close(fd); throw error }
        }
        func request(_ method: String, params: [String: Any], version: Int = 1, target: String? = nil, timeout: Int = 2) throws -> [String: Any] {
            AgentActionWire.configure(fd, timeout: timeout)
            defer { AgentActionWire.configure(fd, timeout: 2) }
            let id = UUID().uuidString
            var value: [String: Any] = ["type": "request", "requestId": id, "sourceClientId": clientID,
                                       "method": method, "version": version, "params": params, "timeoutMs": timeout * 1000]
            if let target { value["targetClientId"] = target }
            try AgentActionWire.send(value, to: fd)
            let deadline = Date().addingTimeInterval(Double(timeout))
            while Date() < deadline {
                let message = try receive()
                if message["requestId"] as? String == id {
                    guard message["resultType"] as? String == "success" else { throw AgentActionWire.Failure.unavailable }
                    return message
                }
            }
            throw AgentActionWire.Failure.unavailable
        }
        func receive() throws -> [String: Any] {
            let message = try AgentActionWire.receive(from: fd)
            if message["type"] as? String == "client-discovery-request", let id = message["requestId"] {
                try AgentActionWire.send(["type": "client-discovery-response", "requestId": id, "response": ["canHandle": false]], to: fd)
            }
            return message
        }
        func snapshot() throws -> [String: Any] {
            try follow(true); following = true
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                let value = try receive()
                guard value["method"] as? String == "thread-stream-state-changed", value["version"] as? Int == 11,
                      value["sourceClientId"] as? String == owner,
                      let params = value["params"] as? [String: Any], params["conversationId"] as? String == task.threadID,
                      let change = params["change"] as? [String: Any], change["type"] as? String == "snapshot",
                      let state = change["conversationState"] as? [String: Any] else { continue }
                return state
            }
            throw AgentActionWire.Failure.unavailable
        }
        func follow(_ value: Bool) throws {
            guard let owner, let thread = task.threadID else { return }
            try AgentActionWire.send(["type": "broadcast", "method": "thread-stream-following-changed", "version": 1,
                                      "sourceClientId": clientID, "targetClientIds": [owner],
                                      "params": ["conversationId": thread, "hostId": "local", "following": value]], to: fd)
        }
        func closeConnection() { if following { try? follow(false) }; Darwin.close(fd) }
    }
}
