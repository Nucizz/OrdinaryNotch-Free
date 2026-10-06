import AppKit
import SwiftUI
import XCTest
@testable import OrdinaryNotch

@MainActor private final class ClipboardStub: ClipboardServing {
    var starts = 0, stops = 0
    var callback: (@MainActor (ClipboardEntry) -> Void)?
    var writes: [ClipboardEntry] = []
    var writeSucceeds = true
    func start(receive: @escaping @MainActor (ClipboardEntry) -> Void) { starts += 1; callback = receive }
    func stop() { stops += 1 }
    func write(_ entry: ClipboardEntry) -> Bool { writes.append(entry); return writeSucceeds }
}

final class ClipboardTests: XCTestCase {
    private func entry(_ text: String) -> ClipboardEntry {
        ClipboardEntry(contents: [[NSPasteboard.PasteboardType.string.rawValue: Data(text.utf8)]])
    }
    @MainActor func testOptInSurvivesRelaunchAndOlderSettingsDefaultOff() throws {
        let suite = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesViewModel(defaults: defaults)
        XCTAssertFalse(preferences.values.clipboardHistoryEnabled)
        preferences.values.clipboardHistoryEnabled = true
        XCTAssertTrue(PreferencesViewModel(defaults: defaults).values.clipboardHistoryEnabled)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences.values)) as? [String: Any])
        json.removeValue(forKey: "clipboardHistoryEnabled")
        let restored = try JSONDecoder().decode(NotchSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(restored.clipboardHistoryEnabled)
    }
    @MainActor func testDisabledAndSuspendedCaptureIsRejectedAndDisableClearsPins() {
        let service = ClipboardStub()
        let subject = ClipboardViewModel(service: service)
        XCTAssertFalse(subject.enabled)
        subject.receive(entry("before opt-in"))
        XCTAssertEqual(service.starts, 0); XCTAssertTrue(subject.items.isEmpty)
        subject.suspend(true); subject.setEnabled(true)
        XCTAssertEqual(service.starts, 0)
        subject.suspend(false)
        XCTAssertEqual(service.starts, 1)
        service.callback?(entry("first"))
        subject.togglePin(subject.items[0].id)
        subject.suspend(true)
        service.callback?(entry("locked"))
        XCTAssertEqual(subject.items.count, 1); XCTAssertFalse(subject.copy())
        subject.suspend(false)
        XCTAssertEqual(service.starts, 2)
        subject.setEnabled(false)
        service.callback?(entry("late callback"))
        XCTAssertTrue(subject.items.isEmpty); XCTAssertFalse(subject.copy())
    }
    @MainActor func testDedupSearchPinSelectionAndCopyFailure() throws {
        let service = ClipboardStub(), model = ClipboardViewModel(service: service)
        model.setEnabled(true)
        model.receive(entry("Alpha"))
        let alpha = try XCTUnwrap(model.items.first)
        model.togglePin(alpha.id)
        model.receive(entry("Beta")); model.receive(entry("Alpha"))
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.items[0].id, alpha.id); XCTAssertTrue(model.items[0].pinned)
        model.receive(entry("Gamma")); model.prepareToShow()
        XCTAssertEqual(model.selectedID, alpha.id)
        model.moveSelection(by: 1)
        XCTAssertTrue(model.copy()); XCTAssertEqual(service.writes.last?.title, "Gamma")
        model.query = "bETA"
        XCTAssertEqual(model.filteredItems.map(\.title), ["Beta"])
        XCTAssertTrue(model.copy()); XCTAssertEqual(service.writes.last?.title, "Beta")
        XCTAssertFalse(model.copy(UUID()), "A stale row must never copy a different item")
        service.writeSucceeds = false
        XCTAssertFalse(model.copy()); XCTAssertNotNil(model.error)
        model.remove(alpha.id); XCTAssertFalse(model.items.contains { $0.id == alpha.id })
        model.clear(); XCTAssertTrue(model.items.isEmpty); XCTAssertNil(model.error)
        XCTAssertEqual(service.starts, 2, "Clear invalidates pending capture before resuming")
    }
    @MainActor func testCountAndByteLimitsPreservePinnedItems() throws {
        let model = ClipboardViewModel(service: ClipboardStub())
        model.setEnabled(true); model.receive(entry("keep"))
        let pinned = try XCTUnwrap(model.items.first?.id)
        model.togglePin(pinned)
        for index in 0..<70 { model.receive(entry("item \(index)")) }
        XCTAssertEqual(model.items.count, 50); XCTAssertTrue(model.items.contains { $0.id == pinned })
        XCTAssertFalse(model.items.contains { $0.title == "item 0" })
        model.clear()
        for index in 0..<7 {
            let data = Data(repeating: UInt8(index), count: ClipboardService.maximumEntryBytes)
            model.receive(ClipboardEntry(contents: [[NSPasteboard.PasteboardType.html.rawValue: data]]))
            if let id = model.items.first?.id { model.togglePin(id) }
        }
        XCTAssertEqual(model.items.count, 4)
        XCTAssertEqual(model.items.reduce(0) { $0 + $1.byteCount }, ClipboardViewModel.maximumBytes)
        model.receive(entry(String(repeating: "x", count: ClipboardService.maximumEntryBytes + 1)))
        XCTAssertEqual(model.items.count, 4)
    }
    @MainActor func testExcludedPasteboardTypesAndOversizePayloadAreSkipped() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        // NSPasteboardItem can only write modern UTI names; the legacy marker remains read-only.
        for marker in ClipboardService.ignoredTypes where !marker.contains(" ") {
            board.clearContents()
            let item = NSPasteboardItem()
            item.setString("secret", forType: .string); item.setString("", forType: .init(marker))
            XCTAssertTrue(board.writeObjects([item]))
            XCTAssertNil(ClipboardService.readContents(from: board), marker)
        }
        board.clearContents(); board.setString(" \n ", forType: .string)
        XCTAssertNil(ClipboardService.readContents(from: board))
        board.clearContents()
        board.setData(Data(repeating: 65, count: ClipboardService.maximumEntryBytes + 1), forType: .string)
        XCTAssertNil(ClipboardService.readContents(from: board))
    }
    @MainActor func testRichTextAndMultipleFilesRoundTripWithoutRecapture() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let rich = NSPasteboardItem()
        rich.setString("hello", forType: .string); rich.setString("<b>hello</b>", forType: .html)
        board.clearContents(); XCTAssertTrue(board.writeObjects([rich]))
        let captured = ClipboardEntry(contents: try XCTUnwrap(ClipboardService.readContents(from: board)))
        XCTAssertEqual(captured.title, "hello")
        let service = ClipboardService(pasteboard: board)
        XCTAssertTrue(service.write(captured))
        XCTAssertEqual(board.string(forType: .html), "<b>hello</b>")
        XCTAssertNil(ClipboardService.readContents(from: board), "Our own copy-back must not enter history")
        let urls = [URL(fileURLWithPath: "/tmp/one.txt"), URL(fileURLWithPath: "/tmp/two.png")]
        board.clearContents(); XCTAssertTrue(board.writeObjects(urls.map { $0 as NSURL }))
        let files = ClipboardEntry(contents: try XCTUnwrap(ClipboardService.readContents(from: board)))
        XCTAssertEqual(files.kind, .files); XCTAssertEqual(files.title, "2 files")
        XCTAssertTrue(service.write(files))
        XCTAssertEqual(board.pasteboardItems?.count, 2)
        XCTAssertEqual(board.pasteboardItems?.compactMap { $0.string(forType: .fileURL) }, urls.map(\.absoluteString))
    }
    @MainActor func testImageThumbnailIsDownsampledAndPayloadPreserved() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 256,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let image = ClipboardEntry(contents: [[NSPasteboard.PasteboardType.png.rawValue: data]])
        XCTAssertEqual(image.kind, .image)
        let thumbnail = try XCTUnwrap(image.thumbnail?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertLessThanOrEqual(thumbnail.width, 96); XCTAssertLessThanOrEqual(thumbnail.height, 96)
        XCTAssertEqual(image.contents[0][NSPasteboard.PasteboardType.png.rawValue], data)
    }
    @MainActor func testMonitorSkipsExistingUnchangedSuspendedAndPendingCopies() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("before opt-in", forType: .string)
        let service = ClipboardService(pasteboard: board)
        var captured: [ClipboardEntry] = []
        service.start { captured.append($0) }
        defer { service.stop() }
        XCTAssertTrue(service.isMonitoring)
        for _ in 0..<1_000 { service.poll() }
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(captured.isEmpty)
        board.clearContents(); board.setString("new", forType: .string)
        service.poll()
        for _ in 0..<50 {
            if !captured.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(captured.map(\.title), ["new"])
        board.clearContents(); board.setString("pending", forType: .string)
        service.poll(); service.stop()
        XCTAssertFalse(service.isMonitoring)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(captured.count, 1)
        board.clearContents(); board.setString("while disabled", forType: .string)
        service.start { captured.append($0) }; service.poll()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(captured.count, 1)
    }
}
