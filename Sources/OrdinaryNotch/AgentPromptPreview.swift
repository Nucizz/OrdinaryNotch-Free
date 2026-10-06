import Foundation

/// Developer samples never enter the live request queue or use a real thread ID.
enum AgentPromptPreview: String, CaseIterable, Identifiable {
    case question = "Codex question", approval = "Codex action approval"
    var id: String { rawValue }
    var prompt: AgentPrompt {
        var activity = CodexActivity.idle
        activity.state = "running"
        activity.attention = self == .question ? "question" : "approval"
        activity.taskName = "Test the notch request layout"
        let task = CodeTask(id: "developer-preview", provider: .codex, activity: activity)
        let id = "developer-preview-" + UUID().uuidString
        switch self {
        case .question:
            return AgentPrompt(id: id, task: task, kind: .question, requestID: id, questions: [
                AgentQuestion(id: "layout", title: "Which layout should we use for agent requests?", options: [
                    "Expand to fit the options (Recommended)", "Keep a compact panel", "Open a separate window", "Use the current layout"
                ], descriptions: [
                    "Show every choice and its description together in the notch.",
                    "Keep the request small and reveal more details when needed.",
                    "Move the question into a dedicated window on the desktop.",
                    "Leave the current presentation unchanged for now."
                ]),
                AgentQuestion(id: "notes", title: "Anything else to adjust?", options: [])
            ])
        case .approval:
            return AgentPrompt(id: id, task: task, kind: .command, requestID: id,
                               detail: "Run the focused app tests.\n\nswift test --filter AgentActionTests\n\nThis is a preview. No command will run.",
                               alwaysAllowPayload: Data("{}".utf8), alwaysAllowScope: "Commands starting with swift test (preview only)")
        }
    }
}
