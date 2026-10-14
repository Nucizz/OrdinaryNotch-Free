import AppKit

/// The app yields its own overlay; it never moves or impersonates system dialogs.
@MainActor final class SystemPromptPresentationService {
    static let shared = SystemPromptPresentationService()
    var changed: () -> Void = {}
    private(set) var activeRequests = 0
    private var settingsGraceUntil = Date.distantPast

    func withPrompt<T>(_ operation: () async throws -> T) async rethrows -> T {
        activeRequests += 1; changed()
        defer { activeRequests -= 1; changed() }
        return try await operation()
    }
    func openingPrivacySettings() {
        settingsGraceUntil = Date().addingTimeInterval(2)
        changed()
    }
    func shouldYield() -> Bool {
        shouldYield(frontmostBundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                    modalWindow: NSApp.modalWindow != nil)
    }
    func shouldYield(at now: Date = Date(), frontmostBundle: String?, modalWindow: Bool) -> Bool {
        activeRequests > 0 || now < settingsGraceUntil || modalWindow || Self.isPermissionApplication(frontmostBundle)
    }
    static func isPermissionApplication(_ bundle: String?) -> Bool {
        guard let bundle else { return false }
        return ["com.apple.systempreferences", "com.apple.SecurityAgent", "com.apple.UserNotificationCenter",
                "com.apple.CoreServicesUIAgent", "com.apple.LocalAuthentication.UIAgent"].contains(bundle)
    }
}
