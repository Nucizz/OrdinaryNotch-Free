import Combine
import FanCore
import Foundation

struct ThermalNotice: Equatable {
    let sensorID: String
    let sensorName: String
    let celsius: Double
}

struct ThermalAlertPolicy {
    static let sustainedDuration: TimeInterval = 10
    static let cooldown: TimeInterval = 180
    private var hotSince: [String: Date] = [:]
    private var lastSample: Date?
    private var nextAllowed = Date.distantPast
    func isOverheating(at now: Date) -> Bool { now < nextAllowed }
    mutating func resetObservation() { hotSince.removeAll(); lastSample = nil }
    mutating func observe(_ snapshot: FanSnapshot, at now: Date) -> ThermalNotice? {
        guard let date = snapshot.date, now.timeIntervalSince(date) >= 0,
              now.timeIntervalSince(date) <= 8, snapshot.error == nil else {
            resetObservation(); return nil
        }
        guard date != lastSample else { return nil }
        if let lastSample, date.timeIntervalSince(lastSample) > 8 { hotSince.removeAll() }
        lastSample = date
        let cpuAverage = snapshot.temperatures.first { $0.name == "CPU Average" }
        let hot = snapshot.temperatures.filter { reading in
            guard reading.isHot else { return false }
            // CPU overheat follows the displayed average, never an individual hottest sensor.
            return reading.zone != .cpu || reading.id == cpuAverage?.id
        }
        let ids = Set(hot.map(\.id))
        hotSince = hotSince.filter { ids.contains($0.key) }
        for sensor in hot where hotSince[sensor.id] == nil { hotSince[sensor.id] = date }
        guard now >= nextAllowed,
              let sensor = hot.filter({ date.timeIntervalSince(hotSince[$0.id]!) >= Self.sustainedDuration })
                .max(by: { $0.celsius < $1.celsius }) else { return nil }
        nextAllowed = now.addingTimeInterval(Self.cooldown)
        return ThermalNotice(sensorID: sensor.id, sensorName: sensor.name, celsius: sensor.celsius)
    }
}

@MainActor final class ThermalAlertsViewModel: ObservableObject {
    @Published private(set) var notice: ThermalNotice?
    @Published private(set) var overheatActive = false
    var active: Bool { notice != nil }
    var visibilityChanged: (Bool) -> Void = { _ in }
    private var policy = ThermalAlertPolicy()
    private var pending: ThermalNotice?
    private var deadline: Date?
    private var suspended = false
    private var isPreview = false
    func tick(snapshot: FanSnapshot, at now: Date, enabled: Bool, canPresent: Bool) {
        guard !suspended else { return }
        if let deadline, now >= deadline { dismiss() }
        let event = policy.observe(snapshot, at: now)
        let overheating = policy.isOverheating(at: now)
        if overheatActive != overheating { overheatActive = overheating }
        // Cooling mode is independent of notification preferences and previews.
        if isPreview { return }
        guard enabled else { pending = nil; dismiss(); return }
        if let event { pending = event }
        guard let event = pending else { return }
        guard let date = snapshot.date, now.timeIntervalSince(date) <= 8,
              let sensor = snapshot.temperatures.first(where: { $0.id == event.sensorID && $0.isHot }) else {
            pending = nil; return
        }
        if canPresent && !active {
            pending = nil
            present(ThermalNotice(sensorID: sensor.id, sensorName: sensor.name, celsius: sensor.celsius), at: now)
        }
    }
    private func present(_ event: ThermalNotice, at now: Date) {
        let wasActive = active
        notice = event; deadline = now.addingTimeInterval(8)
        if !wasActive { visibilityChanged(true) }
    }
    func dismiss() {
        guard active else { return }
        notice = nil; deadline = nil; isPreview = false; visibilityChanged(false)
    }
    func suspend(_ value: Bool) {
        guard value != suspended else { return }
        suspended = value; pending = nil; policy.resetObservation(); dismiss()
        if value { overheatActive = false }
    }
    func preview(_ event: ThermalNotice = ThermalNotice(sensorID: "cpu", sensorName: "CPU Average", celsius: 101)) {
        guard !suspended else { return }
        isPreview = true
        present(event, at: Date())
    }
}
