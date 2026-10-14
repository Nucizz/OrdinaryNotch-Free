import AppKit
import Combine
import SwiftUI

@MainActor
final class MusicViewModel: ObservableObject {
    @Published private var state = MusicPlaybackState()
    @Published private(set) var seekPreview: Double?
    private var seekIdentity: MusicContentIdentity?
    private var seekGestureActive = false
    @Published private(set) var accent = NSColor.white
    @Published private(set) var waveformColors: [NSColor] = [.white, .white]
    private(set) var backdrop: NSImage?
    var outputName: String? {
        guard let name = state.outputName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }
    var outputSymbol: String { state.outputSymbol }
    @Published var isOutputMenuOpen = false
    @Published var outputSelectionError: String?
    private let listAudioOutputs: () -> [AudioOutput.Device]
    private let selectAudioOutput: (AudioOutput.Device) -> Bool
    func outputMenuItems() -> [NotchButtonMenuItem] {
        let devices = listAudioOutputs()
        guard !devices.isEmpty else {
            return [NotchButtonMenuItem(title: "No audio outputs available", enabled: false, action: {})]
        }
        return devices.map { device in
            NotchButtonMenuItem(title: device.route.name, selected: device.selected, symbol: device.route.symbol) { [weak self] in
                self?.selectOutput(device)
            }
        }
    }
    func selectOutput(_ device: AudioOutput.Device) {
        guard selectAudioOutput(device) else {
            outputSelectionError = "\(device.route.name) is no longer available or could not be selected. Try choosing it again."
            service.refresh()
            return
        }
        outputSelectionError = nil
        state.outputName = device.route.name
        state.outputSymbol = device.route.symbol
        service.refresh()
    }
    var sourceIcon: NSImage? { state.hasTrack ? state.sourceIcon : nil }
    var sourceTitle: String { state.hasTrack ? state.source : "Now Playing" }
    var sourceIdentity: String { state.hasTrack ? (state.sourceIdentifier ?? state.source) : "" }
    var sourceIdentifier: String? { state.sourceIdentifier }
    var canOpenSource: Bool { hasTrack && state.sourceIdentifier?.isEmpty == false }
    func openSource() {
        guard canOpenSource, let identifier = state.sourceIdentifier else { return }
        openApplication(identifier)
    }
    var contentIdentity: MusicContentIdentity {
        MusicContentIdentity(source: sourceIdentity, title: state.title, artist: state.artist, hasTrack: state.hasTrack)
    }
    var accentColor: Color { Color(nsColor: accent) }
    var albumColors: [NSColor]? {
        guard state.hasTrack, state.artwork != nil else { return nil }
        return waveformColors
    }
    private let service: any MusicServing
    private let defaultLauncher: any DefaultMediaLaunching
    @Published var defaultPlayer = DefaultMediaSelection() {
        didSet { if oldValue != defaultPlayer { cancelDefaultPlayback(); defaultPlaybackMessage = nil } }
    }
    @Published private(set) var isStartingDefaultPlayer = false
    @Published private(set) var defaultPlaybackMessage: String?
    private var defaultPlaybackTask: Task<Void, Never>?
    private var defaultPlaybackGeneration = UUID()
    var canPlay: Bool { !isStartingDefaultPlayer && (hasTrack || defaultPlayer.isConfigured) }
    var playHint: String {
        if isStartingDefaultPlayer { return "Opening \(defaultPlayer.title)…" }
        if hasTrack { return isPlaying ? "Pause" : "Resume" }
        return defaultPlayer.isConfigured ? "Play in \(defaultPlayer.title)" : "Choose a default player in Settings → Media"
    }
    var idlePlaybackDetail: String {
        defaultPlaybackMessage ?? (defaultPlayer.isConfigured ? "Play in \(defaultPlayer.title)" : "Choose a default player in Settings → Media")
    }
    @Published private(set) var lidAudioError: String?
    private lazy var closedLidMedia = ClosedLidMediaService(onError: { [weak self] in self?.lidAudioError = $0 },
        pause: { [weak self] in self?.command("pause") })
    private let openApplication: (String) -> Void
    let lyrics: LyricsViewModel
    private var lyricsSubscription: AnyCancellable?
    private var lyricsEnabledSubscription: AnyCancellable?
    private var lyricsClock: Timer?
    init(service: (any MusicServing)? = nil, lyrics: LyricsViewModel? = nil,
         openApplication: ((String) -> Void)? = nil, defaultLauncher: (any DefaultMediaLaunching)? = nil,
         listAudioOutputs: @escaping () -> [AudioOutput.Device] = { AudioOutput.devices() },
         selectAudioOutput: @escaping (AudioOutput.Device) -> Bool = { AudioOutput.select($0) }) {
        let service = service ?? MusicService()
        self.service = service
        self.listAudioOutputs = listAudioOutputs
        self.selectAudioOutput = selectAudioOutput
        self.defaultLauncher = defaultLauncher ?? DefaultMediaLauncher()
        self.openApplication = openApplication ?? { ApplicationNavigationService.openMediaApplication($0) }
        self.lyrics = lyrics ?? LyricsViewModel()
        lyricsSubscription = self.lyrics.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        lyricsEnabledSubscription = self.lyrics.$enabled.removeDuplicates().sink { [weak self] enabled in
            self?.configureLyricsClock(enabled: enabled)
        }
        service.onChange = { [weak self] next in self?.apply(next) }
    }
    private func apply(_ next: MusicPlaybackState) {
        closedLidMedia.observePlayback(playing: next.isPlaying, source: next.sourceIdentifier)
        guard next != state else { return }
        if next.artwork !== state.artwork {
            backdrop = AlbumBackdrop.make(from: next.artwork)
            let palette = AlbumAccent.palette(from: next.artwork)
            accent = palette[0]
            waveformColors = palette
        }
        state = next
        if seekGestureActive, seekIdentity != contentIdentity || !canSeek {
            seekIdentity = nil
            seekPreview = nil
        }
        lyrics.update(track: next.hasTrack ? LyricsTrack(title: next.title, artist: next.artist, duration: next.duration, album: next.album) : nil,
                      position: next.position)
        configureLyricsClock(enabled: lyrics.enabled)
    }
    var title: String { get { state.title } set { var next = state; next.title = newValue; apply(next) } }
    var artist: String { get { state.artist } set { var next = state; next.artist = newValue; apply(next) } }
    var album: String { get { state.album } set { var next = state; next.album = newValue; apply(next) } }
    var isPlaying: Bool { get { state.isPlaying } set { var next = state; next.isPlaying = newValue; apply(next) } }
    var position: Double { get { state.position } set { var next = state; next.position = newValue; apply(next) } }
    var duration: Double { get { state.duration } set { var next = state; next.duration = newValue; apply(next) } }
    var artwork: NSImage? { get { state.artwork } set { var next = state; next.artwork = newValue; apply(next) } }
    var hasTrack: Bool { get { state.hasTrack } set { var next = state; next.hasTrack = newValue; apply(next) } }
    var error: String? { get { lidAudioError ?? state.error } set { var next = state; next.error = newValue; apply(next) } }
    var source: String { get { state.source } set { var next = state; next.source = newValue; apply(next) } }
    func refresh() { service.refresh() }
    func startLidMonitoring() { closedLidMedia.start() }
    func updatePosition() { service.updatePosition() }
    func command(_ command: String) {
        if command == "pause" { cancelDefaultPlayback() }
        guard command == "playpause", !hasTrack else { service.command(command); return }
        guard canPlay else { return }
        defaultPlaybackMessage = nil
        isStartingDefaultPlayer = true
        let token = UUID(), selection = defaultPlayer
        defaultPlaybackGeneration = token
        defaultPlaybackTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if defaultPlaybackGeneration == token { isStartingDefaultPlayer = false; defaultPlaybackTask = nil }
            }
            do {
                let message = try await defaultLauncher.play(selection) { [weak self] in
                    guard let self else { return false }
                    return self.defaultPlaybackGeneration == token && !self.isPlaying
                }
                try Task.checkCancellation()
                guard defaultPlaybackGeneration == token else { return }
                defaultPlaybackMessage = message
                service.refresh()
            } catch is CancellationError {
                return
            } catch {
                guard defaultPlaybackGeneration == token else { return }
                defaultPlaybackMessage = "Couldn’t open \(selection.title). Check that it is installed and try again."
            }
        }
    }
    private func cancelDefaultPlayback() {
        defaultPlaybackGeneration = UUID()
        defaultPlaybackTask?.cancel(); defaultPlaybackTask = nil
        isStartingDefaultPlayer = false
    }
    var canSeek: Bool { hasTrack && duration.isFinite && duration > 0 }
    var isSeeking: Bool { seekGestureActive }
    var seekDuration: Double { canSeek ? duration : 1 }
    var displayedPosition: Double {
        let value = seekPreview ?? position
        return value.isFinite ? min(seekDuration, max(0, value)) : 0
    }
    func beginSeeking() {
        guard canSeek, !seekGestureActive else { return }
        seekGestureActive = true
        seekIdentity = contentIdentity
        seekPreview = displayedPosition
    }
    func previewSeek(to seconds: Double) {
        guard seconds.isFinite, canSeek else { return }
        if !seekGestureActive { beginSeeking() }
        guard seekIdentity == contentIdentity else { return }
        seekPreview = min(duration, max(0, seconds))
    }
    func finishSeeking() {
        defer { cancelSeeking() }
        guard canSeek, seekIdentity == contentIdentity, let seekPreview else { return }
        let target = min(duration, max(0, seekPreview))
        position = target
        service.seek(to: target)
    }
    func cancelSeeking() {
        seekGestureActive = false
        seekIdentity = nil
        seekPreview = nil
    }
    private func configureLyricsClock(enabled: Bool) {
        guard enabled && state.hasTrack && state.isPlaying else {
            lyricsClock?.invalidate(); lyricsClock = nil
            return
        }
        guard lyricsClock == nil else { return }
        // Interpolate the player's local timeline; this does not poll the player or network.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.lyricsClock != nil else { return }
                self.service.updatePosition()
            }
        }
        timer.tolerance = 0.01
        lyricsClock = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stop() {
        cancelDefaultPlayback()
        closedLidMedia.stop()
        cancelSeeking()
        lyricsClock?.invalidate(); lyricsClock = nil
        lyrics.stop(); service.stop()
    }
    deinit { lyricsClock?.invalidate() }
}

/// Timers, play/pause and waveform updates must not replace the media content.
struct MusicContentIdentity: Hashable {
    let source: String
    let title: String
    let artist: String
    let hasTrack: Bool
}
