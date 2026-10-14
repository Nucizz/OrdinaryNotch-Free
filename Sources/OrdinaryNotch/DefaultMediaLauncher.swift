import AppKit
import ApplicationServices

@MainActor
protocol DefaultMediaLaunching {
    /// Nil means a Play command was sent; a message means the player needs attention.
    func play(_ selection: DefaultMediaSelection, shouldContinue: @escaping @MainActor () -> Bool) async throws -> String?
}

@MainActor
final class DefaultMediaLauncher: DefaultMediaLaunching {
    func play(_ selection: DefaultMediaSelection, shouldContinue: @escaping @MainActor () -> Bool) async throws -> String? {
        guard selection.isConfigured else { return "Choose a default player in Settings → Media." }
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let app: NSRunningApplication
        let websiteOnly: Bool
        if let url = Self.applicationURL(for: selection) {
            app = try await workspace.openApplication(at: url, configuration: configuration)
            websiteOnly = false
        } else if let website = selection.player.website,
                  let browser = workspace.urlForApplication(toOpen: website) {
            app = try await workspace.open([website], withApplicationAt: browser, configuration: configuration)
            websiteOnly = true
        } else {
            return "\(selection.title) is unavailable. Choose an installed app in Settings → Media."
        }
        try Task.checkCancellation()
        guard shouldContinue() else { return nil }
        if let identifier = selection.player.scriptableBundleIdentifier, app.bundleIdentifier == identifier {
            // Only our two fixed, scriptable identifiers enter AppleScript.
            let message = await Task.detached(priority: .userInitiated) { () -> String? in
                var error: NSDictionary?
                let script = NSAppleScript(source: "with timeout of 5 seconds\ntell application id \"\(identifier)\" to play\nend timeout")
                script?.executeAndReturnError(&error)
                guard script != nil, error == nil else {
                    return "Allow playback control in System Settings → Privacy & Security → Automation, or choose a track in \(selection.title)."
                }
                return nil
            }.value
            try Task.checkCancellation()
            return message
        }
        // Use the chosen player's own transport. A global media key could wake
        // an unrelated app, and a toggle could pause playback that already began.
        guard AXIsProcessTrusted() else {
            return "Choose a track in \(selection.title). Accessibility access enables its Play control."
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        for _ in 0..<12 {
            try Task.checkCancellation()
            guard shouldContinue() else { return nil }
            guard workspace.frontmostApplication?.processIdentifier == app.processIdentifier else {
                return "Continue playback in \(selection.title)."
            }
            if Self.pressTransport(in: root, player: selection.player, websiteOnly: websiteOnly) { return nil }
            try await Task.sleep(for: .milliseconds(250))
        }
        return "Choose a track or sign in to \(selection.title) to begin playback."
    }

    static func applicationURL(for selection: DefaultMediaSelection) -> URL? {
        if selection.player == .other {
            guard let path = selection.applicationPath else { return nil }
            let url = URL(fileURLWithPath: path)
            return url.pathExtension == "app" && Bundle(url: url)?.bundleIdentifier != nil ? url : nil
        }
        if let id = selection.player.scriptableBundleIdentifier,
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return app }
        // Includes Chrome/Edge PWAs and Safari web apps without scanning libraries
        // or maintaining a background catalogue of installed software.
        let roots = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for root in roots {
            guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in entries {
                if entries.level > 2 { entries.skipDescendants(); continue }
                guard url.pathExtension == "app",
                      selection.player.applicationNames.contains(url.deletingPathExtension().lastPathComponent),
                      let bundle = Bundle(url: url), bundle.bundleIdentifier != nil else { continue }
                if let address = bundle.object(forInfoDictionaryKey: "CrAppModeShortcutURL") as? String,
                   let webURL = URL(string: address), !selection.player.acceptsWebURL(webURL) { continue }
                return url
            }
        }
        return nil
    }

    /// Accept only unambiguous transport actions, never a random song's Play button.
    static func isPlayControl(label: String, siblingLabels: [String]) -> Bool {
        if label == "Play current" || label == "Play (k)" { return true }
        guard ["Play", "Resume", "Play playback", "Resume playback"].contains(label) else { return false }
        let siblings = Set(siblingLabels)
        return !siblings.isDisjoint(with: ["Next", "Next track", "Skip to next"])
            && !siblings.isDisjoint(with: ["Previous", "Previous track", "Skip to previous"])
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    private static func label(_ element: AXUIElement) -> String {
        [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute].compactMap {
            attribute(element, $0) as? String
        }.first(where: { !$0.isEmpty }) ?? ""
    }
    private static func pressTransport(in root: AXUIElement, player: DefaultMediaPlayer, websiteOnly: Bool) -> Bool {
        guard let value = attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let window = value as! AXUIElement
        var pending = [(window, 0, !websiteOnly)], count = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 0.12
        while let (node, depth, inPlayer) = pending.popLast(), count < 900, ProcessInfo.processInfo.systemUptime < deadline {
            count += 1
            var scoped = inPlayer
            if websiteOnly, let address = attribute(node, "AXURL") {
                let url = (address as? URL) ?? (address as? String).flatMap(URL.init(string:))
                if let url, player.acceptsWebURL(url) { scoped = true }
            }
            let nodes = children(node)
            let buttons = nodes.filter { (attribute($0, kAXRoleAttribute) as? String) == kAXButtonRole }
            let labels = buttons.map(label)
            let matches = buttons.filter { scoped && isPlayControl(label: label($0), siblingLabels: labels) }
            if matches.count == 1, let play = matches.first,
               (attribute(play, kAXEnabledAttribute) as? Bool) != false {
                return AXUIElementPerformAction(play, kAXPressAction as CFString) == .success
            }
            // Player bars usually follow the library/content tree. Visit the tail
            // first so a large music library cannot exhaust the bounded scan.
            if depth < 25 { pending.append(contentsOf: nodes.map { ($0, depth + 1, scoped) }) }
        }
        return false
    }
}
