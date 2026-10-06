import AppKit
import AVFoundation
import EventKit
import Foundation

struct MusicPlaybackState: Equatable {
    var title: String = "Nothing playing"
    var artist: String = "Play audio in your favorite app"
    var album: String = ""
    var isPlaying: Bool = false
    var position: Double = 0
    var duration: Double = 0
    var artwork: NSImage? = nil
    var hasTrack: Bool = false
    var error: String? = nil
    var source: String = "Now Playing"
    var sourceIdentifier: String? = nil
    var sourceIcon: NSImage? = nil
    var outputName: String? = nil
}

@MainActor
protocol MusicServing: AnyObject {
    var onChange: ((MusicPlaybackState) -> Void)? { get set }
    func refresh()
    func updatePosition()
    func command(_ command: String)
    func stop()
}

@MainActor
final class MusicService: MusicServing {
    private(set) var state = MusicPlaybackState() {
        didSet {
            guard state != oldValue, !notificationPending else { return }
            notificationPending = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                notificationPending = false
                onChange?(state)
            }
        }
    }
    var onChange: ((MusicPlaybackState) -> Void)?
    private var notificationPending = false
    private var title: String { get { state.title } set { state.title = newValue } }
    private var artist: String { get { state.artist } set { state.artist = newValue } }
    private var isPlaying: Bool { get { state.isPlaying } set { state.isPlaying = newValue } }
    private var position: Double { get { state.position } set { state.position = newValue } }
    private var duration: Double { get { state.duration } set { state.duration = newValue } }
    private var artwork: NSImage? { get { state.artwork } set { state.artwork = newValue } }
    private var hasTrack: Bool { get { state.hasTrack } set { state.hasTrack = newValue } }
    private var error: String? { get { state.error } set { state.error = newValue } }
    private var source: String { get { state.source } set { state.source = newValue } }
    private let nowPlaying = NowPlayingClient()
    private var timeline = NowPlayingTimeline()
    private var systemArtwork: String?
    private var usesSystemPlayer = false
    private var busy = false
    private var artURL: String?
    private var sourceID: String?
    private let queue = DispatchQueue(label: "ordinary.music")

    func refresh() {
        state.outputName = AudioOutput.currentName()
        usesSystemPlayer = nowPlaying.start { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let snapshot): self.apply(snapshot)
            case .failure:
                self.apply(nil)
                self.error = "Now Playing is temporarily unavailable. Retrying automatically."
            }
        }
        if usesSystemPlayer { updatePosition(); return }
        guard !busy else { return }
        let apps = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        guard apps.contains("com.spotify.client") || apps.contains("com.apple.Music") else {
            timeline.update(nil, at: Date())
            hasTrack = false; state.album = ""; title = "Nothing playing"; artist = "Open Music or Spotify"; isPlaying = false; artwork = nil; artURL = nil; position = 0; duration = 0; return
        }
        busy = true
        let candidates = ["com.spotify.client", "com.apple.Music"].filter { apps.contains($0) }
        queue.async { [weak self] in
            var chosen: [String]?
            var chosenID = ""
            var failure: String?
            for id in candidates {
                let spotify = id == "com.spotify.client"
                let script = """
                tell application id "\(id)"
                    if player state is stopped then return ""
                    set t to current track
                    set art to ""
                    \(spotify ? "set art to artwork url of t" : "")
                    return (name of t) & (ASCII character 31) & (artist of t) & (ASCII character 31) & (player state as text) & (ASCII character 31) & (player position as text) & (ASCII character 31) & (duration of t as text) & (ASCII character 31) & art & (ASCII character 31) & (album of t)
                end tell
                """
                var err: NSDictionary?
                let result = NSAppleScript(source: script)?.executeAndReturnError(&err).stringValue
                if err != nil { failure = "Allow Ordinary Notch in System Settings → Privacy & Security → Automation." }
                if let result, !result.isEmpty {
                    let values = result.components(separatedBy: "\u{1f}")
                    if values.count >= 6 { chosen = values; chosenID = id; if values[2] == "playing" { break } }
                }
            }
            let values = chosen, identifier = chosenID, message = failure
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.busy = false; self.error = message
                guard let values else { self.timeline.update(nil, at: Date()); self.isPlaying = false; self.hasTrack = false; self.state.album = ""; self.title = "Nothing playing"; self.artist = "Choose a track in Music or Spotify"; self.artwork = nil; self.artURL = nil; self.position = 0; self.duration = 0; return }
                self.hasTrack = true
                self.updateSource(identifier)
                self.title = values[0]; self.artist = values[1]; self.state.album = values.count > 6 ? values[6] : ""; self.isPlaying = values[2] == "playing"
                self.position = Double(values[3]) ?? 0
                self.duration = (Double(values[4]) ?? 0) / (identifier == "com.spotify.client" ? 1000 : 1)
                let sampledAt = Date()
                self.timeline.update(NowPlayingSnapshot(bundleIdentifier: identifier, parentApplicationBundleIdentifier: nil,
                    title: self.title, artist: self.artist, playing: self.isPlaying,
                    durationMicros: self.duration * 1_000_000, elapsedTimeMicros: self.position * 1_000_000,
                    timestampEpochMicros: sampledAt.timeIntervalSince1970 * 1_000_000,
                    playbackRate: 1, artworkData: nil), at: sampledAt)
                if identifier == "com.apple.Music" { self.loadMusicArtwork(key: "music:" + values[0] + ":" + values[1]) }
                else { self.loadArtwork(values[5]) }
            }
        }
    }
    private func apply(_ snapshot: NowPlayingSnapshot?) {
        timeline.update(snapshot, at: Date()); error = nil
        guard let snapshot else {
            hasTrack = false; isPlaying = false; state.album = ""
            title = "Nothing playing"; artist = "Play audio in your favorite app"
            position = 0; duration = 0; artwork = nil; systemArtwork = nil; sourceID = nil; state.sourceIdentifier = nil; source = "Now Playing"; state.sourceIcon = nil
            return
        }
        hasTrack = true; isPlaying = snapshot.playing
        title = snapshot.title; artist = snapshot.artist ?? ""; state.album = snapshot.album ?? ""
        let id = snapshot.parentApplicationBundleIdentifier ?? snapshot.bundleIdentifier
        updateSource(id)
        duration = snapshot.duration
        if systemArtwork != snapshot.artworkData {
            systemArtwork = snapshot.artworkData
            artwork = snapshot.artworkData.flatMap { Data(base64Encoded: $0) }.flatMap(NSImage.init(data:))
        }
        updatePosition()
    }
    private func updateSource(_ identifier: String) {
        guard sourceID != identifier else { return }
        sourceID = identifier
        state.sourceIdentifier = identifier
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        switch identifier {
        case "com.apple.Music": source = "Apple Music"
        case "com.spotify.client": source = "Spotify"
        case "com.google.Chrome": source = "Chrome"
        default: source = appURL?.deletingPathExtension().lastPathComponent ?? "Now Playing"
        }
        // Read the installed app's actual icon only when the player changes.
        state.sourceIcon = appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
    func updatePosition() {
        if let snapshot = timeline.snapshot {
            let current = snapshot.position(at: Date())
            if position != current { position = current }
        }
    }
    func stop() { nowPlaying.stop() }

    private func loadMusicArtwork(key: String) {
        guard artURL != key else { return }
        artURL = key; artwork = nil
        queue.async { [weak self] in
            var error: NSDictionary?
            let data = NSAppleScript(source: "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track")?
                .executeAndReturnError(&error).data
            Task { @MainActor [weak self] in
                guard let self, self.artURL == key else { return }
                self.artwork = data.flatMap(NSImage.init(data:))
            }
        }
    }
    private func loadArtwork(_ value: String) {
        guard artURL != value else { return }; artURL = value; artwork = nil
        guard let url = URL(string: value), url.scheme == "https" else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), artURL == value else { return }
            artwork = NSImage(data: data)
        }
    }
    func command(_ command: String) {
        guard ["playpause", "next track", "previous track"].contains(command), hasTrack else { return }
        if usesSystemPlayer {
            nowPlaying.send(command) { [weak self] success in
                self?.error = success ? nil : "The current player could not accept that command."
            }
            return
        }
        let id = source == "Spotify" ? "com.spotify.client" : "com.apple.Music"
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == id }) else { return }
        queue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: "tell application id \"\(id)\" to \(command)")?.executeAndReturnError(&error)
            Task { @MainActor in self?.refresh() }
        }
    }
}
