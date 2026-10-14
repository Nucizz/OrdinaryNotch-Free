import Foundation
import CoreServices
import Darwin

/// Recursive, coalesced notifications also cover SQLite WALs and atomic file replacement.
/// Failed/dropped watches are safe: callers retain a bounded fallback refresh.
final class FileChangeMonitor {
    private final class Handler {
        let paths: [String]
        let changed: @Sendable () -> Void
        init(paths: [String], changed: @escaping @Sendable () -> Void) { self.paths = paths; self.changed = changed }
    }
    private let queue = DispatchQueue(label: "ordinary.file-changes", qos: .utility)
    private var stream: FSEventStreamRef?
    private var handler: Handler?
    private var paths: [String] = []
    @discardableResult func watch(_ urls: [URL], changed: @escaping @Sendable () -> Void) -> Bool {
        let paths = Array(Set(urls.map(Self.canonicalPath))).sorted()
        if self.paths == paths, stream != nil { return true }
        stop()
        guard !paths.isEmpty else { return false }
        let handler = Handler(paths: paths, changed: changed)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        // Watch the nearest existing parent when a profile has not been created yet.
        let roots = Set(paths.map { path -> String in
            var url = URL(fileURLWithPath: path)
            while !FileManager.default.fileExists(atPath: url.path), url.path != "/" { url.deleteLastPathComponent() }
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue { url.deleteLastPathComponent() }
            return url.path
        })
        let callback: FSEventStreamCallback = { _, context, count, eventPaths, flags, _ in
            guard let context else { return }
            let handler = Unmanaged<Handler>.fromOpaque(context).takeUnretainedValue()
            let events = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            let dropped = (0..<count).contains { flags[$0] & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0 }
            if dropped || events.contains(where: { event in
                handler.paths.contains { event == $0 || event.hasPrefix($0 + "/") || $0.hasPrefix(event + "/") }
            }) { handler.changed() }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, Array(roots) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)) else { return false }
        self.handler = handler; self.stream = stream; self.paths = paths
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else { stop(); return false }
        return true
    }
    func stop() {
        if let stream {
            FSEventStreamStop(stream); FSEventStreamInvalidate(stream)
            // Drain callbacks before releasing their unretained context.
            queue.sync {}
            FSEventStreamRelease(stream)
        }
        stream = nil; handler = nil; paths = []
    }
    private static func canonicalPath(_ url: URL) -> String {
        // Foundation can preserve /var for not-yet-created descendants, while
        // FSEvents reports /private/var. Resolve the existing ancestor with the
        // filesystem, then restore the missing path components.
        var path = url.path
        var suffix: [String] = []
        while path != "/", !FileManager.default.fileExists(atPath: path) {
            suffix.insert((path as NSString).lastPathComponent, at: 0)
            path = (path as NSString).deletingLastPathComponent
        }
        if let resolved = realpath(path, nil) {
            path = String(cString: resolved); free(resolved)
        }
        return suffix.reduce(path) { ($0 as NSString).appendingPathComponent($1) }
    }
    deinit { stop() }
}
