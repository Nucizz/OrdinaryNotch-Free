import Foundation

struct BatteryReading: Equatable {
    let percent: Int
    let connected: Bool
    let charging: Bool
    let full: Bool


}

struct BatteryNotice: Equatable {
    enum Kind: Equatable { case low, connected, full }
    let kind: Kind
    let percent: Int
    var title: String {
        switch kind { case .low: "Battery running low"; case .connected: "Charger connected"; case .full: "Battery fully charged" }
    }
    var subtitle: String {
        switch kind { case .low: "Connect your Mac to power."; case .connected: "Your Mac is connected to power."; case .full: "Ready to go whenever you are." }
    }
    var symbol: String {
        switch kind { case .low: "battery.25"; case .connected: "bolt.batteryblock.fill"; case .full: "battery.100" }
    }
}

/// A discharge cycle reports each threshold once, even if readings fluctuate.
struct BatteryAlertPolicy {
    private var previous: BatteryReading?
    private var reported: Set<Int> = []
    private var reportedFull = false
    private let levels = [20, 15, 10, 5]
    mutating func observe(_ reading: BatteryReading) -> BatteryNotice? {
        defer { previous = reading }
        if reading.connected {
            // Rearm only levels that the battery has actually recharged beyond.
            reported = reported.filter { reading.percent < $0 + 2 }
            if reading.percent < 95 { reportedFull = false }
            if reading.full && !reportedFull {
                reportedFull = true
                return previous != nil ? BatteryNotice(kind: .full, percent: reading.percent) : nil
            }
            if previous?.connected == false { return BatteryNotice(kind: .connected, percent: reading.percent) }
            return nil
        }
        guard let crossed = levels.last(where: { reading.percent <= $0 && !reported.contains($0) }) else { return nil }
        reported.formUnion(levels.filter { $0 >= crossed })
        return BatteryNotice(kind: .low, percent: reading.percent)
    }
    // Ignore charger transitions while asleep; still evaluate a newly low battery on wake.
    mutating func rebaselineConnection() { previous = nil }
}
