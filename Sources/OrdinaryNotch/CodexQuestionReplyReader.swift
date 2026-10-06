import Foundation
import SQLite3

struct CodexQuestionAnswer: Equatable {
    let callID: String
    let index: Int
    let date: Date
}

/// The app-server receives a submitted answer before a busy turn writes it to the rollout.
/// Retains only call/item IDs and timestamps; answer text is never stored or forwarded.
final class CodexQuestionReplyReader {
    private struct Cache {
        var cursor: Int64 = 0
        var answers: [String: [CodexQuestionAnswer]] = [:]
    }
    private var caches: [String: Cache] = [:]
    private static let textField = try! NSRegularExpression(pattern: #"text: ("(?:\\.|[^"\\])*")"#)
    func read(root: URL, now: Date) -> [String: [CodexQuestionAnswer]] {
        let path = root.appendingPathComponent("logs_2.sqlite").path
        var cache = caches[path] ?? Cache()
        let cutoff = now.addingTimeInterval(-3600)
        cache.answers = cache.answers.mapValues { $0.filter { $0.date >= cutoff } }.filter { !$0.value.isEmpty }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            return cache.answers
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 20)
        var maximum: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MAX(id) FROM logs", -1, &maximum, nil) == SQLITE_OK else { return cache.answers }
        let result = sqlite3_step(maximum)
        let end = result == SQLITE_ROW ? sqlite3_column_int64(maximum, 0) : cache.cursor
        sqlite3_finalize(maximum)
        if end < cache.cursor { cache = Cache() }
        if end == cache.cursor { caches[path] = cache; return cache.answers }
        // The initial scan uses the timestamp index; later scans cover only newly appended rows.
        let condition = cache.cursor == 0 ? "ts >= ? AND id <= ?" : "id > ? AND id <= ?"
        let sql = "SELECT ts, ts_nanos, thread_id, feedback_log_body FROM logs WHERE \(condition) AND target = 'codex_core::session::handlers' AND feedback_log_body LIKE '%<send_user_message_question_reply>%' ORDER BY id"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return cache.answers }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, cache.cursor == 0 ? Int64(cutoff.timeIntervalSince1970) : cache.cursor)
        sqlite3_bind_int64(statement, 2, end)
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            if let thread = sqlite3_column_text(statement, 2), let body = sqlite3_column_text(statement, 3) {
                let date = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 0)) + Double(sqlite3_column_int64(statement, 1)) / 1_000_000_000)
                if date >= cutoff && date <= now.addingTimeInterval(5) {
                    let threadID = String(cString: thread)
                    for answer in Self.parse(String(cString: body), at: date) {
                        var items = cache.answers[threadID] ?? []
                        items.removeAll { $0.callID == answer.callID && $0.index == answer.index }
                        items.append(answer)
                        cache.answers[threadID] = Array(items.suffix(256))
                    }
                }
            }
            step = sqlite3_step(statement)
        }
        // A busy/error result must be retried, not acknowledged as fully consumed.
        if step == SQLITE_DONE { cache.cursor = end }
        caches[path] = cache
        return cache.answers
    }
    static func parse(_ body: String, at date: Date) -> [CodexQuestionAnswer] {
        guard body.contains(": Submission sub=Submission {"),
              body.contains("op: TurnInput { request: TurnInputRequest { input: UserInput { content:") else { return [] }
        let ns = body as NSString
        var answers: [CodexQuestionAnswer] = []
        for match in textField.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            let quoted = ns.substring(with: match.range(at: 1))
            guard let text = try? JSONSerialization.jsonObject(with: Data(quoted.utf8), options: .fragmentsAllowed) as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let opening = "<send_user_message_question_reply>"
            guard trimmed.hasPrefix(opening), let end = trimmed.range(of: "</send_user_message_question_reply>") else { continue }
            let data = Data(trimmed[trimmed.index(trimmed.startIndex, offsetBy: opening.count)..<end.lowerBound].utf8)
            guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            for item in items {
                guard let encoded = item["questionItemId"] as? String,
                      let id = try? JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [Any],
                      id.count >= 3, let callID = id[1] as? String, !callID.isEmpty,
                      let index = id[2] as? Int, index >= 0 else { continue }
                answers.append(CodexQuestionAnswer(callID: callID, index: index, date: date))
            }
        }
        return answers
    }
}
