import AppKit

enum CodeTaskNavigationError: LocalizedError {
    case missingConversation, missingProfile, closedApp, deliveryFailed, claudeUnavailable
    var errorDescription: String? {
        switch self {
        case .missingConversation: "A link to this task is unavailable."
        case .missingProfile: "This task’s account could not be found."
        case .closedApp: "Open this task’s ChatGPT account, then try again."
        case .deliveryFailed: "Could not open the task. Try again from its account’s app."
        case .claudeUnavailable: "Install Claude Desktop to open this Claude Code session."
        }
    }
}

@MainActor
protocol CodeTaskOpening {
    func open(_ task: CodeTask) throws
}

/// Deliver a conversation URL to the running app associated with its profile.
@MainActor
struct CodeTaskNavigationService: CodeTaskOpening {
    var profiles: () -> [CodeProfile] = {
        let catalog = CodeProfiles()
        return CodeAccount.allCases.map { catalog.profile($0) }
    }
    var runningApplications: () -> [URL: pid_t] = {
        Dictionary(NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated, let url = app.bundleURL else { return nil }
            return (url.standardizedFileURL.resolvingSymlinksInPath(), app.processIdentifier)
        }, uniquingKeysWith: { first, _ in first })
    }
    var deliver: (URL, pid_t) throws -> Void = { url, pid in
        let event = urlEvent(url, processID: pid)
        do {
            _ = try event.sendEvent(options: [.noReply, .neverInteract], timeout: 1)
        } catch { throw CodeTaskNavigationError.deliveryFailed }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }
    var openClaude: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    func open(_ task: CodeTask) throws {
        guard let url = task.conversationURL else { throw CodeTaskNavigationError.missingConversation }
        if task.provider == .claude {
            guard openClaude(url) else { throw CodeTaskNavigationError.claudeUnavailable }
            return
        }
        guard let profileID = task.profileID,
              let profile = profiles().first(where: { $0.id == profileID }),
              let runtime = profile.runtime else { throw CodeTaskNavigationError.missingProfile }
        guard let pid = runningApplications()[runtime.standardizedFileURL.resolvingSymlinksInPath()] else {
            throw CodeTaskNavigationError.closedApp
        }
        try deliver(url, pid)
    }

    static func urlEvent(_ url: URL, processID: pid_t) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass),
            eventID: AEEventID(kAEGetURL), targetDescriptor: NSAppleEventDescriptor(processIdentifier: processID),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: url.absoluteString), forKeyword: AEKeyword(keyDirectObject))
        return event
    }
}
