import Foundation
import ActivityCore
struct ClaudeProfiles {
    var home = FileManager.default.homeDirectoryForCurrentUser
    var applications = URL(fileURLWithPath: "/Applications")
    func profile(_ account: CodeAccount) -> CodeProfile {
        let root = home == FileManager.default.homeDirectoryForCurrentUser ? ClaudeHookSetup.configURL.deletingLastPathComponent() : home.appendingPathComponent(".claude")
        let app = applications.appendingPathComponent("Claude.app")
        return CodeProfile(account: .personal, root: root, launcher: app, runtime: app)
    }
}
