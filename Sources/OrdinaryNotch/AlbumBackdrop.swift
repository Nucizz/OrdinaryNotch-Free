import AppKit
import CoreImage

/// Prepare a tiny, blurred texture once per cover change, never on playback ticks.
enum AlbumBackdrop {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func make(from image: NSImage?) -> NSImage? {
        guard let image,
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bitmap = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                                     bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        bitmap.interpolationQuality = .medium
        bitmap.draw(source, in: bounds)
        guard let thumbnail = bitmap.makeImage() else { return nil }
        let blurred = CIImage(cgImage: thumbnail).clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 9])
        guard let result = context.createCGImage(blurred, from: bounds) else { return nil }
        return NSImage(cgImage: result, size: bounds.size)
    }
}
