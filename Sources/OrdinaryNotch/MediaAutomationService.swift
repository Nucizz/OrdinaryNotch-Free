import AppKit
import Carbon

struct MediaAutomationPermission: Equatable, Identifiable, Sendable {
    enum Status: String, Sendable {
        case allowed = "Allowed", denied = "Not allowed", notDetermined = "Not requested"
        case notRunning = "Open app to check", notInstalled = "Not installed", unavailable = "Could not check"
    }
    let id: String
    let name: String
    let status: Status
}

@MainActor
protocol MediaAutomationServing {
    func permissions() async -> [MediaAutomationPermission]
}

/// Reads Apple Events authorization without sending events, prompting, or launching a player.
@MainActor
struct MediaAutomationService: MediaAutomationServing {
    func permissions() async -> [MediaAutomationPermission] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let targets = [("com.apple.Music", "Music"), ("com.spotify.client", "Spotify")].map { id, name in
            (id, name, NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil, running.contains(id))
        }
        return await Task.detached(priority: .utility) {
            targets.map { id, name, installed, running in
                let status: MediaAutomationPermission.Status
                if !installed { status = .notInstalled }
                else if !running { status = .notRunning }
                else {
                    let target = NSAppleEventDescriptor(bundleIdentifier: id)
                    status = Self.status(for: AEDeterminePermissionToAutomateTarget(target.aeDesc,
                        AEEventClass(typeWildCard), AEEventID(typeWildCard), false))
                }
                return MediaAutomationPermission(id: id, name: name, status: status)
            }
        }.value
    }
    nonisolated static func status(for result: OSStatus) -> MediaAutomationPermission.Status {
        switch result {
        case noErr: .allowed
        case OSStatus(errAEEventNotPermitted): .denied
        case OSStatus(errAEEventWouldRequireUserConsent): .notDetermined
        case OSStatus(procNotFound): .notRunning
        default: .unavailable
        }
    }
}
