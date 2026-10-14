import AppKit
import Combine

/// References only: removing or persisting an item never changes the original file.
@MainActor
final class FileShelfViewModel: ObservableObject {
    final class Item: Identifiable {
        let url: URL
        let icon: NSImage
        var thumbnail: NSImage?
        var thumbnailRequest: FileThumbnailRequest?
        var id: URL { url.standardizedFileURL }
        private let scoped: Bool
        var isAvailable: Bool { FileManager.default.fileExists(atPath: url.path) }
        init?(url: URL, allowUnavailable: Bool = false) {
            guard url.isFileURL else { return nil }
            let scoped = url.startAccessingSecurityScopedResource()
            guard allowUnavailable || FileManager.default.fileExists(atPath: url.path) else {
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
    @Published private(set) var selectedIDs: Set<URL> = []
    @Published private(set) var preservesFiles: Bool
    @Published var error: String?
    var isSelectingFiles = false
    var isMenuOpen = false
    var isInteracting: Bool { isSelectingFiles || isMenuOpen }
    private let thumbnails: FileThumbnailServing
    private let store: FileShelfStore?
    private let pasteboard: NSPasteboard
    var selectedItems: [Item] { items.filter { selectedIDs.contains($0.id) } }
    var canPaste: Bool { !pasteboardFiles.isEmpty }
    private var pasteboardFiles: [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    init(thumbnails: FileThumbnailServing? = nil, store: FileShelfStore? = nil,
         preservesFiles: Bool = false, pasteboard: NSPasteboard = .general) {
        self.thumbnails = thumbnails ?? FileThumbnailService()
        self.store = store
        self.preservesFiles = preservesFiles
        self.pasteboard = pasteboard
        if preservesFiles {
            add(store?.load() ?? [], restoring: true)
        } else { store?.clear() }
    }

    @discardableResult func add(_ urls: [URL]) -> Bool { add(urls, restoring: false) }

    @discardableResult private func add(_ urls: [URL], restoring: Bool) -> Bool {
        var accepted = false
        var rejected = false
        for url in urls {
            if items.contains(where: { $0.id == url.standardizedFileURL }) { accepted = true; continue }
            guard let item = Item(url: url, allowUnavailable: restoring) else { rejected = true; continue }
            items.append(item)
            if item.isAvailable {
                item.thumbnailRequest = thumbnails.request(for: url) { [weak self, weak item] image in
                    guard let self, let item, self.items.contains(where: { $0 === item }) else { return }
                    self.objectWillChange.send()
                    item.thumbnail = image
                    item.thumbnailRequest = nil
                }
            } else { rejected = true }
            accepted = true
        }
        error = rejected ? "Some files are unavailable. Reconnect their drive or add them again from Finder." : nil
        persist()
        return accepted
    }
    func setPreservesFiles(_ enabled: Bool) {
        guard preservesFiles != enabled else { return }
        preservesFiles = enabled
        if enabled { persist() } else { store?.clear() }
    }
    private func persist() { if preservesFiles { store?.save(items.map(\.url)) } }
    func select(_ ids: Set<URL>) {
        let valid = ids.intersection(Set(items.map(\.id)))
        if selectedIDs != valid { selectedIDs = valid }
    }
    func selectAll() { select(Set(items.map(\.id))) }
    @discardableResult func copySelection() -> Bool {
        let selected = selectedItems
        guard !selected.isEmpty else { return false }
        guard selected.allSatisfy(\.isAvailable) else {
            error = "Some selected files are unavailable. Reconnect their drive or remove them from the selection."
            return false
        }
        pasteboard.clearContents()
        let copied = pasteboard.writeObjects(selected.map { $0.url as NSURL })
        error = copied ? nil : "These files could not be copied. Try again."
        return copied
    }
    @discardableResult func paste() -> Bool {
        let urls = pasteboardFiles
        guard !urls.isEmpty else { error = "Copy files in Finder before pasting into the shelf."; return false }
        let accepted = add(urls)
        if accepted { select(Set(urls.map(\.standardizedFileURL))) }
        return accepted
    }
    func removeSelection() {
        for item in selectedItems { remove(item) }
    }
    func remove(_ item: Item) {
        item.thumbnailRequest?.cancel(); item.thumbnailRequest = nil
        items.removeAll { $0.id == item.id }; error = nil
        selectedIDs.remove(item.id)
        persist()
    }
    func clear() {
        for item in items { item.thumbnailRequest?.cancel(); item.thumbnailRequest = nil }
        items.removeAll(); error = nil
        selectedIDs.removeAll()
        persist()
    }
    func reveal(_ item: Item) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    func revealSelection() { NSWorkspace.shared.activateFileViewerSelecting(selectedItems.map(\.url)) }
    func open(_ item: Item) {
        error = NSWorkspace.shared.open(item.url) ? nil : "This file is no longer available at its original location."
    }
}
