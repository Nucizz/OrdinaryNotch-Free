import Foundation

/// Reads changed bytes only, retaining incomplete records and bounding each poll's work.
final class IncrementalJSONLog<State> {
    private struct Entry {
        var offset: UInt64
        var modified: Date
        var inode: UInt64
        var state: State
        var pending: Data
    }
    private var cache: [String: Entry] = [:]
    private(set) var lastReadBytes = 0
    func read(_ url: URL, initial: @autoclosure () -> State, bootstrap: ((FileHandle, UInt64) -> (UInt64, State))? = nil, parse: (Data, State) -> State) -> State? {
        lastReadBytes = 0
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let modified = attrs[.modificationDate] as? Date else { return nil }
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let previous = cache[url.path]
        if let previous, previous.offset == size, previous.modified == modified, previous.inode == inode { return previous.state }
        let append = previous.map { $0.inode == inode && size > $0.offset } ?? false
        var entry = append ? previous! : Entry(offset: 0, modified: modified, inode: inode, state: initial(), pending: Data())
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        if !append, let bootstrap {
            let (offset, state) = bootstrap(handle, size)
            entry.offset = min(offset, size); entry.state = state
        }
        guard (try? handle.seek(toOffset: entry.offset)) != nil else { return nil }
        let end = min(size, entry.offset + 4 * 1024 * 1024)
        while entry.offset < end, let chunk = try? handle.read(upToCount: Int(min(262144, end - entry.offset))), !chunk.isEmpty {
            entry.offset += UInt64(chunk.count); lastReadBytes += chunk.count; entry.pending.append(chunk)
            if let newline = entry.pending.lastIndex(of: 10) {
                entry.state = parse(Data(entry.pending.prefix(through: newline)), entry.state)
                entry.pending = Data(entry.pending.suffix(from: entry.pending.index(after: newline)))
            }
            // Ignore a malformed giant record rather than retaining unbounded memory.
            if entry.pending.count > 4 * 1024 * 1024 { entry.pending.removeAll(keepingCapacity: false) }
        }
        entry.modified = modified; entry.inode = inode
        cache[url.path] = entry
        return entry.state
    }
    func retain(paths: Set<String>) { cache = cache.filter { paths.contains($0.key) } }
}
