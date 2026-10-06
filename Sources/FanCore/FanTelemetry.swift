import Foundation
import IOKit

public struct FanReading: Identifiable, Equatable, Codable {
    public let id: Int
    public let name: String
    public let rpm: Double
    public let minimum: Double
    public let maximum: Double
    public let manual: Bool
    public init(id: Int, name: String, rpm: Double, minimum: Double, maximum: Double, manual: Bool) { self.id = id; self.name = name; self.rpm = rpm; self.minimum = minimum; self.maximum = maximum; self.manual = manual }

}
public struct TemperatureReading: Identifiable, Equatable, Codable {
    public let id: String
    public let name: String
    public let celsius: Double
    public init(id: String, name: String, celsius: Double) { self.id = id; self.name = name; self.celsius = celsius }
    public var zone: TemperatureZone? {
        let label = name.lowercased()
        let key = id.lowercased()
        if label.contains("battery") || key.hasPrefix("tb") { return .battery }
        if label.contains("gpu") || key.hasPrefix("tg") { return .gpu }
        if label.contains("cpu") || key.hasPrefix("tc") || key.hasPrefix("tp") { return .cpu }
        return nil
    }
    // Display warning thresholds, not replacements for hardware thermal protection.
    public var isHot: Bool {
        guard let zone else { return false }
        return celsius >= (zone == .battery ? 45 : zone == .gpu ? 90 : 100)
    }
}
public enum TemperatureZone: String, CaseIterable, Codable {
    case cpu, gpu, battery
}
public struct FanSnapshot: Codable {
    public var fans: [FanReading] = []
    public var temperatures: [TemperatureReading] = []
    /// A successful FNum read; nil means hardware detection is unavailable.
    public var detectedFanCount: Int?
    public var hasNoFans: Bool { detectedFanCount == 0 }
    public var date: Date?
    public var error: String?
    public init(fans: [FanReading] = [], temperatures: [TemperatureReading] = [], date: Date? = nil, error: String? = nil, detectedFanCount: Int? = nil) { self.fans = fans; self.temperatures = temperatures; self.date = date; self.error = error; self.detectedFanCount = detectedFanCount }
    public func temperature(for zone: TemperatureZone) -> TemperatureReading? {
        let matches = temperatures.filter { $0.zone == zone && $0.celsius.isFinite }
        let preferredName = "\(zone.rawValue.uppercased()) Average"
        return matches.first(where: { $0.name.caseInsensitiveCompare(preferredName) == .orderedSame })
            ?? matches.max(by: { $0.celsius < $1.celsius })
    }
}

/// AppleSMC telemetry. Read-only temperature and RPM monitoring.
/// Protocol reference: https://github.com/exelban/stats/blob/master/SMC/smc.swift
public final class FanTelemetry: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    public init() {}
    private var connection: io_connect_t = 0
    private var lastCallFailure = ""
    private var temperatureKeys: [String]?
    private var metadata: [String: (UInt32, String)] = [:]
    public static var machine: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
    public var hasCalibratedSensors: Bool { Self.machine == "Mac15,3" }
    deinit { if connection != 0 { IOServiceClose(connection) } }

    private func open() -> Bool {
        if connection != 0 { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        return IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS
    }
    // Apple's user-client wire message is 80 bytes; integer fields are native endian.
    private func call(key: String = "\0\0\0\0", command: UInt8, size: UInt32 = 0, index: UInt32 = 0) -> [UInt8]? {
        guard connection != 0, key.utf8.count == 4 else { return nil }
        var input = [UInt8](repeating: 0, count: 80)
        func put(_ value: UInt32, at offset: Int) {
            withUnsafeBytes(of: value) { input.replaceSubrange(offset..<offset + 4, with: $0) }
        }
        put(key.utf8.reduce(0) { ($0 << 8) | UInt32($1) }, at: 0)
        put(size, at: 28)
        input[42] = command
        put(index, at: 44)
        var output = [UInt8](repeating: 0, count: 80)
        var count = 80
        let result = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                IOConnectCallStructMethod(connection, 2, source.baseAddress, 80, destination.baseAddress, &count)
            }
        }
        guard result == KERN_SUCCESS, count == 80, output[40] == 0 else {
            lastCallFailure = "IOKit 0x\(String(UInt32(bitPattern: result), radix: 16)), SMC 0x\(String(output[40], radix: 16)), response \(count) bytes"
            return nil
        }
        return output
    }
    private func integer(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }
    private func fourCC(_ value: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }, encoding: .ascii) ?? ""
    }
    private func info(_ key: String) -> (UInt32, String)? {
        if let cached = metadata[key] { return cached }
        guard let bytes = call(key: key, command: 9) else { return nil }
        let value = (integer(bytes, 28), fourCC(integer(bytes, 32)))
        guard value.0 > 0, value.0 <= 32 else { return nil }
        metadata[key] = value
        return value
    }
    private func read(_ key: String) -> Double? {
        // Multiple SMC clients can briefly contend; retry a failed read, never reuse stale telemetry.
        for attempt in 0..<3 {
            if let (size, type) = info(key), let bytes = call(key: key, command: 5, size: size),
               let value = Self.decode(type: type, bytes: Array(bytes[48..<48 + Int(size)])) { return value }
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.02) }
        }
        return nil
    }
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        let value: Double
        switch type {
        case "flt " where bytes.count >= 4:
            value = Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "fpe2" where bytes.count >= 2: value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78" where bytes.count >= 2: value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "ui8 " where bytes.count >= 1: value = Double(bytes[0])
        case "ui16" where bytes.count >= 2: value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count >= 4: value = Double(bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        default: return nil
        }
        return value.isFinite ? value : nil
    }
    public func snapshot() -> FanSnapshot {
        lock.lock(); defer { lock.unlock() }
        guard open() else { return FanSnapshot(error: "Temperature and fan readings are unavailable on this Mac.") }
        guard let count = read("FNum"), count >= 0, count <= 16, count.rounded() == count else { return FanSnapshot(error: "Could not read this Mac’s fans.") }
        var result = FanSnapshot(date: Date(), detectedFanCount: Int(count))
        for index in 0..<Int(count) {
            guard let rpm = read("F\(index)Ac"), rpm >= 0 else { continue }
            let mode = read("F\(index)Md") ?? read("F\(index)md")
            result.fans.append(FanReading(id: index, name: count == 1 ? "Fan" : "Fan \(index + 1)", rpm: rpm,
                                         minimum: read("F\(index)Mn") ?? 0, maximum: read("F\(index)Mx") ?? 0, manual: mode == 1))
        }
        if result.fans.count != Int(count) { result.error = "Could not read all fan speeds." }
        if hasCalibratedSensors {
            let cpuAverage = read("TCMb").flatMap { Self.validTemperature($0) ? $0 : nil }
            let cpuMaximum = read("TCMz").flatMap { Self.validTemperature($0) ? $0 : nil }
            if let value = cpuAverage ?? cpuMaximum {
                result.temperatures.append(TemperatureReading(id: "cpu-average", name: "CPU Average", celsius: value))
            }
            // Mac15,3's calibrated GPU sensors. Exclude paired raw values and CPU/SoC sensors.
            let gpuKeys = ["Tg0D", "Tg0P", "Tg0X", "Tg0b", "Tg0j", "Tg0v"]
            let gpu = gpuKeys.compactMap { read($0) }.filter(Self.validTemperature)
            if !gpu.isEmpty {
                result.temperatures.append(TemperatureReading(id: "gpu-average", name: "GPU Average", celsius: gpu.reduce(0, +) / Double(gpu.count)))
            }
            let battery = ["TB0T", "TB1T"].lazy.compactMap { self.read($0) }.first(where: Self.validTemperature)
            if let value = battery {
                result.temperatures.append(TemperatureReading(id: "battery", name: "Battery", celsius: value))
            }
            if let value = cpuMaximum, cpuAverage != nil {
                result.temperatures.append(TemperatureReading(id: "cpu-max", name: "CPU Maximum", celsius: value))
            }
            return result
        }
        if temperatureKeys == nil, let count = read("#KEY"), count > 0, count <= 20000 {
            var keys: [String] = []
            for index in 0..<Int(count) {
                guard let bytes = call(command: 8, index: UInt32(index)) else { continue }
                let key = fourCC(integer(bytes, 0))
                guard key.hasPrefix("T"), let (_, type) = info(key), ["flt ", "sp78"].contains(type),
                      let value = read(key), value > 0, value < 130 else { continue }
                keys.append(key)
            }
            temperatureKeys = keys
        }
        // Expose exact sensor keys for unknown hardware instead of inventing CPU/GPU labels.
        for key in temperatureKeys ?? [] {
            if let value = read(key), value > 0, value < 130 {
                result.temperatures.append(TemperatureReading(id: key, name: Self.sensorName(key), celsius: value))
            }
        }
        result.temperatures.sort { $0.celsius > $1.celsius }
        return result
    }
    private static func validTemperature(_ value: Double) -> Bool { value.isFinite && value > 0 && value < 130 }

    static func sensorName(_ key: String) -> String {
        ["TC0P": "CPU proximity", "TC0D": "CPU die", "TG0P": "GPU proximity", "TB0T": "Battery", "TB1T": "Battery", "Ts0P": "Palm rest" ][key] ?? key
    }
}
