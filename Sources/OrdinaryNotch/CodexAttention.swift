import Foundation

/// Tracks request IDs, never the contents of answers or tool results.
struct CodexAttention {
    private var questions: [String: Set<Int>] = [:]
    private var questionDetails: [String: [AgentQuestion]] = [:]
    var pendingAsyncQuestions: [AgentQuestion] {
        questionDetails.keys.sorted().flatMap { call in
            (questionDetails[call] ?? []).enumerated().compactMap { index, question in
                questions[call]?.contains(index) == true ? question : nil
            }
        }
    }
    private var synchronousQuestions = Set<String>()
    private var approvals = Set<String>()
    private var approvalCells: [String: String] = [:]
    private var waits: [String: String] = [:]
    private var approvalsAreAutomatic = false
    var reason: String? { !approvals.isEmpty ? "approval" : (!questions.isEmpty ? "question" : nil) }

    mutating func acknowledge(call: String, index: Int) {
        questions[call]?.remove(index)
        if questions[call]?.isEmpty == true {
            questions.removeValue(forKey: call)
            questionDetails.removeValue(forKey: call)
            synchronousQuestions.remove(call)
        }
    }
    mutating func finishTurn() {
        approvals.removeAll(); approvalCells.removeAll(); waits.removeAll()
    }
    mutating func clearPendingRequests() {
        finishTurn()
        questions.removeAll(); questionDetails.removeAll(); synchronousQuestions.removeAll()
    }
    mutating func useAutomaticApprovalReview() {
        approvalsAreAutomatic = true
        approvals.removeAll(); approvalCells.removeAll(); waits.removeAll()
    }
    static func usesAutomaticApprovalReview(_ text: String) -> Bool {
        text.range(of: #"approvals_reviewer.{0,80}auto_review"#, options: .regularExpression) != nil
    }
    mutating func observe(_ payload: [String: Any]) {
        if payload["role"] as? String == "developer", let content = payload["content"] as? [[String: Any]] {
            let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if Self.usesAutomaticApprovalReview(text) { useAutomaticApprovalReview() }
        }
        if payload["role"] as? String == "user", let content = payload["content"] as? [[String: Any]] {
            for part in content {
                guard let text = part["text"] as? String else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("<send_user_message_question_reply>"),
                   let start = trimmed.firstIndex(of: ">"), let end = trimmed.range(of: "</send_user_message_question_reply>") {
                    let body = String(trimmed[trimmed.index(after: start)..<end.lowerBound])
                    if let replies = Self.json(body) as? [[String: Any]] {
                        for reply in replies {
                            guard let item = reply["questionItemId"] as? String, let id = Self.json(item) as? [Any],
                                  id.count >= 3, let call = id[1] as? String, let index = id[2] as? Int else { continue }
                            acknowledge(call: call, index: index)
                        }
                    }
                } else if !trimmed.isEmpty && !trimmed.hasPrefix("<") {
                    // A fresh user request supersedes older unanswered prompts.
                    questions.removeAll(); questionDetails.removeAll(); synchronousQuestions.removeAll()
                }
            }
        }
        guard let type = payload["type"] as? String, let call = payload["call_id"] as? String else { return }
        if type == "function_call" || type == "custom_tool_call" {
            let name = (payload["name"] as? String ?? "").components(separatedBy: ".").last ?? ""
            let raw = payload["arguments"] as? String ?? payload["input"] as? String ?? ""
            let arguments = Self.json(raw) as? [String: Any]
            if name == "request_user_input" || name == "request_user_input_async" {
                let count = (arguments?["questions"] as? [Any])?.count ?? 1
                if count > 0 { questions[call] = Set(0..<count) }
                if name == "request_user_input" { synchronousQuestions.insert(call) }
                else if let items = arguments?["questions"] as? [[String: Any]] {
                    questionDetails[call] = items.enumerated().map { index, item in
                        let encoded = try! JSONSerialization.data(withJSONObject: ["request_user_input_async", call, index])
                        return AgentQuestion(id: String(decoding: encoded, as: UTF8.self), title: item["title"] as? String ?? "Question",
                                             options: item["options"] as? [String] ?? [])
                    }
                }
            } else if name == "exec_command", !approvalsAreAutomatic,
                      arguments?["sandbox_permissions"] as? String == "require_escalated" {
                approvals.insert(call)
            } else if name == "exec", !approvalsAreAutomatic, Self.requestsEscalation(raw) {
                approvals.insert(call)
            } else if name == "wait", let cell = arguments?["cell_id"] as? String, let approval = approvalCells[cell] {
                waits[call] = approval
            }
        } else if type == "function_call_output" || type == "custom_tool_call_output" {
            if synchronousQuestions.remove(call) != nil { questions.removeValue(forKey: call) }
            let output = payload["output"] as? String ?? ""
            if let result = Self.json(output) as? [String: Any], result["accepted"] as? Bool == false {
                questions.removeValue(forKey: call)
                questionDetails.removeValue(forKey: call)
            }
            let approval = waits.removeValue(forKey: call) ?? call
            if approvals.contains(approval) {
                if let range = output.range(of: #"Script running with cell ID\s+([^\s]+)"#, options: .regularExpression) {
                    let cell = output[range].split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
                    approvalCells[cell] = approval
                } else {
                    approvals.remove(approval)
                    approvalCells = approvalCells.filter { $0.value != approval }
                }
            }
        }
    }
    private static func json(_ text: String) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    /// Reads only the top-level options passed to tools.exec_command. Searching the
    /// raw wrapper text misclassifies harmless commands that merely print or grep
    /// the words `sandbox_permissions: require_escalated`.
    private static func requestsEscalation(_ source: String) -> Bool {
        guard let marker = source.range(of: "tools.exec_command") else { return false }
        let bytes = Array(source[marker.lowerBound...].utf8)
        guard let object = bytes.firstIndex(of: 123) else { return false } // {
        var index = object + 1
        while index < bytes.count {
            skipWhitespaceAndCommas(bytes, &index)
            guard index < bytes.count, bytes[index] != 125 else { return false } // }
            guard let key = token(bytes, &index) else { index += 1; continue }
            skipWhitespace(bytes, &index)
            guard index < bytes.count, bytes[index] == 58 else { skipValue(bytes, &index); continue } // :
            index += 1
            skipWhitespace(bytes, &index)
            if key == "sandbox_permissions" { return token(bytes, &index) == "require_escalated" }
            skipValue(bytes, &index)
        }
        return false
    }
    private static func token(_ bytes: [UInt8], _ index: inout Int) -> String? {
        guard index < bytes.count else { return nil }
        if bytes[index] == 34 || bytes[index] == 39 { // " or '
            let quote = bytes[index]
            index += 1
            var value: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 92, index + 1 < bytes.count { value.append(bytes[index + 1]); index += 2; continue }
                index += 1
                if byte == quote { return String(bytes: value, encoding: .utf8) }
                value.append(byte)
            }
            return nil
        }
        let start = index
        while index < bytes.count,
              (bytes[index] == 95 || bytes[index] == 36 || bytes[index] >= 48 && bytes[index] <= 57 ||
               bytes[index] >= 65 && bytes[index] <= 90 || bytes[index] >= 97 && bytes[index] <= 122) { index += 1 }
        return index > start ? String(bytes: bytes[start..<index], encoding: .utf8) : nil
    }
    private static func skipWhitespace(_ bytes: [UInt8], _ index: inout Int) {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    private static func skipWhitespaceAndCommas(_ bytes: [UInt8], _ index: inout Int) {
        while index < bytes.count, [9, 10, 13, 32, 44].contains(bytes[index]) { index += 1 }
    }
    private static func skipValue(_ bytes: [UInt8], _ index: inout Int) {
        var nested = 0
        var quote: UInt8?
        while index < bytes.count {
            let byte = bytes[index]
            if let activeQuote = quote {
                if byte == 92 { index = min(bytes.count, index + 2); continue }
                index += 1
                if byte == activeQuote { quote = nil }
                continue
            }
            if byte == 34 || byte == 39 { quote = byte; index += 1; continue }
            if [123, 91, 40].contains(byte) { nested += 1; index += 1; continue } // { [ (
            if [125, 93, 41].contains(byte) {
                if nested == 0 { return }
                nested -= 1; index += 1; continue
            }
            if byte == 44, nested == 0 { index += 1; return }
            index += 1
        }
    }
}
