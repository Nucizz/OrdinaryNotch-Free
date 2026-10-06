import AppKit

/// Hover never activates the app. If a click takes keyboard focus, return it on collapse.
@MainActor
final class FocusCoordinator: NSObject {
    private(set) var previousApp: NSRunningApplication?
    var settingsAreOpen: () -> Bool = { false }
    var otherPanelIsPresented: () -> Bool = { false }
    var ignoreClockActivation: () -> Bool = { false }
    func start() {
        remember(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    @objc private func activated(_ notification: Notification) {
        remember(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
    }
    func remember(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular, !app.isTerminated else { return }
        if app.bundleIdentifier == "com.apple.clock", ignoreClockActivation() { return }
        previousApp = app
    }
    func restore(from panel: NSPanel) {
        guard !settingsAreOpen(), !otherPanelIsPresented() else { return }
        let hadFocus = panel.isKeyWindow || NSApp.isActive
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let own = ProcessInfo.processInfo.processIdentifier
        if panel.isKeyWindow { panel.resignKey() }
        guard let previousApp, !previousApp.isTerminated,
              FocusReturnPolicy.shouldRestore(hadFocus: hadFocus, front: front, own: own, previous: previousApp.processIdentifier, settingsOpen: settingsAreOpen()) else { return }
        if NSApp.isActive { NSApp.deactivate() }
        previousApp.activate(options: [])
    }
}

enum FocusReturnPolicy {
    static func shouldRestore(hadFocus: Bool, front: pid_t?, own: pid_t, previous: pid_t, settingsOpen: Bool = false) -> Bool {
        // A deliberate switch to a third app takes precedence over restoring the older app.
        !settingsOpen && hadFocus && (front == nil || front == own || front == previous)
    }
}
