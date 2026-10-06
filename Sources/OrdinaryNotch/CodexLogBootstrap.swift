import Foundation

/// Skip older turns on first attachment, while preserving the latest turn's full lifecycle.
/// Only candidate lifecycle/usage records are decoded during the reverse scan.
enum CodexLogBootstrap {
    static func read(_ handle: FileHandle, size: UInt64, hasUserEvent: Bool) -> (UInt64, CodexSessionStatus) {
        var state = CodexSessionStatus()
        state.hasUserInteraction = hasUserEvent
        // The latest turn can begin megabytes after its developer context. Preserve
        // the approval-review mode before jumping to that turn, otherwise automatic
        // reviews look like unresolved user actions until their command finishes.
        if (try? handle.seek(toOffset: 0)) != nil,
           let prefix = try? handle.read(upToCount: Int(min(size, 256 * 1024))),
           CodexAttention.usesAutomaticApprovalReview(String(decoding: prefix, as: UTF8.self)) {
            state.attention.useAutomaticApprovalReview()
        }
        guard size > 256 * 1024 else { return (0, state) }
        var cursor = size
        var suffix = Data()
        var start: UInt64?
        var terminal: UInt64?
        let startMarker = Data("task_started".utf8), turnMarker = Data("turn_started".utf8)
        let usageMarker = Data("token_count".utf8)
        while cursor > 0 {
            let position = cursor > 262144 ? cursor - 262144 : 0
            guard (try? handle.seek(toOffset: position)) != nil,
                  let bytes = try? handle.read(upToCount: Int(cursor - position)), !bytes.isEmpty else { break }
            var block = bytes; block.append(suffix)
            var end = block.endIndex
            // Only complete newline-delimited records are eligible, including across blocks.
            for index in block.indices.reversed() where block[index] == 10 {
                let begin = index + 1
                if begin < end, let result = consume(block.subdata(in: begin..<end), offset: position + UInt64(begin), start: &start, terminal: &terminal, state: &state, startMarker: startMarker, turnMarker: turnMarker, usageMarker: usageMarker) { return result }
                end = index
            }
            suffix = Data(block.prefix(end))
            if position == 0 {
                if let result = consume(suffix, offset: 0, start: &start, terminal: &terminal, state: &state, startMarker: startMarker, turnMarker: turnMarker, usageMarker: usageMarker) { return result }
            }
            cursor = position
            // Once the latest turn is located, a bounded look-back supplies its preceding quota.
            if let start, start > cursor + 4 * 1024 * 1024 { return (terminal ?? start, state) }
        }
        return (terminal ?? start ?? 0, state)
    }
    private static func consume(_ line: Data, offset: UInt64, start: inout UInt64?, terminal: inout UInt64?, state: inout CodexSessionStatus, startMarker: Data, turnMarker: Data, usageMarker: Data) -> (UInt64, CodexSessionStatus)? {
        let mightStart = start == nil && (line.range(of: startMarker) != nil || line.range(of: turnMarker) != nil)
        let terminalTypes = ["task_complete", "turn_complete", "turn_aborted", "task_failed", "turn_failed", "task_blocked", "turn_blocked"]
        let mightEnd = start == nil && terminal == nil && terminalTypes.contains { line.range(of: Data($0.utf8)) != nil }
        let mightUsage = state.usage == nil && line.range(of: usageMarker) != nil
        guard mightStart || mightEnd || mightUsage,
              let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              event["type"] as? String == "event_msg", let payload = event["payload"] as? [String: Any] else { return nil }
        if mightStart, ["task_started", "turn_started"].contains(payload["type"] as? String ?? "") {
            start = offset
            state.startedAt = CodexSessionStatus.parse(line).startedAt
        }
        if mightEnd, terminalTypes.contains(payload["type"] as? String ?? "") { terminal = offset }
        if mightUsage, payload["type"] as? String == "token_count" {
            state.usage = CodexSessionStatus.parse(line).usage
        }
        if let start, state.usage != nil { return (terminal ?? start, state) }
        return nil
    }
}
