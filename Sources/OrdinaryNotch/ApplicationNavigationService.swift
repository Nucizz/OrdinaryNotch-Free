import AppKit

enum ApplicationNavigationService {
    @MainActor static func openProvider(_ provider: CodeProvider) {
        NSWorkspace.shared.open(URL(string: provider == .claude ? "https://claude.ai/new" : "https://chatgpt.com/")!)
    }
    @MainActor static func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) { NSWorkspace.shared.open(url) }
    }
}
