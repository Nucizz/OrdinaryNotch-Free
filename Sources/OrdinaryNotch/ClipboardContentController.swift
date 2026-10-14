import AppKit
import Combine

private final class ClipboardTableView: NSTableView {
    var command: (NSEvent) -> Bool = { _ in false }
    override func keyDown(with event: NSEvent) { if !command(event) { super.keyDown(with: event) } }
}

/// Maccy's compact menu layout adapted to our AppKit controls and bounded history model.
/// MIT attribution: Resources/Maccy-LICENSE.txt. Upstream revision: docs/clipboard-history.md.
@MainActor
final class ClipboardContentController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
                                         NSTextFieldDelegate, NSMenuDelegate {
    let searchField = NSTextField()
    private let clearSearchButton = NSButton()
    private let table = ClipboardTableView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let previewScroll = NSScrollView()
    private let previewText = NSTextView()
    private let previewButton = NSButton()
    private let model: ClipboardViewModel
    private let closeHistory: () -> Void
    private let pasteSelection: (() -> Void)?
    private let openPreferences: () -> Void
    var sizeChanged: ((CGFloat, Bool) -> Void)?
    private var rows: [ClipboardEntry] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var updatingSelection = false
    private var contextID: UUID?
    private var footer: [ClipboardMenuButton] = []
    private var footerSelection: Int? { didSet {
        for (index, button) in footer.enumerated() { button.selected = index == footerSelection }
    } }
    private var previewWidth: NSLayoutConstraint!
    private var errorHeight: NSLayoutConstraint!
    private var previewVisible = false
    private var clearAll = false
    private var separatorIndex: Int? {
        guard let first = rows.first, first.pinned else { return nil }
        return rows.firstIndex { !$0.pinned }
    }
    var preferredHeight: CGFloat {
        5 + 23 + 12 + max(3 * ClipboardMenuMetrics.rowHeight,
            rows.indices.reduce(0) { $0 + rowHeight($1) }) + 13 + 4 * ClipboardMenuMetrics.rowHeight + 5
            + (model.error == nil ? 0 : 48)
    }
    init(model: ClipboardViewModel, close: @escaping () -> Void, paste: (() -> Void)? = nil,
         preferences: @escaping () -> Void = {}) {
        self.model = model; closeHistory = close; pasteSelection = paste; openPreferences = preferences
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(model:close:)") }
    override func loadView() {
        let background = NSView()
        view = ClipboardGlassSurface.make(content: background)
        let title = NSTextField(labelWithString: "Clipboard")
        title.font = .systemFont(ofSize: 13); title.textColor = .secondaryLabelColor
        title.setContentHuggingPriority(.required, for: .horizontal)
        let searchContainer = NSView()
        searchContainer.wantsLayer = true
        searchContainer.layer?.cornerRadius = ClipboardMenuMetrics.cornerRadius
        searchContainer.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.1).cgColor
        searchField.isEditable = true; searchField.isSelectable = true
        searchField.placeholderString = "Search"
        searchField.focusRingType = .none; searchField.font = .systemFont(ofSize: 13)
        searchField.isBezeled = false; searchField.drawsBackground = false
        searchField.maximumNumberOfLines = 1
        searchField.setAccessibilityLabel("Search clipboard history"); searchField.delegate = self
        let searchIcon = NSImageView()
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.contentTintColor = .secondaryLabelColor
        clearSearchButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear search")
        clearSearchButton.isBordered = false; clearSearchButton.target = self
        clearSearchButton.action = #selector(clearSearch); clearSearchButton.toolTip = "Clear search"
        for child in [searchIcon, searchField, clearSearchButton] {
            child.translatesAutoresizingMaskIntoConstraints = false; searchContainer.addSubview(child)
        }
        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 5),
            searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 11), searchIcon.heightAnchor.constraint(equalToConstant: 11),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 5),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 17),
            searchField.trailingAnchor.constraint(equalTo: clearSearchButton.leadingAnchor, constant: -5),
            clearSearchButton.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            clearSearchButton.widthAnchor.constraint(equalToConstant: 11), clearSearchButton.heightAnchor.constraint(equalToConstant: 11),
            clearSearchButton.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -5)
        ])
        previewButton.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Toggle preview")
        previewButton.isBordered = false; previewButton.target = self; previewButton.action = #selector(togglePreview)
        previewButton.toolTip = "Toggle preview"
        let column = NSTableColumn(identifier: .init("item"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil; table.style = .plain; table.intercellSpacing = .zero
        table.rowHeight = ClipboardMenuMetrics.rowHeight; table.backgroundColor = .clear
        table.allowsMultipleSelection = false; table.selectionHighlightStyle = .regular
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self; table.target = self; table.action = #selector(copyClickedRow)
        table.command = { [weak self] in self?.handleKey($0) ?? false }
        table.setAccessibilityLabel("Copied items")
        let menu = NSMenu(); menu.delegate = self; table.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay; scroll.drawsBackground = false; scroll.borderType = .noBorder
        emptyLabel.alignment = .center; emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13)
        errorLabel.font = .systemFont(ofSize: 11); errorLabel.textColor = .systemRed
        let rule = NSBox(); rule.boxType = .separator
        let footerStack = NSStackView(); footerStack.orientation = .vertical; footerStack.spacing = 0; footerStack.alignment = .leading
        for (index, item) in [("Clear", "⌥⌘⌫"), ("Preferences…", "⌘,"), ("About", ""), ("Quit", "⌘Q")].enumerated() {
            let button = ClipboardMenuButton(item.0, shortcut: item.1)
            button.tag = index; button.target = self; button.action = #selector(footerClicked(_:))
            button.hovered = { [weak self] in self?.selectFooter(index) }
            footer.append(button); footerStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: footerStack.widthAnchor).isActive = true
        }
        previewText.isEditable = false; previewText.isSelectable = true; previewText.drawsBackground = false
        previewText.textContainerInset = NSSize(width: 12, height: 12)
        previewText.autoresizingMask = [.width]; previewText.isHorizontallyResizable = false
        previewText.textContainer?.widthTracksTextView = true
        previewScroll.documentView = previewText; previewScroll.hasVerticalScroller = true
        previewScroll.drawsBackground = false; previewScroll.isHidden = true
        for child in [title, searchContainer, previewButton, scroll, emptyLabel, errorLabel, rule, footerStack, previewScroll] {
            child.translatesAutoresizingMaskIntoConstraints = false; background.addSubview(child)
        }
        previewWidth = previewScroll.widthAnchor.constraint(equalToConstant: 0)
        errorHeight = errorLabel.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            previewWidth, errorHeight,
            previewScroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            previewScroll.topAnchor.constraint(equalTo: background.topAnchor),
            previewScroll.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            title.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            title.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchContainer.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            searchContainer.topAnchor.constraint(equalTo: background.topAnchor, constant: 5),
            searchContainer.heightAnchor.constraint(equalToConstant: 23),
            searchContainer.trailingAnchor.constraint(equalTo: previewButton.leadingAnchor, constant: -5),
            previewButton.widthAnchor.constraint(equalToConstant: 20),
            previewButton.heightAnchor.constraint(equalToConstant: 23),
            previewButton.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            previewButton.trailingAnchor.constraint(equalTo: previewScroll.leadingAnchor, constant: -15),
            scroll.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 5),
            scroll.trailingAnchor.constraint(equalTo: previewScroll.leadingAnchor, constant: -5),
            scroll.bottomAnchor.constraint(equalTo: errorLabel.topAnchor, constant: -6),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 10),
            errorLabel.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -10),
            errorLabel.bottomAnchor.constraint(equalTo: rule.topAnchor),
            rule.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 6),
            rule.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -6),
            rule.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -6),
            footerStack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            footerStack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            footerStack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -5)
        ])
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        model.$items.combineLatest(model.$query).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        model.$selectedID.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncSelection() }.store(in: &subscriptions)
        model.$error.receive(on: DispatchQueue.main).sink { [weak self] message in
            guard let self else { return }; self.errorLabel.stringValue = message ?? ""
            self.errorHeight.constant = message == nil ? 0 : 48
            self.sizeChanged?(self.preferredHeight, self.previewVisible)
        }.store(in: &subscriptions)
        reload()
    }
    func prepareForPresentation() { _ = view; footerSelection = nil; reload(); view.window?.makeFirstResponder(searchField) }
    private func reload() {
        updatingSelection = true; rows = model.filteredItems
        if searchField.stringValue != model.query { searchField.stringValue = model.query }
        clearSearchButton.isHidden = model.query.isEmpty
        table.reloadData(); updatingSelection = false; syncSelection()
        emptyLabel.stringValue = model.query.isEmpty ? "No copied items" : "No matching items"
        emptyLabel.isHidden = !rows.isEmpty
        sizeChanged?(preferredHeight, previewVisible)
    }
    private func syncSelection() {
        updatingSelection = true
        defer { updatingSelection = false }
        if footerSelection == nil, let index = rows.firstIndex(where: { $0.id == model.selectedID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false); table.scrollRowToVisible(index)
        } else { table.deselectAll(nil) }
        updatePreview()
    }
    private func rowHeight(_ row: Int) -> CGFloat {
        (rows[row].kind == .image ? 50 : ClipboardMenuMetrics.rowHeight) + (separatorIndex == row ? 13 : 0)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rowHeight(row) }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = ClipboardMenuRowView(); view.separator = separatorIndex == row
        view.hovered = { [weak self] in
            guard let self, self.rows.indices.contains(row) else { return }
            self.footerSelection = nil; self.model.selectedID = self.rows[row].id
        }
        return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let item = rows[row], cell = NSTableCellView()
        let label = NSTextField(labelWithString: item.title.replacingOccurrences(of: "\n", with: " "))
        label.font = .systemFont(ofSize: 13); label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1; cell.textField = label
        let number = rows[..<row].filter { !$0.pinned }.count + 1
        let shortcut = NSTextField(labelWithString: item.pinned ? "" : number <= 9 ? "⌘\(number)" : "")
        shortcut.font = .systemFont(ofSize: 13)
        shortcut.setContentCompressionResistancePriority(.required, for: .horizontal)
        for child in [label, shortcut] { child.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(child) }
        let offset: CGFloat = separatorIndex == row ? 6.5 : 0
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: shortcut.leadingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor, constant: offset),
            shortcut.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            shortcut.centerYAnchor.constraint(equalTo: label.centerYAnchor)
        ])
        if item.pinned {
            let pin = NSImageView()
            pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
            pin.contentTintColor = .secondaryLabelColor
            pin.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(pin)
            NSLayoutConstraint.activate([
                pin.widthAnchor.constraint(equalToConstant: 12), pin.heightAnchor.constraint(equalToConstant: 12),
                pin.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                pin.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: pin.leadingAnchor, constant: -10)
            ])
        }
        if let thumbnail = item.thumbnail, item.kind == .image {
            label.isHidden = true
            let image = NSImageView(); image.image = thumbnail; image.imageScaling = .scaleProportionallyDown
            image.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(image); cell.imageView = image
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: label.leadingAnchor),
                image.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: min(340, max(40, thumbnail.size.width))),
                image.heightAnchor.constraint(equalToConstant: 40)
            ])
        }
        cell.toolTip = item.title; cell.setAccessibilityLabel(item.title + (item.pinned ? ", pinned" : ""))
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingSelection, rows.indices.contains(table.selectedRow) else { return }
        footerSelection = nil; model.selectedID = rows[table.selectedRow].id
    }
    @objc private func clearSearch() {
        model.query = ""; searchField.stringValue = ""; footerSelection = nil
        model.selectedID = model.filteredItems.first?.id; view.window?.makeFirstResponder(searchField)
    }
    func controlTextDidChange(_ notification: Notification) {
        footerSelection = nil; model.query = searchField.stringValue; model.selectedID = model.filteredItems.first?.id
    }
    private func moveSelection(_ offset: Int) {
        if let footerSelection {
            if footerSelection == 0 && offset < 0 && !rows.isEmpty {
                self.footerSelection = nil; model.selectedID = rows.last?.id
            } else { selectFooter((footerSelection + offset + footer.count) % footer.count) }
        } else if rows.isEmpty || (offset > 0 && model.selectedID == rows.last?.id) { selectFooter(0) }
        else { model.moveSelection(by: offset) }
    }
    private func selectFooter(_ index: Int) { footerSelection = index; syncSelection() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1)
        case #selector(NSResponder.insertNewline(_:)): activateSelection()
        case #selector(NSResponder.cancelOperation(_:)): closeHistory()
        default: return false
        }
        return true
    }
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == .command, key == "," { performFooter(1); return true }
        if flags == .command, key == "q" { performFooter(3); return true }
        if flags == .option, key == "p", let id = model.selectedID { model.togglePin(id); return true }
        if event.keyCode == 51, flags == .option, let id = model.selectedID { model.remove(id); return true }
        if event.keyCode == 51, flags == [.command, .option] { model.clearUnpinned(); return true }
        if event.keyCode == 51, flags == [.command, .option, .shift] { model.clear(); return true }
        if (flags == .command || flags == [.command, .option]), let number = Int(key), (1...9).contains(number) {
            let items = rows.filter { !$0.pinned }
            if items.indices.contains(number - 1), model.copy(items[number - 1].id) {
                if flags.contains(.option), let pasteSelection { pasteSelection() } else { closeHistory() }
            }
            return true
        }
        if event.keyCode == 36 || event.keyCode == 76 { activateSelection(); return true }
        if event.keyCode == 53 { closeHistory(); return true }
        if event.keyCode == 125 { moveSelection(1); return true }
        if event.keyCode == 126 { moveSelection(-1); return true }
        return false
    }
    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        clearAll = flags.contains([.command, .option, .shift])
        footer.first?.caption.stringValue = clearAll ? "Clear All" : "Clear"
        footer.first?.shortcut.stringValue = clearAll ? "⇧⌥⌘⌫" : "⌥⌘⌫"
    }
    private func activateSelection() {
        if let footerSelection { performFooter(footerSelection); return }
        guard model.copy() else { return }
        if let pasteSelection { pasteSelection() } else { closeHistory() }
    }
    @objc private func copyClickedRow() {
        guard rows.indices.contains(table.clickedRow), model.copy(rows[table.clickedRow].id) else { return }
        if NSEvent.modifierFlags.contains(.option), let pasteSelection { pasteSelection() } else { closeHistory() }
    }
    @objc private func footerClicked(_ sender: NSButton) { performFooter(sender.tag) }
    private func performFooter(_ index: Int) {
        switch index {
        case 0: if clearAll { model.clear() } else { model.clearUnpinned() }
        case 1: closeHistory(); openPreferences()
        case 2: closeHistory(); NSApp.activate(ignoringOtherApps: true); NSApp.orderFrontStandardAboutPanel(nil)
        case 3: NSApp.terminate(nil)
        default: break
        }
    }
    @objc private func togglePreview() {
        previewVisible.toggle(); previewWidth.constant = previewVisible ? 280 : 0; previewScroll.isHidden = !previewVisible
        previewButton.state = previewVisible ? .on : .off; updatePreview(); sizeChanged?(preferredHeight, previewVisible)
    }
    private func updatePreview() {
        guard previewVisible else { return }
        let item = rows.first { $0.id == model.selectedID }
        let text = item?.contents.compactMap { record in
            (record[NSPasteboard.PasteboardType.string.rawValue] ?? record[NSPasteboard.PasteboardType.URL.rawValue]
                ?? record[NSPasteboard.PasteboardType.fileURL.rawValue]).flatMap { String(data: $0, encoding: .utf8) }
        }.joined(separator: "\n") ?? ""
        let content = NSMutableAttributedString(string: text.isEmpty ? item?.title ?? "No item selected" : String(text.prefix(32_000)),
            attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        if let image = item?.thumbnail, item?.kind == .image {
            let attachment = NSTextAttachment(); attachment.image = image
            content.setAttributedString(NSAttributedString(attachment: attachment))
        }
        previewText.textStorage?.setAttributedString(content)
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
