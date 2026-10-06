import Foundation
import Combine

@MainActor
final class BatteryViewModel: ObservableObject {
    @Published private(set) var notice: BatteryNotice?
    var active: Bool { notice != nil }
    var visibilityChanged: (Bool) -> Void = { _ in }
    private let service: any BatteryReadingService
    init(service: any BatteryReadingService = BatteryService()) { self.service = service }
    private var policy = BatteryAlertPolicy()
    private var pending: [(notice: BatteryNotice, created: Date)] = []
    private var deadline: Date?
    private var nextRead = Date.distantPast
    private var suspended = false
    private var isPreview = false

    func tick(at now: Date, values: NotchSettings, canPresent: Bool) {
        guard !suspended else { return }
        if let deadline, now >= deadline { dismiss() }
        if now >= nextRead && !isPreview {
            nextRead = now.addingTimeInterval(2)
            if let reading = service.read() {
                if notice?.kind == .low && reading.connected { dismiss() }
                if let event = policy.observe(reading) { pending.append((event, now)) }
                // Discard queued notices whose underlying state changed before presentation.
                pending.removeAll { item in
                    (item.notice.kind == .low && reading.connected) || (item.notice.kind != .low && !reading.connected)
                }
            }
        }
        pending.removeAll { now.timeIntervalSince($0.created) >= 60 }
        guard let item = pending.first else { return }
        let event = item.notice
        let enabled: Bool
        switch event.kind { case .low: enabled = values.batteryLowAlerts; case .connected: enabled = values.batteryChargingAlerts; case .full: enabled = values.batteryFullAlerts }
        guard enabled else { pending.removeFirst(); return }
        if canPresent && !active { pending.removeFirst(); present(event, at: now) }
    }
    private func present(_ event: BatteryNotice, at now: Date) {
        let wasActive = active
        notice = event
        deadline = now.addingTimeInterval(6)
        if !wasActive { visibilityChanged(true) }
    }
    func preview(_ event: BatteryNotice = BatteryNotice(kind: .low, percent: 20)) {
        guard !suspended else { return }
        isPreview = true
        present(event, at: Date())
    }
    func dismiss() {
        guard active else { return }
        notice = nil; deadline = nil; isPreview = false
        visibilityChanged(false)
    }
    func suspend(_ value: Bool) {
        guard value != suspended else { return }
        suspended = value
        pending.removeAll(); dismiss()
        policy.rebaselineConnection()
        nextRead = .distantPast
    }
}
