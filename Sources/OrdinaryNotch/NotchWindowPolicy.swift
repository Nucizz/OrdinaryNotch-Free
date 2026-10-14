import AppKit

@MainActor enum NotchWindowPolicy {
    // A high overlay level; Space participation is controlled separately below.
    static let overlayLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    static let borderLevel = NSWindow.Level(rawValue: overlayLevel.rawValue + 1)
    static let clipboardLevel = NSWindow.Level(rawValue: borderLevel.rawValue + 1)

    static func configure(_ window: NSWindow, diagnostic: Bool = false) {
        window.level = diagnostic ? borderLevel : overlayLevel
        window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.animationBehavior = .none
    }
}
