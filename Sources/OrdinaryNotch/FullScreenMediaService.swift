import AppKit
import ApplicationServices

/// AX queries can stall in another process; keep them off the hover/UI thread.
@MainActor
final class FullScreenMediaService {
    private var mediaFullScreen = false
    private var lastRequest = Date.distantPast
    private var task: Task<Void, Never>?
    private var context: Context?

    private struct Context: Equatable, Sendable {
        var display: CGRect
        var topInset: CGFloat
        var systemFullScreen: Bool
        var frontmostPID: pid_t?
    }

    func read(screen: NSScreen?, systemFullScreen: Bool, enabled: Bool) -> Bool {
        guard enabled, let screen, let primary = NSScreen.screens.first else {
            context = nil
            mediaFullScreen = false
            return false
        }
        // CGWindow and Accessibility use a top-left origin on the primary display.
        let next = Context(display: CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
                                          width: screen.frame.width, height: screen.frame.height),
                           topInset: screen.safeAreaInsets.top, systemFullScreen: systemFullScreen,
                           frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        if context != next {
            context = next
            mediaFullScreen = false
            lastRequest = .distantPast
        }
        guard task == nil, Date().timeIntervalSince(lastRequest) >= 0.75 else { return mediaFullScreen }
        lastRequest = Date()
        task = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { Self.detect(next) }.value
            guard let self else { return }
            if self.context == next { self.mediaFullScreen = result }
            self.task = nil
        }
        return mediaFullScreen
    }

    nonisolated private static func detect(_ context: Context) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Inspect the foremost ordinary window on the notch's display, even when
        // keyboard focus is on another display. Window titles are never needed.
        guard let window = windows.first(where: { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let frame = windowFrame(info) else { return false }
            let intersection = frame.intersection(context.display)
            return !intersection.isNull && intersection.width > 100 && intersection.height > 100
        }), let pid = window[kCGWindowOwnerPID as String] as? pid_t,
           let frame = windowFrame(window),
           FullScreenMediaPolicy.coversDisplay(frame, display: context.display, topInset: context.topInset),
           let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }

        let fullScreen = (context.systemFullScreen && context.frontmostPID == pid) ||
            FullScreenMediaPolicy.coversDisplay(frame, display: context.display)
        let nativePlayer = FullScreenMediaPolicy.players.contains(bundleID)
        if FullScreenMediaPolicy.isFullScreenMedia(bundleID: bundleID, windowFullScreen: fullScreen,
            videoFrames: [], display: context.display, topInset: context.topInset) { return true }
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let axWindows = attribute(app, kAXWindowsAttribute) as? [AXUIElement],
              let axWindow = axWindows.first(where: { element in
                  guard let bounds = elementFrame(element) else { return false }
                  return abs(bounds.minX - frame.minX) < 4 && abs(bounds.minY - frame.minY) < 4 &&
                      abs(bounds.width - frame.width) < 4 && abs(bounds.height - frame.height) < 4
              }), fullScreen || (attribute(axWindow, "AXFullScreen") as? Bool == true) else { return false }
        if nativePlayer { return true }

        let deadline = Date().addingTimeInterval(0.35)
        // Start at the display center so large pages do not bury the video below
        // hundreds of unrelated nodes. Walk up from an overlay/control if needed.
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(app, Float(context.display.midX), Float(context.display.midY), &hit) == .success {
            var current = hit
            for _ in 0..<20 {
                guard let element = current, Date() < deadline else { break }
                if isFullScreenVideo(element, context: context) { return true }
                guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
                current = (parent as! AXUIElement)
            }
        }
        var pending = [(axWindow, 0)]
        var visited = 0
        while let (element, depth) = pending.popLast(), visited < 500, Date() < deadline {
            visited += 1
            if isFullScreenVideo(element, context: context) { return true }
            if depth < 25, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(500 - visited).reversed().map { ($0, depth + 1) })
            }
        }
        return false
    }

    nonisolated private static func isFullScreenVideo(_ element: AXUIElement, context: Context) -> Bool {
        guard FullScreenMediaPolicy.isVideoElement(subrole: attribute(element, kAXSubroleAttribute) as? String,
                                                  roleDescription: attribute(element, kAXRoleDescriptionAttribute) as? String),
              let frame = elementFrame(element) else { return false }
        return FullScreenMediaPolicy.isFullScreenMedia(bundleID: "", windowFullScreen: true,
            videoFrames: [frame], display: context.display, topInset: context.topInset)
    }

    nonisolated private static func windowFrame(_ info: [String: Any]) -> CGRect? {
        guard let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    nonisolated private static func elementFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
