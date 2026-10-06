import AppKit
import QuickLookThumbnailing

final class FileThumbnailRequest {
    private var cancellation: (() -> Void)?
    init(cancel: @escaping () -> Void) { cancellation = cancel }
    func cancel() { cancellation?(); cancellation = nil }
    deinit { cancellation?() }
}

@MainActor
protocol FileThumbnailServing {
    func request(for url: URL, completion: @escaping @MainActor (NSImage?) -> Void) -> FileThumbnailRequest
}

@MainActor
final class FileThumbnailService: FileThumbnailServing {
    func request(for url: URL, completion: @escaping @MainActor (NSImage?) -> Void) -> FileThumbnailRequest {
        let generator = QLThumbnailGenerator.shared
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 44),
                                                  scale: 2, representationTypes: .thumbnail)
        request.iconMode = false
        generator.generateBestRepresentation(for: request) { representation, _ in
            let image = representation?.nsImage
            Task { @MainActor in completion(image) }
        }
        return FileThumbnailRequest { generator.cancel(request) }
    }
}
