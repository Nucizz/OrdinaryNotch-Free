import AppKit

struct ForegroundActivityContext: Equatable, Sendable {
    var bundleIdentifier: String?
    var bundlePath: String?
    var hasVisibleWindow = false
    var showActivitiesWhileViewingApp = false

    func suppressesMedia(source: String?) -> Bool {
        !showActivitiesWhileViewingApp && hasVisibleWindow && source != nil && source == bundleIdentifier
    }
    var suppressesClock: Bool { !showActivitiesWhileViewingApp && hasVisibleWindow && bundleIdentifier == "com.apple.clock" }
    func suppresses(_ task: CodeTask) -> Bool {
        guard !showActivitiesWhileViewingApp, hasVisibleWindow else { return false }
        if let source = task.sourceApplication {
            return source.standardizedFileURL.resolvingSymlinksInPath().path == bundlePath
        }
        guard task.account == .personal else { return false }
        return task.provider == .claude ? bundleIdentifier == "com.anthropic.claudefordesktop"
            : ["com.openai.codex", "com.openai.chat"].contains(bundleIdentifier ?? "")
    }
}

@MainActor final class ForegroundActivityService {
    private var application: NSRunningApplication?
    private var lastRead = Date.distantPast
    private var context = ForegroundActivityContext()

    func read(ignoreClockActivation: Bool, now: Date = Date()) -> ForegroundActivityContext {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           !(ignoreClockActivation && front.bundleIdentifier == "com.apple.clock"),
           front.processIdentifier != application?.processIdentifier {
            application = front
            lastRead = .distantPast
        }
        guard now.timeIntervalSince(lastRead) >= 0.25 else { return context }
        lastRead = now
        guard let application, !application.isHidden, !application.isTerminated else {
            context = ForegroundActivityContext(); return context
        }
        // Window metadata works without screen-recording or Accessibility permission.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let visible = windows.contains { Self.isVisibleWindow($0, pid: application.processIdentifier) }
        context = ForegroundActivityContext(bundleIdentifier: application.bundleIdentifier,
            bundlePath: application.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path,
            hasVisibleWindow: visible)
        return context
    }

    static func isVisibleWindow(_ window: [String: Any], pid: pid_t) -> Bool {
        guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
              window[kCGWindowLayer as String] as? Int == 0,
              (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
        return rect.width > 1 && rect.height > 1
    }
}
