import AppKit

@MainActor
final class HapticFeedbackService {
    enum Event { case interaction, placement, expansion }
    var enabled: () -> Bool = { true }
    private let perform: (NSHapticFeedbackManager.FeedbackPattern) -> Void
    private let now: () -> TimeInterval
    private var lastFeedback: TimeInterval?

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         perform: @escaping (NSHapticFeedbackManager.FeedbackPattern) -> Void = {
             NSHapticFeedbackManager.defaultPerformer.perform($0, performanceTime: .now)
         }) {
        self.now = now
        self.perform = perform
    }

    func play(_ event: Event = .interaction) {
        guard enabled() else { return }
        let time = now()
        guard lastFeedback.map({ time - $0 >= 0.08 }) ?? true else { return }
        lastFeedback = time
        // AppKit owns the duration of these fixed patterns. One event produces one pulse.
        perform(event == .placement ? .alignment : .generic)
    }
}
