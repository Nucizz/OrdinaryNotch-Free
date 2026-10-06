import AppKit
import Combine

private final class ClipboardTableView: NSTableView {
    var copySelection: () -> Void = {}
    var closeHistory: () -> Void = {}
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { copySelection() }
        else if event.keyCode == 53 { closeHistory() }
        else { super.keyDown(with: event) }
    }
}

/// Native AppKit controls; the model continues to own capture, search, and history.
@MainActor
final class ClipboardContentController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
                                         NSSearchFieldDelegate, NSMenuDelegate {
    let searchField = NSSearchField()
    private let table = ClipboardTableView()
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let model: ClipboardViewModel
    private let closeHistory: () -> Void
    private let pasteSelection: (() -> Void)?
    private var rows: [ClipboardEntry] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var updatingSelection = false
    private var contextID: UUID?

    init(model: ClipboardViewModel, close: @escaping () -> Void, paste: (() -> Void)? = nil) {
        self.model = model; closeHistory = close; pasteSelection = paste
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(model:close:)") }

    override func loadView() {
        let background = NSView()
        view = background
        searchField.placeholderString = "Search copied text and links"
        searchField.setAccessibilityLabel("Search clipboard history")
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self

        let itemColumn = NSTableColumn(identifier: .init("item"))
        itemColumn.resizingMask = .autoresizingMask
        table.addTableColumn(itemColumn)
        let pinColumn = NSTableColumn(identifier: .init("pin"))
        pinColumn.width = 30; pinColumn.minWidth = 30; pinColumn.maxWidth = 30
        pinColumn.resizingMask = []
        table.addTableColumn(pinColumn)
        table.headerView = nil
        table.style = .inset
        table.rowHeight = 44
        table.backgroundColor = .clear
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self
        table.target = self; table.action = #selector(copyClickedRow)
        table.copySelection = { [weak self] in self?.copySelected() }
        table.closeHistory = { [weak self] in self?.closeHistory() }
        table.setAccessibilityLabel("Copied items")
        let menu = NSMenu(); menu.delegate = self; table.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor
        countLabel.lineBreakMode = .byTruncatingTail
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        errorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        errorLabel.textColor = .systemRed
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.target = self; clearButton.action = #selector(clearHistory)
        let rule = NSBox(); rule.boxType = .separator
        for child in [searchField, scroll, emptyLabel, errorLabel, rule, countLabel, clearButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(child)
        }
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: errorLabel.topAnchor, constant: -4),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -24),
            errorLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            errorLabel.bottomAnchor.constraint(equalTo: rule.topAnchor, constant: -4),
            rule.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: clearButton.topAnchor, constant: -8),
            clearButton.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            clearButton.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),
            countLabel.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: clearButton.leadingAnchor, constant: -12),
            countLabel.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor)
        ])
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        model.$items.combineLatest(model.$query).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        model.$selectedID.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncSelection() }.store(in: &subscriptions)
        model.$error.receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.errorLabel.stringValue = message ?? "" }.store(in: &subscriptions)
        reload()
    }
    func prepareForPresentation() {
        _ = view
        reload()
        view.window?.makeFirstResponder(searchField)
    }
    private func reload() {
        updatingSelection = true
        rows = model.filteredItems
        if searchField.stringValue != model.query { searchField.stringValue = model.query }
        table.reloadData()
        updatingSelection = false
        syncSelection()
        emptyLabel.stringValue = model.query.isEmpty ? "Copy something to get started" : "No matching items"
        emptyLabel.isHidden = !rows.isEmpty
        countLabel.stringValue = "\(model.items.count) items · Return to paste · Esc to close"
        clearButton.isEnabled = !model.items.isEmpty
    }
    private func syncSelection() {
        updatingSelection = true
        defer { updatingSelection = false }
        if let index = rows.firstIndex(where: { $0.id == model.selectedID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            table.scrollRowToVisible(index)
        } else { table.deselectAll(nil) }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let item = rows[row]
        if tableColumn?.identifier.rawValue == "pin" {
            let button = NSButton(image: NSImage(systemSymbolName: item.pinned ? "pin.fill" : "pin", accessibilityDescription: nil)!,
                                  target: self, action: #selector(pinRow(_:)))
            button.isBordered = false; button.bezelStyle = .inline; button.tag = row
            button.toolTip = item.pinned ? "Unpin item" : "Pin item"
            button.setAccessibilityLabel(button.toolTip)
            return button
        }
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.image = item.thumbnail ?? NSImage(systemSymbolName: item.kind == .files ? "doc" : item.kind == .image ? "photo" : "text.alignleft", accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyDown
        let label = NSTextField(labelWithString: item.title)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        cell.imageView = icon; cell.textField = label
        for child in [icon, label] { child.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(child) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30), icon.heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        cell.toolTip = item.title
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingSelection, rows.indices.contains(table.selectedRow) else { return }
        model.selectedID = rows[table.selectedRow].id
    }
    func controlTextDidChange(_ notification: Notification) {
        model.query = searchField.stringValue
        model.selectedID = model.filteredItems.first?.id
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)): model.moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)): model.moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)): copySelected()
        case #selector(NSResponder.cancelOperation(_:)): closeHistory()
        default: return false
        }
        return true
    }
    private func copySelected() {
        guard model.copy() else { return }
        if let pasteSelection { pasteSelection() } else { closeHistory() }
    }
    @objc private func clearHistory() { model.clear() }
    @objc private func copyClickedRow() {
        guard rows.indices.contains(table.clickedRow) else { return }
        if model.copy(rows[table.clickedRow].id) { closeHistory() }
    }
    @objc private func pinRow(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag) else { return }
        model.togglePin(rows[sender.tag].id)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard rows.indices.contains(row) else { contextID = nil; return }
        let item = rows[row]; contextID = item.id
        for (title, action) in [("Copy", #selector(copyContext)), (item.pinned ? "Unpin" : "Pin", #selector(pinContext)), ("Remove", #selector(removeContext))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
    }
    @objc private func copyContext() { if let contextID, model.copy(contextID) { closeHistory() } }
    @objc private func pinContext() { if let contextID { model.togglePin(contextID) } }
    @objc private func removeContext() { if let contextID { model.remove(contextID) } }
}
