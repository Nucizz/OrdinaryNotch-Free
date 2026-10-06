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
    func open(_ pane: String)
    func hooksInstalled() -> Bool
    func setHooksEnabled(_ enabled: Bool) throws
}
@MainActor
struct PrivacyService: PrivacyServing {
    var cameraGranted: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    func requestCamera() async {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
        else { open("Camera") }
    }
    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        open("Accessibility")
    }
    func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) { NSWorkspace.shared.open(url) }
    }
    func hooksInstalled() -> Bool { ClaudeHookSetup.installed() }
    func setHooksEnabled(_ enabled: Bool) throws {
        try ClaudeHookSetup.install(executable: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/OrdinaryActivityBridge"), enabled: enabled)
    }
}
