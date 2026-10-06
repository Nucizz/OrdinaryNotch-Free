import Foundation

/// Match the actual runtime bundle, not the short-lived Work launcher or its helpers.
enum CodeAppPresence {
    static func isRunning(profile: CodeProfile, runningBundlePaths: Set<String>) -> Bool {
        guard let runtime = profile.runtime else { return false }
        return runningBundlePaths.contains(runtime.standardizedFileURL.resolvingSymlinksInPath().path)
    }
}

/// Reads only the desktop's persisted unread IDs. Does not mark tasks read or write to Codex.
final class CodexReadStateReader {
    private struct Cached {
        let modified: Date
        let size: UInt64
        let unread: Set<String>?
    }
    private var cache: [String: Cached] = [:]
    func unreadThreads(in root: URL) -> Set<String>? {
        let file = root.appendingPathComponent(".codex-global-state.json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attrs[.modificationDate] as? Date,
              let size = (attrs[.size] as? NSNumber)?.uint64Value, size <= 16 * 1024 * 1024 else { return nil }
        if let previous = cache[file.path], previous.modified == modified, previous.size == size { return previous.unread }
        guard let data = try? Data(contentsOf: file) else { return nil }
        let unread = Self.parse(data)
        cache[file.path] = Cached(modified: modified, size: size, unread: unread)
        return unread
    }
    static func parse(_ data: Data) -> Set<String>? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = json["electron-thread-read-state-v1"] as? [String: Any],
              state["version"] as? Int == 1,
              let identities = state["unreadByIdentity"] as? [String: [String: [String]]],
              identities.count == 1, let hosts = identities.values.first else { return nil }
        // Ambiguous account/host state is unknown, never evidence that a task was read.
        let local = hosts.filter { $0.key.hasPrefix("local:") }
        guard local.count == 1 else { return nil }
        return Set(local.values.first!)
    }
    static func wasRead(threadID: String?, activity: CodexActivity, unread: Set<String>?, now: Date) -> Bool {
        guard activity.state == "complete", let threadID, let unread else { return false }
        // Let the desktop persist the unread flag after a new terminal event.
        guard now.timeIntervalSince(activity.finishedAt ?? activity.updatedAt) >= 3 else { return false }
        return !unread.contains(threadID)
    }
}
