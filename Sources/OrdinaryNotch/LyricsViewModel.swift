import Combine
import Foundation

@MainActor
final class LyricsViewModel: ObservableObject {
    enum Status: Equatable { case idle, loading, ready, unavailable, instrumental, failed }
    @Published private(set) var enabled = false
    @Published private(set) var status = Status.idle
    @Published private(set) var currentLine: LyricLine?
    @Published private(set) var source: LyricsSource?
    @Published private(set) var hiddenForCurrentTrack = false
    private let service: any LyricsServing
    private var track: LyricsTrack?
    private var position: Double = 0
    private var timingOffset: Double = 0
    private var lines: [LyricLine] = []
    private var request: Task<Void, Never>?
    private var unavailableDismissal: Task<Void, Never>?
    private var generation = UUID()

    init(service: any LyricsServing = MusixmatchLyricsService()) { self.service = service }
    var text: String {
        switch status {
        case .idle: return "Play a song to see lyrics"
        case .loading: return "Finding synced lyrics…"
        case .unavailable: return "Synced lyrics unavailable for this song"
        case .instrumental: return "Instrumental"
        case .failed: return "Couldn’t load lyrics for this song"
        case .ready: return currentLine?.text.isEmpty == false ? currentLine!.text : "♪"
        }
    }
    func toggle() {
        hiddenForCurrentTrack = false
        enabled.toggle()
        if enabled { load() }
        else { cancel(); lines = []; currentLine = nil; source = nil; status = .idle }
    }
    func update(track next: LyricsTrack?, position: Double) {
        self.position = position
        if track != next {
            track = next
            hiddenForCurrentTrack = false
            cancel(); lines = []; currentLine = nil; source = nil; status = .idle
            if enabled { load() }
        }
        selectCurrentLine()
    }
    /// Positive values show lines earlier without changing the playback clock.
    func setTimingOffset(_ seconds: Double) {
        timingOffset = seconds.isFinite ? min(5, max(-5, seconds)) : 0
        selectCurrentLine()
    }
    private func selectCurrentLine() {
        let line = TimedLyrics.current(in: lines, at: position + timingOffset)
        if currentLine != line { currentLine = line }
    }
    func stop() { cancel() }
    private func cancel() {
        generation = UUID(); request?.cancel(); request = nil
        unavailableDismissal?.cancel(); unavailableDismissal = nil
    }
    private func dismissUnavailableAfterDelay() {
        unavailableDismissal?.cancel()
        let token = generation
        unavailableDismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.enabled, self.generation == token else { return }
            self.hiddenForCurrentTrack = true
        }
    }
    private func load() {
        guard enabled, let track else {
            status = .unavailable
            if enabled { dismissUnavailableAfterDelay() }
            return
        }
        cancel()
        let token = generation, service = service
        status = .loading
        request = Task { [weak self] in
            do {
                let result = try await service.fetch(track)
                guard let self, !Task.isCancelled, self.enabled, self.generation == token else { return }
                switch result {
                case .synced(let lines, let source):
                    self.source = source
                    self.lines = lines; self.status = .ready
                    self.selectCurrentLine()
                case .unavailable: self.status = .unavailable; self.dismissUnavailableAfterDelay()
                case .instrumental: self.status = .instrumental; self.dismissUnavailableAfterDelay()
                }
            } catch {
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.status = .failed
                self.dismissUnavailableAfterDelay()
            }
        }
    }
}
