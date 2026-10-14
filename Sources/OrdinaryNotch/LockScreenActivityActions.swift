import Foundation

enum LockScreenActivityAction {
    enum MediaCommand: String { case previous = "previous track", playpause, next = "next track" }
    case media(MediaCommand, MusicContentIdentity)
    case seek(Double, MusicContentIdentity)
    case open(String)
    case review(String)
    case cancelOpen
}

/// Playback and audio routing run while locked. App navigation is a short-lived
/// request, revalidated after the same console user has authenticated normally.
@MainActor final class LockScreenActivityActions {
    struct Context {
        var lock: SessionLockSnapshot
        var enabled: Bool
        var sessionAvailable: Bool
    }
    private struct Pending {
        let id: String
        let message: String
        let expires: TimeInterval
        let review: Bool
    }
    private var pending: Pending?
    var message: String? { pending?.message }
    private let context: () -> Context
    private let snapshot: () -> LockScreenActivitySnapshot
    private let media: (LockScreenActivityAction.MediaCommand) -> Void
    private let open: (String, Bool) -> Void
    private let output: (AudioOutput.Device) -> Bool
    private let seek: (Double, MusicContentIdentity) -> Void
    private let uptime: () -> TimeInterval

    init(context: @escaping () -> Context, snapshot: @escaping () -> LockScreenActivitySnapshot,
         media: @escaping (LockScreenActivityAction.MediaCommand) -> Void, open: @escaping (String, Bool) -> Void,
         output: @escaping (AudioOutput.Device) -> Bool = { _ in false },
         seek: @escaping (Double, MusicContentIdentity) -> Void = { _, _ in },
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.context = context; self.snapshot = snapshot; self.media = media; self.open = open; self.uptime = uptime
        self.output = output; self.seek = seek
    }

    func selectOutput(_ device: AudioOutput.Device, for identity: MusicContentIdentity) -> Bool {
        let state = context()
        guard state.enabled, state.sessionAvailable, state.lock.currentConsoleUser, state.lock.locked,
              identity.hasTrack, snapshot().rows.contains(where: { $0.media?.identity == identity }) else { return false }
        return output(device)
    }

    @discardableResult func perform(_ action: LockScreenActivityAction) -> String? {
        let state = context()
        guard state.enabled, state.sessionAvailable, state.lock.currentConsoleUser, state.lock.locked else {
            pending = nil; return nil
        }
        switch action {
        case let .media(command, identity):
            // A queued click must not control a replacement track or launch a
            // default player when the original track has disappeared.
            guard snapshot().rows.contains(where: { $0.media?.identity == identity && identity.hasTrack }) else { return message }
            media(command)
        case let .seek(seconds, identity):
            guard seconds.isFinite,
                  let current = snapshot().rows.compactMap(\.media).first(where: { $0.identity == identity }),
                  current.canSeek else { return message }
            seek(min(current.duration, max(0, seconds)), identity)
        case let .open(id), let .review(id):
            guard let row = snapshot().rows.first(where: { $0.id == id }),
                  [.codex, .timer, .stopwatch].contains(row.kind) else { return message }
            let review: Bool
            if case .review = action { review = true } else { review = false }
            guard canOpen(row, review: review) else { return message }
            let label = row.kind == .codex ? (review ? "review this request" : "open this task") : "open Clock"
            pending = Pending(id: id, message: "Unlock your Mac to \(label)", expires: uptime() + 60, review: review)
        case .cancelOpen:
            pending = nil
        }
        return message
    }

    func update() {
        guard let request = pending else { return }
        let state = context()
        guard state.enabled, state.sessionAvailable, state.lock.currentConsoleUser,
              uptime() < request.expires,
              snapshot().rows.contains(where: { $0.id == request.id && canOpen($0, review: request.review) }) else {
            pending = nil; return
        }
        guard !state.lock.locked else { return }
        pending = nil
        open(request.id, request.review)
    }
    private func canOpen(_ row: LockScreenActivityRow, review: Bool) -> Bool {
        if review { return row.code?.needsInput == true && row.code?.canReview == true }
        return row.kind == .codex ? row.code?.canOpen == true : [.timer, .stopwatch].contains(row.kind)
    }
}
