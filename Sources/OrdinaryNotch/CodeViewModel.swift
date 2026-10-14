import Combine
import Foundation

@MainActor
final class CodeViewModel: ObservableObject {
    @Published var activity = CodexActivity.idle { didSet { revision &+= 1 } }
    @Published private(set) var dashboard = CodeDashboard() { didSet { revision &+= 1 } }
    @Published private(set) var navigationError: String?
    private(set) var revision: UInt64 = 0
    private let service: any CodeActivityReading
    private let navigation: any CodeTaskOpening
    private var busy = false
    private var requestedSelection: CodeSelection = .codex
    private var requestedAccount: CodeAccountFilter = .personal
    private var lastRead: TimeInterval = -.infinity
    private var dirty = true
    private var bridge: URL?
    private var monitoring = false
    private var changeRefresh: Task<Void, Never>?
    private let uptime: () -> TimeInterval
    var didRead: ((CodeDashboard, TimeInterval) -> Void)?
    init(service: (any CodeActivityReading)? = nil, navigation: (any CodeTaskOpening)? = nil,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        let service = service ?? CodeActivityService()
        self.service = service
        self.navigation = navigation ?? CodeTaskNavigationService()
        self.uptime = uptime
    }
    func refreshIfNeeded(bridge: URL, selection: CodeSelection, account: CodeAccountFilter, freshnessRequired: Bool = false) {
        if !monitoring {
            monitoring = true
            service.monitorChanges { [weak self] in
                guard let self, self.monitoring else { return }
                self.dirty = true
                guard self.changeRefresh == nil else { return }
                self.changeRefresh = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    guard let self, self.monitoring else { return }
                    self.changeRefresh = nil
                    if let bridge = self.bridge {
                        self.refreshIfNeeded(bridge: bridge, selection: self.requestedSelection, account: self.requestedAccount)
                    }
                }
            }
        }
        let selectionChanged = self.bridge != bridge || requestedSelection != selection || requestedAccount != account
        self.bridge = bridge
        let active = dashboard.tasks.contains { !$0.isUsageOnly && ($0.activity.isWorking || $0.activity.needsInput) }
        let interval: TimeInterval = active ? 2 : freshnessRequired ? 5 : 30
        guard selectionChanged || uptime() - lastRead >= (dirty ? 0.25 : interval) else { return }
        refresh(bridge: bridge, selection: selection, account: account)
    }
    func stopMonitoring() {
        monitoring = false; service.stopMonitoring(); bridge = nil; dirty = true
        changeRefresh?.cancel(); changeRefresh = nil
    }
    func openTask(_ task: CodeTask) {
        navigationError = nil
        do { try navigation.open(task) }
        catch { navigationError = error.localizedDescription }
    }
    func refresh(bridge: URL, selection: CodeSelection = .codex, account: CodeAccountFilter = .personal) {
        requestedSelection = selection; requestedAccount = account
        guard !busy else { return }; busy = true
        lastRead = uptime(); dirty = false
        let sampledAt = ProcessInfo.processInfo.systemUptime
        Task {
            let snapshot = await service.read(bridge: bridge, selection: selection, account: account)
            guard requestedSelection == selection, requestedAccount == account else {
                busy = false
                refresh(bridge: bridge, selection: requestedSelection, account: requestedAccount)
                return
            }
            if dashboard != snapshot { dashboard = snapshot }
            if let primary = snapshot.primary?.activity {
                if activity != primary { activity = primary }
            } else if activity.state != "idle" { activity = .idle }
            busy = false
            didRead?(snapshot, sampledAt)
        }
    }
    func setPreviewTasks(_ tasks: [CodeTask], profileIDs: [CodeAccount: String] = [:]) {
        dashboard = CodeDashboard(tasks: tasks, profileIDs: profileIDs)
        activity = dashboard.primary?.activity ?? .idle
    }
}
