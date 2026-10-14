import Foundation

struct SavedClipboardEntry: Codable {
    var contents: [[String: Data]]
    var pinned: Bool
}

/// Opt-in local storage. A serial queue keeps Clear ordered after pending writes.
final class ClipboardHistoryStore {
    static let maximumItems = 50
    static let maximumBytes = 16 * 1_024 * 1_024
    private let url: URL
    private let queue = DispatchQueue(label: "ordinary.clipboard-storage", qos: .utility)

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OrdinaryNotch/Clipboard/history.plist")) {
        self.url = url
    }

    func load() throws -> [SavedClipboardEntry] {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.maximumBytes + 1_024 * 1_024 else { throw StoreError.invalidHistory }
            let records = try PropertyListDecoder().decode([SavedClipboardEntry].self, from: Data(contentsOf: url))
            guard Self.valid(records) else { throw StoreError.invalidHistory }
            return records
        }
    }

    func save(_ records: [SavedClipboardEntry], completion: @escaping (Error?) -> Void) {
        queue.async {
            do {
                guard Self.valid(records) else { throw StoreError.invalidHistory }
                let folder = self.url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let data = try encoder.encode(records)
                try data.write(to: self.url, options: [.atomic])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.url.path)
                completion(nil)
            } catch { completion(error) }
        }
    }

    func clear(completion: @escaping (Error?) -> Void) {
        queue.async {
            do {
                if FileManager.default.fileExists(atPath: self.url.path) { try FileManager.default.removeItem(at: self.url) }
                completion(nil)
            } catch { completion(error) }
        }
    }

    func flush() { queue.sync {} }

    private static func valid(_ records: [SavedClipboardEntry]) -> Bool {
        guard records.count <= maximumItems else { return false }
        var bytes = 0
        for record in records {
            guard !record.contents.isEmpty, record.contents.count <= 32 else { return false }
            var entryBytes = 0
            for item in record.contents {
                let supported: Set<String> = ["public.utf8-plain-text", "public.url", "public.file-url", "public.rtf", "public.html", "public.png", "public.tiff"]
                guard !item.isEmpty, Set(item.keys).isSubset(of: supported),
                      Set(item.keys).isDisjoint(with: ClipboardService.ignoredTypes) else { return false }
                entryBytes += item.values.reduce(0) { $0 + $1.count }
            }
            guard entryBytes <= ClipboardService.maximumEntryBytes else { return false }
            bytes += entryBytes
        }
        return bytes <= maximumBytes
    }

    private enum StoreError: LocalizedError {
        case invalidHistory
        var errorDescription: String? { "Saved clipboard history is invalid or exceeds the storage limit." }
    }
}
