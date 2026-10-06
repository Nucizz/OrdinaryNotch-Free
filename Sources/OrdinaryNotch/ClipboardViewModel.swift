import Combine
import Foundation

@MainActor
final class ClipboardViewModel: ObservableObject {
    static let maximumItems = 50
    static let maximumBytes = 16 * 1_024 * 1_024
    @Published private(set) var enabled = false
    @Published private(set) var items: [ClipboardEntry] = []
    @Published var query = ""
    @Published var selectedID: UUID?
    @Published private(set) var error: String?
    @Published var shortcutError: String?
    private var suspended = false
    private let service: ClipboardServing
    init(service: ClipboardServing? = nil) { self.service = service ?? ClipboardService() }
    var filteredItems: [ClipboardEntry] {
        let matches = items.filter { query.isEmpty || $0.searchText.localizedCaseInsensitiveContains(query) }
        return matches.filter(\.pinned) + matches.filter { !$0.pinned }
    }
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        if value { resumeIfNeeded() }
        else { service.stop(); clear(); query = ""; shortcutError = nil }
    }
    func suspend(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        if value { service.stop() } else { resumeIfNeeded() }
    }
    private func resumeIfNeeded() {
        guard enabled, !suspended else { return }
        service.start { [weak self] in self?.receive($0) }
    }
    func receive(_ entry: ClipboardEntry) {
        guard enabled, !suspended, entry.byteCount <= ClipboardService.maximumEntryBytes else { return }
        var updated = entry
        if let index = items.firstIndex(where: { $0.fingerprint == entry.fingerprint }) {
            updated = items.remove(at: index)
        }
        items.insert(updated, at: 0)
        while items.count > Self.maximumItems || items.reduce(0, { $0 + $1.byteCount }) > Self.maximumBytes {
            guard let index = items.lastIndex(where: { !$0.pinned }) else { break }
            items.remove(at: index)
        }
    }
    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
    }
    func remove(_ id: UUID) { items.removeAll { $0.id == id }; error = nil }
    func clear() {
        items.removeAll(); selectedID = nil; error = nil
        // Invalidate any read already in flight so Clear cannot immediately refill history.
        if enabled, !suspended { service.stop(); resumeIfNeeded() }
    }
    func prepareToShow() { query = ""; error = nil; selectedID = filteredItems.first?.id }
    func moveSelection(by offset: Int) {
        let visible = filteredItems
        guard !visible.isEmpty else { selectedID = nil; return }
        let index = visible.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : visible.count)
        selectedID = visible[min(visible.count - 1, max(0, index + offset))].id
    }
    func copy(_ id: UUID? = nil) -> Bool {
        guard enabled, !suspended else { return false }
        let visible = filteredItems
        let entry = id.flatMap { id in visible.first { $0.id == id } }
            ?? (id == nil ? (visible.first { $0.id == selectedID } ?? visible.first) : nil)
        guard let entry else { return false }
        guard service.write(entry) else { error = "Could not copy this item. Try again."; return false }
        selectedID = entry.id
        error = nil
        return true
    }
    func reportPasteResult(_ result: ClipboardPasteResult) { error = result.message }
}
