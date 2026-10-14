import Foundation

enum FullScreenVisibility: String, Codable, CaseIterable {
    case always, hideApps, hideMedia

    var title: String {
        switch self {
        case .always: "Always Show"
        case .hideApps: "Hide in Full-Screen Apps"
        case .hideMedia: "Hide During Full-Screen Media"
        }
    }

    var icon: String {
        switch self {
        case .always: "eye"
        case .hideApps: "arrow.up.left.and.arrow.down.right"
        case .hideMedia: "play.rectangle"
        }
    }

    var next: Self {
        switch self {
        case .always: .hideApps
        case .hideApps: .hideMedia
        case .hideMedia: .always
        }
    }

    func hidesNotch(appFullScreen: Bool, mediaFullScreen: Bool) -> Bool {
        switch self {
        case .always: false
        case .hideApps: appFullScreen || mediaFullScreen
        case .hideMedia: mediaFullScreen
        }
    }
}

enum FullScreenMediaPolicy {
    static let players: Set<String> = [
        "com.apple.QuickTimePlayerX", "com.apple.TV", "org.videolan.vlc", "com.colliderli.iina", "io.mpv"
    ]

    static func isVideoElement(subrole: String?, roleDescription: String?) -> Bool {
        // WebKit supplies a stable subrole. Chromium can expose only a localized
        // description; recognize its English video role without guessing by title.
        subrole == "AXVideo" || roleDescription?.lowercased() == "video"
    }

    static func coversDisplay(_ frame: CGRect, display: CGRect, topInset: CGFloat = 0) -> Bool {
        guard !frame.isEmpty, !display.isEmpty else { return false }
        let tolerance: CGFloat = 4
        return abs(frame.minX - display.minX) <= tolerance &&
            abs(frame.maxX - display.maxX) <= tolerance &&
            abs(frame.maxY - display.maxY) <= tolerance &&
            frame.minY >= display.minY - tolerance &&
            frame.minY <= display.minY + topInset + tolerance
    }

    static func isFullScreenMedia(bundleID: String, windowFullScreen: Bool, videoFrames: [CGRect],
                                  display: CGRect, topInset: CGFloat) -> Bool {
        guard windowFullScreen else { return false }
        return players.contains(bundleID) || videoFrames.contains {
            coversDisplay($0, display: display, topInset: topInset)
        }
    }
}
