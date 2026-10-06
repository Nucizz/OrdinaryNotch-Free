import Foundation

enum CodeChannel: String, Codable, CaseIterable, Identifiable {
    case gpt, claude
    var id: String { rawValue }
    var provider: CodeProvider { self == .gpt ? .codex : .claude }
    var account: CodeAccount { .personal }
    var title: String { self == .gpt ? "GPT" : "Claude" }
    func title(in channels: [CodeChannel]) -> String { title }
}

enum CodeLayout: String, Codable, CaseIterable, Identifiable {
    case gptClaude, claudeGPT, gptOnly, claudeOnly
    var id: String { rawValue }
    var channels: [CodeChannel] {
        switch self {
        case .gptClaude: [.gpt, .claude]
        case .claudeGPT: [.claude, .gpt]
        case .gptOnly: [.gpt]
        case .claudeOnly: [.claude]
        }
    }
    var title: String {
        channels.count == 1 ? channels[0].title + " only" : channels.map { $0.title(in: channels) }.joined(separator: "  ·  ")
    }
}

extension NotchSettings {
    var selectedCodeLayout: CodeLayout {
        codeLayout ?? (codeSelection == .claude ? .claudeOnly : .gptOnly)
    }
    var codeChannels: [CodeChannel] { selectedCodeLayout.channels }
}
