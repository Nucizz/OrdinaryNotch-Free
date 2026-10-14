import Foundation

enum CodeAccount: String, Codable, CaseIterable {
    case personal
    var title: String { "Personal" }
}

enum CodeAccountFilter: String, Codable, CaseIterable {
    case personal
    var title: String { rawValue.capitalized }
    var accounts: [CodeAccount] { [.personal] }
}

struct CodeProfile: Equatable {
    let account: CodeAccount
    let root: URL
    let launcher: URL?
    var runtime: URL? = nil
    var id: String { root.standardizedFileURL.resolvingSymlinksInPath().path }
}

struct CodeProfiles {
    var home = FileManager.default.homeDirectoryForCurrentUser
    var applications = URL(fileURLWithPath: "/Applications")
    func profile(_ account: CodeAccount) -> CodeProfile {
        let fallback = home.appendingPathComponent(".codex")
        let app = applications.appendingPathComponent("ChatGPT.app")
        return CodeProfile(account: .personal, root: fallback, launcher: app, runtime: app)
    }
}
