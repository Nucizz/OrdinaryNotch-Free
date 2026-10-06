import AppKit
import Combine

@MainActor
final class ClockViewModel: ObservableObject {
    @Published var timers: [AppleTimer] = []
    @Published var stopwatch = AppleStopwatch()
    @Published var timerError: String?
    @Published var stopwatchError: String?
    @Published var commandError: String?
    @Published var isControlling = false
    private let controller = ClockController()
    var focusReturnApplication: (() -> NSRunningApplication?)?
    func control(_ action: ClockController.Action) {
        guard !isControlling else { return }
        isControlling = true; commandError = nil
        Task {
            do {
                try await controller.perform(action, timerCount: timers.count, returnTo: focusReturnApplication?())
                try? await Task.sleep(nanoseconds: 200_000_000)
            } catch { commandError = error.localizedDescription }
            isControlling = false
            refresh()
        }
    }
    var primaryTimer: AppleTimer? { timers.first }
    private var busy = false
    private let service: any ClockReading
    init(service: (any ClockReading)? = nil) {
        let service = service ?? AppleClockService()
        self.service = service
    }
    func refresh() {
        guard !busy else { return }; busy = true
        Task {
            let snapshot = await service.read()
            if timers != snapshot.timers { timers = snapshot.timers }
            if stopwatch != snapshot.stopwatch { stopwatch = snapshot.stopwatch }
            if timerError != snapshot.timerError { timerError = snapshot.timerError }
            if stopwatchError != snapshot.stopwatchError { stopwatchError = snapshot.stopwatchError }
            busy = false
        }
    }
    func openClock(stopwatch: Bool = false) { service.open(stopwatch: stopwatch) }
}
