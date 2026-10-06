import AppKit

@MainActor
protocol CodeActivityReading {
    func read(bridge: URL, selection: CodeSelection, account: CodeAccountFilter) async -> CodeDashboard
}

@MainActor
final class CodeActivityService: CodeActivityReading {
    private let reader = CodexActivityReader()
    private let claude = ClaudeProfileActivityReader()
    private let queue = DispatchQueue(label: "ordinary.code-activity", qos: .utility)
    func read(bridge: URL, selection: CodeSelection, account: CodeAccountFilter) async -> CodeDashboard {
        let reader = reader, claude = claude
        let runningApps = Set(NSWorkspace.shared.runningApplications.compactMap { $0.isTerminated ? nil : $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path })
        return await withCheckedContinuation { continuation in
        queue.async {
            let catalog = CodeProfiles()
            let profiles = CodeAccount.allCases.map { catalog.profile($0) }
            let selected = profiles.filter { account.accounts.contains($0.account) }
            let claudeProfiles = ClaudeProfiles()
            var tasks = (selection.includes(.codex) ? reader.readTasks(profileRoots: selected.map(\.root)) : [])
                + (selection.includes(.claude) ? claude.read(profiles: account.accounts.map { claudeProfiles.profile($0) }) : [])
            if selection.includes(.codex), account.accounts.contains(.personal), !tasks.contains(where: { $0.active && $0.profileID == profiles[0].id }), let data = try? Data(contentsOf: bridge) {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                if let manual = try? decoder.decode(CodexActivity.self, from: data),
                   Date().timeIntervalSince(manual.updatedAt) < 300 {
                    tasks.append(CodeTask(id: "manual", provider: .codex, activity: manual, profileID: profiles[0].id))
                }
            }
            for index in tasks.indices where tasks[index].provider == .codex {
                if let profile = profiles.first(where: { $0.id == tasks[index].profileID }) {
                    tasks[index].account = profile.account
                    tasks[index].appIsRunning = CodeAppPresence.isRunning(profile: profile, runningBundlePaths: runningApps)
                }
            }
            let snapshot = CodeDashboard(tasks: tasks, selection: selection, account: account, profileIDs: Dictionary(uniqueKeysWithValues: profiles.map { ($0.account, $0.id) }))
            continuation.resume(returning: snapshot)
        }
        }
    }
}
