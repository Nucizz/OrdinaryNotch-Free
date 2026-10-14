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
    private var monitoring = false
    private var dirty = true
    private var lastRead: TimeInterval = -.infinity
    private var changeRefresh: Task<Void, Never>?
    private let uptime: () -> TimeInterval
    private let service: any ClockReading
    init(service: (any ClockReading)? = nil, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        let service = service ?? AppleClockService()
        self.service = service
        self.uptime = uptime
    }
    func refreshIfNeeded() {
        if !monitoring {
            monitoring = true
            service.monitorChanges { [weak self] in self?.dataChanged() }
        }
        let interval: TimeInterval = timers.isEmpty && stopwatch.started == nil ? 30 : 5
        guard uptime() - lastRead >= (dirty ? 0.15 : interval) else { return }
        refresh()
    }
    private func dataChanged() {
        guard monitoring else { return }
        dirty = true
        guard changeRefresh == nil else { return }
        changeRefresh = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, monitoring else { return }
            changeRefresh = nil; refreshIfNeeded()
        }
    }
    func stopMonitoring() {
        monitoring = false; service.stopMonitoring()
        changeRefresh?.cancel(); changeRefresh = nil; dirty = true
    }
    func refresh() {
        guard !busy else { return }; busy = true
        dirty = false; lastRead = uptime()
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
