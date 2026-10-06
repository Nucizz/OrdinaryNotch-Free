import AppKit
import Combine

/// Session-only references: removing an item never changes the original file.
@MainActor
final class FileShelfViewModel: ObservableObject {
    final class Item: Identifiable {
        let url: URL
        let icon: NSImage
        var thumbnail: NSImage?
        var thumbnailRequest: FileThumbnailRequest?
        var id: URL { url.standardizedFileURL }
        private let scoped: Bool
        init?(url: URL) {
            guard url.isFileURL else { return nil }
            let scoped = url.startAccessingSecurityScopedResource()
            guard FileManager.default.fileExists(atPath: url.path) else {
                if scoped { url.stopAccessingSecurityScopedResource() }
                return nil
            }
            self.url = url
            self.scoped = scoped
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
        deinit {
            thumbnailRequest?.cancel()
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
    }
    @Published private(set) var items: [Item] = []
    @Published var error: String?
    private let thumbnails: FileThumbnailServing

    init(thumbnails: FileThumbnailServing? = nil) {
        self.thumbnails = thumbnails ?? FileThumbnailService()
    }

    @discardableResult func add(_ urls: [URL]) -> Bool {
        var accepted = false
        var rejected = false
        for url in urls {
            if items.contains(where: { $0.id == url.standardizedFileURL }) { accepted = true; continue }
            guard let item = Item(url: url) else { rejected = true; continue }
            items.append(item)
            item.thumbnailRequest = thumbnails.request(for: url) { [weak self, weak item] image in
                guard let self, let item, self.items.contains(where: { $0 === item }) else { return }
                self.objectWillChange.send()
                item.thumbnail = image
                item.thumbnailRequest = nil
            }
            accepted = true
        }
        error = rejected ? "Some files are unavailable. Drag them from Finder again." : nil
        return accepted
    }
    func remove(_ item: Item) {
        item.thumbnailRequest?.cancel(); item.thumbnailRequest = nil
        items.removeAll { $0.id == item.id }; error = nil
    }
    func clear() {
        for item in items { item.thumbnailRequest?.cancel(); item.thumbnailRequest = nil }
        items.removeAll(); error = nil
    }
    func reveal(_ item: Item) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    func open(_ item: Item) {
        error = NSWorkspace.shared.open(item.url) ? nil : "This file is no longer available at its original location."
    }
}
