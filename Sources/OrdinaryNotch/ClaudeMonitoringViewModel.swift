import Foundation
import Combine
import ActivityCore

@MainActor
final class ClaudeMonitoringViewModel: ObservableObject {
    @Published private(set) var enabled: Set<CodeAccount> = []
    @Published private(set) var message: String?
    func refresh() {
        let profiles = ClaudeProfiles()
        enabled = Set(CodeAccount.allCases.filter { ClaudeMonitoringSetup.installed(root: profiles.profile($0).root) })
    }
    func enable(_ account: CodeAccount) {
        let profiles = ClaudeProfiles()

        do {
            try ClaudeMonitoringSetup.install(root: profiles.profile(account).root,
                executable: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/OrdinaryActivityBridge"))
            message = "Monitoring enabled. Restart Claude Code sessions to receive tasks and usage."
        } catch { message = error.localizedDescription }
        refresh()
    }
    func disable(_ account: CodeAccount) {
        do {
            try ClaudeMonitoringSetup.remove(root: ClaudeProfiles().profile(account).root)
            message = "Usage monitoring disabled. Your previous status line was restored."
        } catch { message = error.localizedDescription }
        refresh()
    }
}
