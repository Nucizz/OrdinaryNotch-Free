import AppKit
import Combine
import SwiftUI

@MainActor
final class MusicViewModel: ObservableObject {
    @Published private var state = MusicPlaybackState()
    @Published private(set) var accent = NSColor.white
    @Published private(set) var waveformColors: [NSColor] = [.white, .white]
    private(set) var backdrop: NSImage?
    var outputName: String { state.outputName ?? "Output unavailable" }
    var sourceIcon: NSImage? { state.hasTrack ? state.sourceIcon : nil }
    var sourceTitle: String { state.hasTrack ? state.source : "Now Playing" }
    var sourceIdentity: String { state.hasTrack ? (state.sourceIdentifier ?? state.source) : "" }
    var contentIdentity: MusicContentIdentity {
        MusicContentIdentity(source: sourceIdentity, title: state.title, artist: state.artist, hasTrack: state.hasTrack)
    }
    var accentColor: Color { Color(nsColor: accent) }
    private let service: any MusicServing
    let lyrics: LyricsViewModel
    private var lyricsSubscription: AnyCancellable?
    private var lyricsEnabledSubscription: AnyCancellable?
    private var lyricsClock: Timer?
    init(service: (any MusicServing)? = nil, lyrics: LyricsViewModel? = nil) {
        let service = service ?? MusicService()
        self.service = service
        self.lyrics = lyrics ?? LyricsViewModel()
        lyricsSubscription = self.lyrics.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        lyricsEnabledSubscription = self.lyrics.$enabled.removeDuplicates().sink { [weak self] enabled in
            self?.configureLyricsClock(enabled: enabled)
        }
        service.onChange = { [weak self] next in self?.apply(next) }
    }
    private func apply(_ next: MusicPlaybackState) {
        guard next != state else { return }
        if next.artwork !== state.artwork {
            backdrop = AlbumBackdrop.make(from: next.artwork)
            let palette = AlbumAccent.palette(from: next.artwork)
            accent = palette[0]
            waveformColors = palette
        }
        state = next
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
    var error: String? { get { state.error } set { var next = state; next.error = newValue; apply(next) } }
    var source: String { get { state.source } set { var next = state; next.source = newValue; apply(next) } }
    func refresh() { service.refresh() }
    func updatePosition() { service.updatePosition() }
    func command(_ command: String) { service.command(command) }
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
