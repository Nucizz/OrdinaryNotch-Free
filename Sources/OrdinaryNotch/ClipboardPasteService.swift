import AppKit
import ApplicationServices
import Carbon

enum ClipboardPasteResult: Equatable {
    case sent, permissionRequired, destinationChanged, clipboardChanged, cancelled
    var message: String? {
        switch self {
        case .sent, .cancelled: return nil
        case .permissionRequired: return "Copied. Allow Ordinary Notch in Accessibility to paste automatically, or use ⌘V."
        case .destinationChanged: return "Copied. The original field is no longer active; use ⌘V to paste."
        case .clipboardChanged: return "The clipboard changed before pasting. Select the item again."
        }
    }
}

@MainActor protocol ClipboardPasting: AnyObject {
    func captureDestination()
    func prepareToPaste() -> ClipboardPasteResult?
    func paste() async -> ClipboardPasteResult
    func cancel()
}

@MainActor protocol ClipboardPasteSystem: AnyObject {
    var clipboardChange: Int { get }
    var sessionIsActive: Bool { get }
    func captureDestination() -> pid_t?
    func isCurrentDestination(_ pid: pid_t) -> Bool
    func hasPermission(for pid: pid_t) -> Bool
    func requestPermission()
    func postPaste(to pid: pid_t) -> Bool
}

@MainActor final class ClipboardPasteService: ClipboardPasting {
    private let system: ClipboardPasteSystem
    private var destination: pid_t?
    private var generation = UUID()
    init(system: ClipboardPasteSystem? = nil) { self.system = system ?? MacClipboardPasteSystem() }
    func captureDestination() {
        cancel()
        destination = system.captureDestination()
    }
    func prepareToPaste() -> ClipboardPasteResult? {
        guard let destination, system.sessionIsActive, system.isCurrentDestination(destination) else { return .destinationChanged }
        guard system.hasPermission(for: destination) else {
            system.requestPermission() // Only an explicit Return-to-paste requests access.
            return .permissionRequired
        }
        return nil
    }
    func paste() async -> ClipboardPasteResult {
        guard let destination else { return .destinationChanged }
        let generation = generation, change = system.clipboardChange
        // Let the nonactivating panel relinquish keyboard focus before delivering ⌘V.
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return .cancelled }
        guard !Task.isCancelled, generation == self.generation else { return .cancelled }
        guard system.sessionIsActive, system.isCurrentDestination(destination) else { return .destinationChanged }
        guard system.clipboardChange == change else { return .clipboardChanged }
        guard system.hasPermission(for: destination) else { return .permissionRequired }
        return system.postPaste(to: destination) ? .sent : .destinationChanged
    }
    func cancel() { generation = UUID(); destination = nil }
    static func pasteEvents() -> (CGEvent, CGEvent)? {
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return nil }
        down.flags = .maskCommand; up.flags = .maskCommand
        return (down, up)
    }
}

@MainActor private final class MacClipboardPasteSystem: ClipboardPasteSystem {
    private var application: NSRunningApplication?
    private weak var window: NSWindow?
    private weak var responder: NSResponder?
    var clipboardChange: Int { NSPasteboard.general.changeCount }
    var sessionIsActive: Bool {
        let session = SessionLockSnapshot.read()
        return session.currentConsoleUser && !session.locked
    }
    func captureDestination() -> pid_t? {
        application = NSWorkspace.shared.frontmostApplication
        window = application?.processIdentifier == getpid() ? NSApp.keyWindow : nil
        responder = window?.firstResponder
        return application?.processIdentifier
    }
    func isCurrentDestination(_ pid: pid_t) -> Bool {
        application?.processIdentifier == pid && application?.isTerminated == false &&
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }
    func hasPermission(for pid: pid_t) -> Bool { pid == getpid() || AXIsProcessTrusted() }
    func requestPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    func postPaste(to pid: pid_t) -> Bool {
        guard isCurrentDestination(pid), sessionIsActive else { return false }
        if pid == getpid() {
            guard let window, window.isVisible, let responder else { return false }
            window.makeKeyAndOrderFront(nil)
            guard window.makeFirstResponder(responder) else { return false }
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: responder, from: nil)
        }
        guard AXIsProcessTrusted(), let events = ClipboardPasteService.pasteEvents() else { return false }
        events.0.postToPid(pid)
        events.1.postToPid(pid)
        return true
    }
}
