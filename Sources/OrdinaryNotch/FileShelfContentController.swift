import AppKit
import Combine

enum FileShelfCommand {
    case copy, paste, selectAll
    static func resolve(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Self? {
        let flags = modifiers.intersection([.command, .control, .option, .shift])
        guard flags == .command || flags == .control else { return nil }
        switch keyCode {
        case 8: return .copy
        case 9: return .paste
        case 0: return .selectAll
        default: return nil
        }
    }
}

final class FileShelfCollectionView: NSCollectionView {
    var command: (FileShelfCommand) -> Void = { _ in }
    var clicked: (Bool) -> Void = { _ in }
    var interactionChanged: (Bool) -> Void = { _ in }
    var contextMenu: (IndexPath?) -> NSMenu? = { _ in nil }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        interactionChanged(true)
        defer { interactionChanged(false) }
        super.mouseDown(with: event)
        // AppKit finishes click, range, or rubber-band selection before copying.
        if !event.modifierFlags.contains(.control) { clicked(event.clickCount == 2) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeKey()
        window?.makeFirstResponder(self)
        return contextMenu(indexPathForItem(at: convert(event.locationInWindow, from: nil)))
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              let action = FileShelfCommand.resolve(keyCode: event.keyCode, modifiers: event.modifierFlags) else {
            return super.performKeyEquivalent(with: event)
        }
        command(action)
        return true
    }
    override func keyDown(with event: NSEvent) {
        if let action = FileShelfCommand.resolve(keyCode: event.keyCode, modifiers: event.modifierFlags) { command(action) }
        else { super.keyDown(with: event) }
    }
}

@MainActor
final class FileShelfContentController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate, NSMenuDelegate {
    let collection = FileShelfCollectionView()
    private let model: FileShelfViewModel
    private var rows: [FileShelfViewModel.Item] = []
    private var subscription: AnyCancellable?
    private var updating = false
    private let itemIdentifier = NSUserInterfaceItemIdentifier("FileShelfItem")
    init(model: FileShelfViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 88, height: 72)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        collection.collectionViewLayout = layout
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.dataSource = self
        collection.delegate = self
        collection.register(FileShelfCollectionItem.self, forItemWithIdentifier: itemIdentifier)
        collection.setDraggingSourceOperationMask(.copy, forLocal: false)
        collection.setDraggingSourceOperationMask(.copy, forLocal: true)
        collection.setAccessibilityLabel("File Shelf")
        collection.command = { [weak self] in self?.perform($0) }
        collection.interactionChanged = { [weak self] in self?.model.isSelectingFiles = $0 }
        collection.clicked = { [weak self] open in
            guard let self else { return }
            self.selectionChanged()
            if open, let item = self.model.selectedItems.first { self.model.open(item) }
            else { self.model.copySelection() }
        }
        collection.contextMenu = { [weak self] path in self?.makeMenu(at: path) }
        scroll.documentView = collection
        view = scroll
        subscription = model.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }
        refresh()
    }
    private func refresh() {
        updating = true
        defer { updating = false }
        if rows.map(\.id) != model.items.map(\.id) {
            rows = model.items
            collection.reloadData()
        }
        collection.selectionIndexPaths = Set(rows.enumerated().compactMap { index, item in
            model.selectedIDs.contains(item.id) ? IndexPath(item: index, section: 0) : nil
        })
        for index in rows.indices {
            (collection.item(at: IndexPath(item: index, section: 0)) as? FileShelfCollectionItem)?.configure(rows[index])
        }
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { rows.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: itemIdentifier, for: indexPath) as! FileShelfCollectionItem
        item.configure(rows[indexPath.item])
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { selectionChanged() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { selectionChanged() }
    private func selectionChanged() {
        guard !updating else { return }
        model.select(Set(collection.selectionIndexPaths.compactMap { rows.indices.contains($0.item) ? rows[$0.item].id : nil }))
    }
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard rows.indices.contains(indexPath.item), rows[indexPath.item].isAvailable else { return nil }
        return rows[indexPath.item].url as NSURL
    }
    func perform(_ command: FileShelfCommand) {
        switch command {
        case .copy: model.copySelection()
        case .paste: model.paste()
        case .selectAll: model.selectAll()
        }
        refresh()
    }
    func makeMenu(at path: IndexPath?) -> NSMenu {
        if let path, rows.indices.contains(path.item), !model.selectedIDs.contains(rows[path.item].id) {
            model.select([rows[path.item].id])
            refresh()
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        func add(_ title: String, action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; item.isEnabled = enabled
            menu.addItem(item)
        }
        add("Copy", action: #selector(copyFiles), enabled: !model.selectedIDs.isEmpty)
        add("Paste", action: #selector(pasteFiles), enabled: model.canPaste)
        add("Select All", action: #selector(selectFiles), enabled: !rows.isEmpty)
        if !model.selectedIDs.isEmpty {
            menu.addItem(.separator())
            add("Open", action: #selector(openFiles))
            add("Show in Finder", action: #selector(revealFiles))
            add("Remove from Shelf", action: #selector(removeFiles))
        }
        return menu
    }
    func menuWillOpen(_ menu: NSMenu) { model.isMenuOpen = true }
    func menuDidClose(_ menu: NSMenu) { model.isMenuOpen = false }
    override func viewWillDisappear() {
        super.viewWillDisappear()
        model.isSelectingFiles = false
        model.isMenuOpen = false
    }
    @objc private func copyFiles() { perform(.copy) }
    @objc private func pasteFiles() { perform(.paste) }
    @objc private func selectFiles() { perform(.selectAll) }
    @objc private func openFiles() { for item in model.selectedItems { model.open(item) } }
    @objc private func revealFiles() { model.revealSelection() }
    @objc private func removeFiles() { model.removeSelection() }
}

private final class FileShelfCollectionItem: NSCollectionViewItem {
    private let thumbnail = NSImageView()
    private let name = NSTextField(wrappingLabelWithString: "")
    override var isSelected: Bool { didSet { updateSelection() } }
    override func loadView() {
        view = NotchHintTrackingView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        name.font = .systemFont(ofSize: 11)
        name.textColor = .white
        name.alignment = .center
        name.maximumNumberOfLines = 1
        name.lineBreakMode = .byTruncatingMiddle
        for child in [thumbnail, name] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            thumbnail.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 64),
            thumbnail.heightAnchor.constraint(equalToConstant: 36),
            name.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 3),
            name.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            name.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            name.heightAnchor.constraint(equalToConstant: 16),
            name.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -3)
        ])
        updateSelection()
    }
    func configure(_ item: FileShelfViewModel.Item) {
        _ = view
        thumbnail.image = item.thumbnail ?? item.icon
        name.stringValue = item.url.lastPathComponent
        (view as? NotchHintTrackingView)?.hint = "Click to copy \(item.url.lastPathComponent). Double-click to open. Drag to share."
        view.alphaValue = item.isAvailable ? 1 : 0.5
        view.setAccessibilityLabel(item.url.lastPathComponent)
    }
    private func updateSelection() {
        guard isViewLoaded else { return }
        view.layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.4) : .clear).cgColor
        view.layer?.borderWidth = isSelected ? 1 : 0
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
    }
}
