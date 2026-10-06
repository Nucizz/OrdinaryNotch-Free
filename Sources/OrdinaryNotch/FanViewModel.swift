import Foundation
import Combine
import FanCore
@MainActor final class FanViewModel: ObservableObject {
    @Published private(set) var snapshot = FanSnapshot()
    private let telemetry = FanTelemetry()
    private let queue = DispatchQueue(label: "ordinary.free.telemetry", qos: .utility)
    private var reading = false
    var stale: Bool { snapshot.date.map { Date().timeIntervalSince($0) > 8 } ?? true }
    func refresh() {
        guard !reading else { return }; reading = true
        let telemetry = telemetry
        queue.async { [weak self] in
            let result = telemetry.snapshot()
            Task { @MainActor in self?.snapshot = result; self?.reading = false }
        }
    }
}
