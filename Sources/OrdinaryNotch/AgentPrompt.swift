import Foundation

struct AgentQuestion: Equatable, Identifiable {
    var id: String
    var title: String
    var options: [String]
    var descriptions: [String] = []
    var multiple = false
}
struct AgentPrompt: Equatable, Identifiable {
    enum Kind: String { case asyncQuestion, question, command, fileChange, claudePermission, claudeQuestion, handoff }
    var id: String
    var task: CodeTask
    var kind: Kind
    var requestID: String
    var questions: [AgentQuestion] = []
    var detail: String = ""
    var canApprove = true
    var alwaysAllowPayload: Data? = nil
    var alwaysAllowScope: String? = nil
    var accountTitle: String { task.account.title }
}
struct AgentAnswer: Equatable {
    var answers: [String: String] = [:]
    var approve: Bool? = nil
    var alwaysAllow = false
}
