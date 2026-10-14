import AppKit

enum ApplicationNavigationService {
    @MainActor static func openPhotoBooth() async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.PhotoBooth") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
    @MainActor static func openMediaApplication(_ identifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }
    @MainActor static func openProvider(_ provider: CodeProvider) {
        NSWorkspace.shared.open(URL(string: provider == .claude ? "https://claude.ai/new" : "https://chatgpt.com/")!)
    }
    @MainActor static func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) { NSWorkspace.shared.open(url) }
    }
}
