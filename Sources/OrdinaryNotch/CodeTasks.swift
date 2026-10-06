import Foundation

enum CodeProvider: String, Codable, CaseIterable {
    case codex, claude
    var title: String { self == .codex ? "Codex" : "Claude Code" }
}

enum CodeSelection: String, Codable, CaseIterable {
    case codex, claude, both
    var title: String {
        switch self { case .codex: "Codex"; case .claude: "Claude Code"; case .both: "GPT & Claude" }
    }
    func includes(_ provider: CodeProvider) -> Bool { self == .both || rawValue == provider.rawValue }
}

struct CodeTask: Identifiable, Equatable {
    var id: String
    let provider: CodeProvider
    var activity: CodexActivity
    var profileID: String? = nil
    var appIsRunning = true
    var completionWasRead = false
    var threadID: String? = nil
    var account: CodeAccount = .personal
    var sourceApplication: URL? = nil
    var isUsageOnly = false
    var pendingQuestions: [AgentQuestion] = []
    var conversationURL: URL? {
        guard let threadID, UUID(uuidString: threadID) != nil else { return nil }
        switch provider {
        case .codex: return URL(string: "codex://threads/\(threadID)")
        case .claude: return URL(string: "claude://resume?session=\(threadID)")
        }
    }
    var shouldDisplay: Bool { !isUsageOnly && appIsRunning && !(activity.state == "complete" && completionWasRead) }
    var active: Bool { shouldDisplay && (activity.isRunning || activity.needsInput) }
}

struct CodeDashboard: Equatable {
    var tasks: [CodeTask] = [] { didSet { rebuild() } }
    var selection: CodeSelection? = nil { didSet { rebuild() } }
    var account: CodeAccountFilter = .personal
    var profileIDs: [CodeAccount: String] = [:]
    func selecting(_ choice: CodeSelection, account: CodeAccountFilter = .personal, profileID: String? = nil) -> Self {
        let allowed = profileID.map { [$0] } ?? account.accounts.compactMap { profileIDs[$0] }
        return Self(tasks: tasks.filter { choice.includes($0.provider) && ($0.provider != .codex || allowed.isEmpty || allowed.contains($0.profileID ?? "")) }, selection: choice, account: account, profileIDs: profileIDs)
    }
    func account(for task: CodeTask) -> CodeAccount? {
        task.provider == .claude ? task.account : profileIDs.first { $0.value == task.profileID }?.key
    }
    func forChannel(_ channel: CodeChannel) -> Self {
        let matches = tasks.filter { task in
            guard task.provider == channel.provider else { return false }
            if task.provider == .claude { return task.account == channel.account }
            if let profile = profileIDs[channel.account] { return task.profileID == profile }
            return task.account == channel.account
        }
        return Self(tasks: matches, selection: channel.provider == .codex ? .codex : .claude,
                    account: .personal, profileIDs: profileIDs)
    }
    func usage(for account: CodeAccount) -> CodexUsage? {
        guard let profileID = profileIDs[account] else { return self.account.accounts == [account] ? usage : nil }
        return tasks.filter { $0.provider == .codex && $0.profileID == profileID }
            .compactMap { $0.activity.usage }.max { $0.updatedAt < $1.updatedAt }
    }
    var activeTasks: [CodeTask] { tasks.filter(\.active) }
    private(set) var provider: CodeProvider = .codex
    private(set) var ordered: [CodeTask] = []
    private var compactTask: CodeTask?
    init(tasks: [CodeTask] = [], selection: CodeSelection? = nil, account: CodeAccountFilter = .personal, profileIDs: [CodeAccount: String] = [:]) {
        self.tasks = tasks; self.selection = selection; self.account = account; self.profileIDs = profileIDs
        rebuild()
    }
    private var preferredProvider: CodeProvider {
        if let selection, selection != .both { return selection == .claude ? .claude : .codex }
        let candidates = activeTasks
        if candidates.contains(where: { $0.provider == .codex }) { return .codex }
        return candidates.first?.provider ?? tasks.max { $0.activity.updatedAt < $1.activity.updatedAt }?.provider ?? .codex
    }
    private mutating func rebuild() {
        provider = preferredProvider
        let preferred = provider
        ordered = tasks.filter(\.shouldDisplay).sorted {
            if $0.active != $1.active { return $0.active }
            if $0.provider != $1.provider { return $0.provider == preferred }
            if $0.activity.needsInput != $1.activity.needsInput { return $0.activity.needsInput }
            if $0.activity.updatedAt != $1.activity.updatedAt { return $0.activity.updatedAt > $1.activity.updatedAt }
            return $0.id < $1.id
        }
        compactTask = ordered.first { $0.activity.needsInput }
        if compactTask == nil {
            // Earlier start means greater elapsed time for every common clock tick.
            compactTask = ordered.lazy.filter { $0.activity.isWorking }.min {
                let lhs = $0.activity.timerStartedAt ?? .distantFuture, rhs = $1.activity.timerStartedAt ?? .distantFuture
                return lhs == rhs ? $0.id < $1.id : lhs < rhs
            }
        }
        if compactTask == nil { compactTask = ordered.first { $0.activity.state == "complete" } }
    }
    func compactActivity(at now: Date) -> CodexActivity? { compactTask?.activity }
    var compactProvider: CodeProvider? { compactTask?.provider }
    var visible: [CodeTask] { Array(ordered.prefix(2)) }
    var primary: CodeTask? { ordered.first }
    var runningCount: Int { tasks.filter { $0.shouldDisplay && $0.activity.isWorking }.count }
    var waitingCount: Int { tasks.filter { $0.shouldDisplay && $0.activity.needsInput }.count }
    var usage: CodexUsage? {
        // Hidden/read tasks still carry account-wide usage snapshots.
        let providerTasks = tasks.filter { $0.provider == provider }
        let fallbackProfile = Set(providerTasks.compactMap(\.profileID)).count == 1 ? providerTasks.first?.profileID : nil
        let profileID = provider == .codex && account.accounts.count == 1
            ? profileIDs[account.accounts[0]] ?? primary?.profileID ?? fallbackProfile : primary?.profileID ?? fallbackProfile
        return providerTasks.filter { $0.profileID == profileID }
            .compactMap { $0.activity.usage }.max { $0.updatedAt < $1.updatedAt }
    }
}
