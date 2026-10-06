import AppKit
import XCTest
@testable import OrdinaryNotch

final class FileShelfTests: XCTestCase {
    @MainActor func testThumbnailLoadsOnceAndUnavailablePreviewKeepsFileIcon() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Preview fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let thumbnails = ShelfThumbnailFixture()
        let model = FileShelfViewModel(thumbnails: thumbnails)
        model.add([file, file])
        let item = try XCTUnwrap(model.items.first)
        XCTAssertNil(item.thumbnail)
        XCTAssertEqual(thumbnails.completions.count, 1, "Duplicate drops reuse the same preview request")
        let icon = item.icon
        let preview = NSImage(size: NSSize(width: 64, height: 44))
        thumbnails.completions[0](preview)
        XCTAssertTrue(item.thumbnail === preview)
        XCTAssertTrue(item.icon === icon)
        model.clear()
        model.add([file])
        thumbnails.completions[1](nil)
        XCTAssertNil(model.items.first?.thumbnail)
        XCTAssertNotNil(model.items.first?.icon)
        XCTAssertNil(model.error, "Missing thumbnails must not turn valid files into errors")
    }

    @MainActor func testRemovingAndReaddingFileRejectsOldThumbnailCompletion() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Preview fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let thumbnails = ShelfThumbnailFixture()
        let model = FileShelfViewModel(thumbnails: thumbnails)
        model.add([file])
        let oldItem = try XCTUnwrap(model.items.first)
        model.remove(oldItem)
        XCTAssertEqual(thumbnails.cancelled, [0])
        model.add([file])
        thumbnails.completions[0](NSImage(size: NSSize(width: 64, height: 44)))
        XCTAssertNil(model.items.first?.thumbnail, "A stale result cannot overwrite a newly dropped copy")
        XCTAssertNil(oldItem.thumbnail)
        model.clear()
        XCTAssertEqual(thumbnails.cancelled, [0, 1])
        thumbnails.completions[1](NSImage(size: NSSize(width: 64, height: 44)))
        XCTAssertTrue(model.items.isEmpty)
    }

    @MainActor func testQuickLookGeneratesAnActualImageThumbnail() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        let source = NSImage(size: NSSize(width: 160, height: 90), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(source.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
        let completed = expectation(description: "Quick Look thumbnail")
        var result: NSImage?
        let request = FileThumbnailService().request(for: file) { image in
            result = image
            completed.fulfill()
        }
        defer { request.cancel() }
        await fulfillment(of: [completed], timeout: 15)
        let thumbnail = try XCTUnwrap(result)
        XCTAssertGreaterThan(thumbnail.size.width, 0)
        XCTAssertGreaterThan(thumbnail.size.height, 0)
    }
    @MainActor func testShelfDeduplicatesFilesAndNeverDeletesOriginals() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sample.txt")
        try Data("Keep me".utf8).write(to: file)
        let model = FileShelfViewModel()
        XCTAssertTrue(model.add([file, directory, file]))
        XCTAssertEqual(model.items.map(\.id), [file.standardizedFileURL, directory.standardizedFileURL])
        model.remove(try XCTUnwrap(model.items.first))
        XCTAssertEqual(model.items.count, 1)
        model.clear()
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(try String(contentsOf: file), "Keep me")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor func testShelfRejectsRemoteAndMissingFiles() {
        let model = FileShelfViewModel()
        XCTAssertFalse(model.add([URL(string: "https://example.com/file.txt")!,
                                  URL(fileURLWithPath: "/private/tmp/\(UUID().uuidString)/missing.txt")]))
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNotNil(model.error)
        model.clear()
        XCTAssertNil(model.error)
    }
}

@MainActor
private final class ShelfThumbnailFixture: FileThumbnailServing {
    var completions: [@MainActor (NSImage?) -> Void] = []
    var cancelled: [Int] = []
    func request(for url: URL, completion: @escaping @MainActor (NSImage?) -> Void) -> FileThumbnailRequest {
        let index = completions.count
        completions.append(completion)
        return FileThumbnailRequest { [weak self] in self?.cancelled.append(index) }
    }
}
