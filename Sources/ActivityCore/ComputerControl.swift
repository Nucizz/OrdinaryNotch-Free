import Foundation

/// Recognizes explicit UI actions, never arbitrary shell commands or quoted source text.
public enum ComputerControlTool {
    public static func isControl(name: String, input: [String: Any]) -> Bool {
        let parts = name.replacingOccurrences(of: ".", with: "__").components(separatedBy: "__")
        let tool = parts.last ?? name
        if tool == "computer" || tool.hasPrefix("computer_20") {
            let actions: Set<String> = ["left_click", "right_click", "middle_click", "double_click", "triple_click",
                "left_click_drag", "mouse_move", "key", "type", "scroll", "left_mouse_down", "left_mouse_up", "hold_key"]
            return actions.contains(input["action"] as? String ?? "")
        }
        guard name.contains("cua_repl"), tool == "js", let code = input["code"] as? String else { return false }
        let source = code.replacingOccurrences(of: #"(?s)/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#,
                                              with: " ", options: .regularExpression)
        return source.range(of: #"\.(click|dblclick|doubleClick|fill|type|typeText|press|keypress|keyPress|scroll|drag|dragAndDrop|selectOption|check|uncheck|hover|goto|navigate|back|forward|reload|close|createBrowserTab)\s*\("#,
                            options: .regularExpression) != nil
    }
}

public struct ComputerControlState: Codable, Equatable {
    public private(set) var lastStartedAt: Date?
    public private(set) var lastActionAt: Date?
    private var pending: [String: Date] = [:]
    public init() {}
    public mutating func start(_ id: String, at date: Date) {
        pending = pending.filter { date.timeIntervalSince($0.value) < 120 }
        guard pending[id] == nil else { return }
        pending[id] = date
        lastStartedAt = max(lastStartedAt ?? date, date)
        lastActionAt = max(lastActionAt ?? date, date)
    }
    public mutating func finish(_ id: String, at date: Date) {
        guard pending.removeValue(forKey: id) != nil else { return }
        lastActionAt = max(lastActionAt ?? date, date)
    }
    public mutating func reset() { self = Self() }
    public func isActive(at now: Date) -> Bool {
        if pending.values.contains(where: { (0...120).contains(now.timeIntervalSince($0)) }) { return true }
        return lastActionAt.map { (0...8).contains(now.timeIntervalSince($0)) } ?? false
    }
}
