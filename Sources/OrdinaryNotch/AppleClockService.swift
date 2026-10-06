import AppKit
import Combine
import Foundation
import SQLite3

struct AppleTimer: Identifiable, Equatable {
    let id: String
    let title: String
    let duration: TimeInterval
    let remaining: TimeInterval
    let deadline: Date?
    let state: Int
    var isRunning: Bool { state == 3 }
    var isPaused: Bool { state == 2 }
    func value(at date: Date) -> TimeInterval { max(0, deadline?.timeIntervalSince(date) ?? remaining) }
}

struct AppleStopwatch: Equatable {
    var elapsed: TimeInterval = 0
    var started: Date?
    var laps: [TimeInterval] = []
    var isRunning: Bool { started != nil }
    func value(at date: Date) -> TimeInterval { elapsed + max(0, started.map { date.timeIntervalSince($0) } ?? 0) }
}

/// Read-only adapter for the storage shipped with Apple Clock on this Mac.
/// These are undocumented formats: reject unrecognized records instead of fabricating state.
enum AppleClockReader {
    static func stopwatch(from preferences: [String: Any]) -> AppleStopwatch? {
        guard let records = preferences["MTStopwatches"] as? [[String: Any]],
              let record = records.first?["$MTStopwatch"] as? [String: Any],
              let state = record["MTStopwatchState"] as? Int, (0...2).contains(state) else { return nil }
        if state == 0 { return AppleStopwatch() }
        let offset = (record["MTStopwatchOffset"] as? NSNumber)?.doubleValue ?? 0
        let previous = (record["MTStopwatchPreviousLapsTotalInterval"] as? NSNumber)?.doubleValue ?? 0
        let start = record["MTStopwatchStartDate"] as? Date
        guard state != 2 || start != nil else { return nil }
        return AppleStopwatch(elapsed: max(0, previous + offset), started: state == 2 ? start : nil,
                              laps: (record["MTStopwatchLaps"] as? [NSNumber] ?? []).map(\.doubleValue))
    }

    static func timer(id: String, title: String, duration: Double, state: Int, fireTime: Data) -> AppleTimer? {
        guard state == 2 || state == 3 || state == 4,
              let archive = try? PropertyListSerialization.propertyList(from: fireTime, format: nil) as? [String: Any],
              let objects = archive["$objects"] as? [Any] else { return nil }
        let dictionaries = objects.compactMap { $0 as? [String: Any] }
        let interval = dictionaries.compactMap { ($0["MTTimerTimeInterval"] as? NSNumber)?.doubleValue }.first
        let date = dictionaries.compactMap { ($0["NS.time"] as? NSNumber)?.doubleValue }.first.map(Date.init(timeIntervalSinceReferenceDate:))
        guard (state == 2 && interval != nil) || (state != 2 && date != nil) else { return nil }
        return AppleTimer(id: id, title: title.isEmpty ? "Timer" : title, duration: duration,
                          remaining: interval ?? 0, deadline: date, state: state)
    }

    static func timers(at path: String) throws -> [AppleTimer] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if database != nil { sqlite3_close(database) }
            throw ReadError.unavailable
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 150)
        var statement: OpaquePointer?
        let sql = "SELECT Z_PK, ZTITLE, ZDURATION, ZSTATE, ZFIRETIME FROM ZMTCDTIMER WHERE ZSTATE IN (2, 3, 4)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw ReadError.unsupported }
        defer { sqlite3_finalize(statement) }
        var timers: [AppleTimer] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "Timer"
            guard let bytes = sqlite3_column_blob(statement, 4) else { throw ReadError.unsupported }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 4)))
            guard let timer = timer(id: String(sqlite3_column_int64(statement, 0)), title: title,
                                   duration: sqlite3_column_double(statement, 2), state: Int(sqlite3_column_int(statement, 3)), fireTime: data) else {
                throw ReadError.unsupported
            }
            timers.append(timer)
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw ReadError.unavailable }
        return timers.sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }
    enum ReadError: Error { case unavailable, unsupported }
}


struct ClockSnapshot {
    var timers: [AppleTimer]
    var stopwatch: AppleStopwatch
    var timerError: String?
    var stopwatchError: String?
}
@MainActor
protocol ClockReading {
    func read() async -> ClockSnapshot
    func open(stopwatch: Bool)
}
@MainActor
final class AppleClockService: ClockReading {
    private let queue = DispatchQueue(label: "ordinary.apple-clock", qos: .utility)
    private let databasePath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/group.com.apple.mobiletimerd/local.sqlite").path
    func read() async -> ClockSnapshot {
        let path = databasePath
        return await withCheckedContinuation { continuation in
            queue.async {
                var timers: [AppleTimer] = []
                var readError: String?
                do { timers = try AppleClockReader.timers(at: path) }
                catch { readError = "Clock timer data is unavailable on this Mac. Open Apple Clock to manage timers." }
                let domain = "com.apple.mobiletimerd" as CFString
                CFPreferencesAppSynchronize(domain)
                let preferences = CFPreferencesCopyAppValue("MTStopwatches" as CFString, domain) as? [String: Any]
                let stopwatch = preferences.flatMap(AppleClockReader.stopwatch(from:))
                continuation.resume(returning: ClockSnapshot(timers: timers, stopwatch: stopwatch ?? AppleStopwatch(), timerError: readError,
                    stopwatchError: stopwatch == nil ? "Open Apple Clock once to make stopwatch data available." : nil))
            }
        }
    }
    func open(stopwatch: Bool) {
        if let url = URL(string: stopwatch ? "clock-stopwatch://" : "clock-timer://"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Clock.app"))
    }
}
