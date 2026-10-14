import AppKit

@MainActor
protocol CodeActivityReading {
    func read(bridge: URL, selection: CodeSelection, account: CodeAccountFilter) async -> CodeDashboard
    func monitorChanges(_ changed: @escaping @MainActor () -> Void)
    func stopMonitoring()
}
extension CodeActivityReading {
    func monitorChanges(_ changed: @escaping @MainActor () -> Void) {}
    func stopMonitoring() {}
}

@MainActor
final class CodeActivityService: CodeActivityReading {
    private let reader = CodexActivityReader()
    private let claude = ClaudeProfileActivityReader()
    private let queue = DispatchQueue(label: "ordinary.code-activity", qos: .utility)
    private let changes = FileChangeMonitor()
    private var changed: (@MainActor () -> Void)?
    private var applicationObservers: [NSObjectProtocol] = []
    private var runningApps: Set<String>?
    private var profiles: [CodeProfile] = []
    private var claudeProfiles: [CodeProfile] = []
    private var catalogRead = Date.distantPast
    func monitorChanges(_ changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        guard applicationObservers.isEmpty else { return }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            applicationObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.runningApps = nil; self?.catalogRead = .distantPast; self?.changed?()
                }
            })
        }
    }
    func stopMonitoring() {
        changed = nil; changes.stop()
        applicationObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        applicationObservers = []; runningApps = nil
    }
    func read(bridge: URL, selection: CodeSelection, account: CodeAccountFilter) async -> CodeDashboard {
        let reader = reader, claude = claude
        if Date().timeIntervalSince(catalogRead) >= 30 {
            let catalog = CodeProfiles(), claudeCatalog = ClaudeProfiles()
            profiles = CodeAccount.allCases.map { catalog.profile($0) }
            claudeProfiles = CodeAccount.allCases.map { claudeCatalog.profile($0) }
            catalogRead = Date()
            if applicationObservers.isEmpty { runningApps = nil }
        }
        if runningApps == nil {
            runningApps = Set(NSWorkspace.shared.runningApplications.compactMap { $0.isTerminated ? nil : $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path })
        }
        let runningApps = runningApps ?? [], profiles = profiles
        let selected = profiles.filter { account.accounts.contains($0.account) }
        let selectedClaude = claudeProfiles.filter { account.accounts.contains($0.account) }
        if changed != nil {
            let roots = (selection.includes(.codex) ? selected.map(\.root) : [])
                + (selection.includes(.claude) ? selectedClaude.map(\.root) : []) + [bridge]
            changes.watch(roots) { [weak self] in Task { @MainActor in self?.changed?() } }
        }
        return await withCheckedContinuation { continuation in
        queue.async {
            let profilesByID = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let presence = profilesByID.mapValues { CodeAppPresence.isRunning(profile: $0, runningBundlePaths: runningApps) }
            var tasks = (selection.includes(.codex) ? reader.readTasks(profileRoots: selected.map(\.root)) : [])
                + (selection.includes(.claude) ? claude.read(profiles: selectedClaude) : [])
            var health = CodeMonitoringHealth(available: (!selection.includes(.codex) || reader.monitoringAvailable)
                && (!selection.includes(.claude) || claude.monitoringAvailable))
            if selection.includes(.codex), account.accounts.contains(.personal), !tasks.contains(where: { $0.active && $0.profileID == profiles[0].id }), let data = health.dataIfPresent(at: bridge) {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                if let manual = try? decoder.decode(CodexActivity.self, from: data) {
                    if Date().timeIntervalSince(manual.updatedAt) < 300 {
                        tasks.append(CodeTask(id: "manual", provider: .codex, activity: manual, profileID: profiles[0].id))
                    } else if !["idle", "complete", "stopped", "failed"].contains(manual.state) || manual.goalStartedAt != nil {
                        health.available = false
                    }
                } else { health.available = false }
            }
            for index in tasks.indices where tasks[index].provider == .codex {
                if let profileID = tasks[index].profileID, let profile = profilesByID[profileID] {
                    tasks[index].account = profile.account
                    tasks[index].sourceApplication = profile.runtime
                    tasks[index].appIsRunning = presence[profileID] ?? false
                }
            }
            let snapshot = CodeDashboard(tasks: tasks, selection: selection, account: account, profileIDs: Dictionary(uniqueKeysWithValues: profiles.map { ($0.account, $0.id) }), monitoringAvailable: health.available)
            continuation.resume(returning: snapshot)
        }
        }
    }
}
