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
    init(service: (any CodeActivityReading)? = nil, navigation: (any CodeTaskOpening)? = nil) {
        let service = service ?? CodeActivityService()
        self.service = service
        self.navigation = navigation ?? CodeTaskNavigationService()
    }
    func openTask(_ task: CodeTask) {
        navigationError = nil
        do { try navigation.open(task) }
        catch { navigationError = error.localizedDescription }
    }
    func refresh(bridge: URL, selection: CodeSelection = .codex, account: CodeAccountFilter = .personal) {
        requestedSelection = selection; requestedAccount = account
        guard !busy else { return }; busy = true
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
        }
    }
    func setPreviewTasks(_ tasks: [CodeTask], profileIDs: [CodeAccount: String] = [:]) {
        dashboard = CodeDashboard(tasks: tasks, profileIDs: profileIDs)
        activity = dashboard.primary?.activity ?? .idle
    }
}
