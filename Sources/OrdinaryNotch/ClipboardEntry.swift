import AppKit
import CryptoKit
import ImageIO

struct ClipboardEntry: Identifiable {
    enum Kind { case text, image, files }
    let id = UUID()
    let contents: [[String: Data]]
    let fingerprint: String
    let title: String
    let searchText: String
    let kind: Kind
    let thumbnail: NSImage?
    let byteCount: Int
    var pinned = false

    init(contents: [[String: Data]]) {
        self.contents = contents
        byteCount = contents.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
        var hash = SHA256()
        for item in contents {
            for key in item.keys.sorted() {
                let data = item[key]!
                hash.update(data: Data("\(key.utf8.count):\(key):\(data.count):".utf8))
                hash.update(data: data)
            }
            hash.update(data: Data([0]))
        }
        fingerprint = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let text = contents.compactMap { item in
            (item[NSPasteboard.PasteboardType.string.rawValue] ?? item[NSPasteboard.PasteboardType.URL.rawValue])
                .flatMap { String(data: $0, encoding: .utf8) }
        }.joined(separator: "\n")
        let files = contents.compactMap { $0[NSPasteboard.PasteboardType.fileURL.rawValue] }
            .compactMap { String(data: $0, encoding: .utf8).flatMap(URL.init(string:)) }
        let imageData = contents.lazy.compactMap { $0[NSPasteboard.PasteboardType.png.rawValue] ?? $0[NSPasteboard.PasteboardType.tiff.rawValue] }.first
        if !files.isEmpty {
            kind = .files
            title = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
            searchText = files.map(\.lastPathComponent).joined(separator: " ")
        } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kind = .text
            title = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
            searchText = String(text.prefix(8_000))
        } else if imageData != nil {
            kind = .image; title = "Copied image"; searchText = title
        } else {
            kind = .text; title = "Formatted text"; searchText = title
        }
        if let imageData, let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96
           ] as CFDictionary) {
            thumbnail = NSImage(cgImage: image, size: .zero)
        } else { thumbnail = nil }
    }
}
