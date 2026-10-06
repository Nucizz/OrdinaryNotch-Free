import Foundation
import ActivityCore

/// Readers and hook directories are separated by the canonical configuration root.
final class ClaudeProfileActivityReader: @unchecked Sendable {
    private let lock = NSLock()
    private var readers: [String: ClaudeActivityReader] = [:]
    func read(profiles: [CodeProfile], now: Date = Date()) -> [CodeTask] {
        lock.lock(); defer { lock.unlock() }
        return profiles.flatMap { profile in
            let reader: ClaudeActivityReader
            if let cached = readers[profile.id] { reader = cached }
            else {
                reader = ClaudeActivityReader(root: profile.root.appendingPathComponent("projects"),
                    hooks: profile.root.appendingPathComponent("ordinary-notch/activity"),
                    additionalHooks: profile.account == .personal && profile.id == ClaudeProfiles().profile(.personal).id
                        ? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OrdinaryNotch/ClaudeActivity")] : [])
                readers[profile.id] = reader
            }
            let usage = Self.usage(root: profile.root, now: now)
            var tasks = reader.readTasks(now: now).map { task in
                var task = task
                task.id = profile.id + ":" + task.id
                task.profileID = profile.id; task.account = profile.account; task.sourceApplication = profile.runtime
                task.activity.usage = usage
                return task
            }
            if tasks.isEmpty, let usage {
                var task = CodeTask(id: profile.id + ":usage", provider: .claude, activity: .idle, profileID: profile.id,
                                    account: profile.account, sourceApplication: profile.runtime, isUsageOnly: true)
                task.activity.usage = usage
                tasks.append(task)
            }
            return tasks
        }
    }
    static func usage(root: URL, now: Date) -> CodexUsage? {
        let file = ClaudeUsageSnapshot.file(in: root)
        guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size < 65536,
              let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(ClaudeUsageSnapshot.self, from: data),
              value.updatedAt <= now.timeIntervalSince1970 + 5,
              now.timeIntervalSince1970 - value.updatedAt < 1800 else { return nil }
        let windows = value.windows.compactMap { window -> CodexUsage.Window? in
            guard ["five_hour", "seven_day"].contains(window.id), (0...100).contains(window.used),
                  window.resetsAt > now.timeIntervalSince1970 else { return nil }
            return .init(id: window.id, usedPercent: window.used, minutes: window.id == "five_hour" ? 300 : 10080,
                         resetsAt: Date(timeIntervalSince1970: window.resetsAt))
        }
        return windows.isEmpty ? nil : CodexUsage(windows: windows, updatedAt: Date(timeIntervalSince1970: value.updatedAt))
    }
}
