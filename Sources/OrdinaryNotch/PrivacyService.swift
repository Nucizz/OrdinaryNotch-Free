import AppKit
import AVFoundation
import ApplicationServices
import ActivityCore

@MainActor
protocol PrivacyServing {
    var cameraGranted: Bool { get }
    var accessibilityGranted: Bool { get }
    func requestCamera() async
    func requestAccessibility()
    func repairAccessibility() async throws
    func open(_ pane: String)
    func hooksInstalled() -> Bool
    func setHooksEnabled(_ enabled: Bool) throws
}
extension PrivacyServing {
    func allowAccessibility() async throws {
        if accessibilityGranted { requestAccessibility() }
        else { try await repairAccessibility() }
    }
}
@MainActor
struct PrivacyService: PrivacyServing {
    var cameraGranted: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    func requestCamera() async {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await SystemPromptPresentationService.shared.withPrompt { await AVCaptureDevice.requestAccess(for: .video) }
        }
        else { open("Camera") }
    }
    func requestAccessibility() {
        SystemPromptPresentationService.shared.openingPrivacySettings()
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        open("Accessibility")
    }
    /// Only explicit Allow/Manage actions may reset this app's denied or stale grant.
    func repairAccessibility() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", "dev.ordinary.notch"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 { continuation.resume() }
                else { continuation.resume(throwing: NSError(domain: "AccessibilityRepair", code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Could not reset Accessibility. Remove Ordinary Notch from System Settings → Privacy & Security → Accessibility, then add it again."])) }
            }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
        requestAccessibility()
    }
    func open(_ pane: String) {
        SystemPromptPresentationService.shared.openingPrivacySettings()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) { NSWorkspace.shared.open(url) }
    }
    func hooksInstalled() -> Bool { ClaudeHookSetup.installed() }
    func setHooksEnabled(_ enabled: Bool) throws {
        try ClaudeHookSetup.install(executable: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/OrdinaryActivityBridge"), enabled: enabled)
    }
}
