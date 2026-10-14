import Foundation

enum DefaultMediaPlayer: String, CaseIterable, Codable {
    case none, appleMusic, spotify, soundcloud, youtubeMusic, tidal, deezer, other

    var title: String {
        switch self {
        case .none: "None"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .soundcloud: "SoundCloud"
        case .youtubeMusic: "YouTube Music"
        case .tidal: "TIDAL"
        case .deezer: "Deezer"
        case .other: "Other app…"
        }
    }
    var website: URL? {
        let address: String
        switch self {
        case .appleMusic: address = "https://music.apple.com/"
        case .spotify: address = "https://open.spotify.com/"
        case .soundcloud: address = "https://soundcloud.com/"
        case .youtubeMusic: address = "https://music.youtube.com/"
        case .tidal: address = "https://listen.tidal.com/"
        case .deezer: address = "https://www.deezer.com/"
        case .none, .other: return nil
        }
        return URL(string: address)
    }
    var scriptableBundleIdentifier: String? {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        default: nil
        }
    }
    var applicationNames: [String] {
        switch self {
        case .appleMusic: ["Music"]
        case .youtubeMusic: ["YouTube Music"]
        case .none, .other: []
        default: [title]
        }
    }
    func acceptsWebURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), let expected = website?.host else { return false }
        func withoutWWW(_ host: String) -> String { host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
        return withoutWWW(host) == withoutWWW(expected)
    }
}

struct DefaultMediaSelection: Equatable {
    var player: DefaultMediaPlayer = .none
    var applicationPath: String?
    var title: String {
        guard player == .other, let applicationPath else { return player.title }
        return URL(fileURLWithPath: applicationPath).deletingPathExtension().lastPathComponent
    }
    var isConfigured: Bool { player != .none && (player != .other || applicationPath?.isEmpty == false) }
}
