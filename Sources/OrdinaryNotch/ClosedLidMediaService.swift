import Foundation

/// Uses hardware lid notifications, independently of Face Unlock and Keep Awake.
/// Pause is idempotent: closing an already-paused player must never start it.
@MainActor
final class ClosedLidMediaService {
    private let lid: any LidStateObserving
    private let pause: () -> Void
    private let audio: any ClosedLidAudioSilencing
    private var monitoring = false
    private var closed = false
    private var playingSource: String?

    init(lid: any LidStateObserving = LidStateService(), audio: (any ClosedLidAudioSilencing)? = nil,
         onError: @escaping (String?) -> Void = { _ in }, pause: @escaping () -> Void) {
        self.lid = lid; self.pause = pause
        self.audio = audio ?? ClosedLidAudioService()
        self.audio.onError = onError
    }
    func start() {
        guard !monitoring else { return }
        monitoring = true
        lid.start { [weak self] closed in
            MainActor.assumeIsolated { self?.lidChanged(closed) }
        }
        if let closed = lid.currentState { lidChanged(closed) }
    }
    private func lidChanged(_ closed: Bool) {
        guard monitoring, self.closed != closed else { return }
        self.closed = closed
        if closed { audio.silence(); pause() }
        else { audio.restore() }
        // Opening the lid never resumes playback.
    }
    func observePlayback(playing: Bool, source: String?) {
        let next = playing ? (source ?? "Now Playing") : nil
        let changed = playingSource != next
        playingSource = next
        // Catch playback starting again or switching players while the lid is shut.
        // Position/artwork updates and duplicate notifications do not send commands.
        if monitoring && closed && changed && playing { pause() }
    }
    func stop() {
        monitoring = false; lid.stop()
        if closed { audio.restore() }
        closed = false; playingSource = nil
    }
}
