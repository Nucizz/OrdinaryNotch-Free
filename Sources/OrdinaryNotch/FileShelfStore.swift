import Foundation

@MainActor
final class FileShelfStore {
    private let defaults: UserDefaults
    private let key = "notch.fileShelf.paths.v1"
    init(defaults: UserDefaults) { self.defaults = defaults }

    func load() -> [URL] {
        (defaults.stringArray(forKey: key) ?? []).filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
    }
    func save(_ urls: [URL]) { defaults.set(urls.map(\.path), forKey: key) }
    func clear() { defaults.removeObject(forKey: key) }
}
