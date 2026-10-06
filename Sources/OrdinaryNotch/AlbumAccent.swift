import AppKit

/// Small, one-time sample when artwork changes. No work runs on animation frames.
enum AlbumAccent {
    static func extract(from image: NSImage?) -> NSColor { palette(from: image)[0] }

    /// Two distinct cover colors, lifted for legibility against the black notch.
    static func palette(from image: NSImage?) -> [NSColor] {
        guard let image, let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [.white, .white] }
        let width = 32, height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [.white, .white] }
        struct Bucket { var weight = 0.0; var r = 0.0; var g = 0.0; var b = 0.0 }
        var buckets: [Int: Bucket] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = min(1, Double(pixels[index]) / 255 / alpha)
            let g = min(1, Double(pixels[index + 1]) / 255 / alpha)
            let b = min(1, Double(pixels[index + 2]) / 255 / alpha)
            let high = max(r, g, b), low = min(r, g, b)
            guard high > 0.12 else { continue }
            let saturation = (high - low) / high
            let weight = 0.15 + saturation
            let key = Int(r * 7) * 64 + Int(g * 7) * 8 + Int(b * 7)
            var bucket = buckets[key, default: Bucket()]
            bucket.weight += weight; bucket.r += r * weight; bucket.g += g * weight; bucket.b += b * weight
            buckets[key] = bucket
        }
        let ranked = buckets.sorted {
            $0.value.weight == $1.value.weight ? $0.key < $1.key : $0.value.weight > $1.value.weight
        }.map(\.value)
        guard let chosen = ranked.first else { return [.white, .white] }
        func sample(_ bucket: Bucket) -> NSColor {
            NSColor(srgbRed: bucket.r / bucket.weight, green: bucket.g / bucket.weight,
                    blue: bucket.b / bucket.weight, alpha: 1)
        }
        let primary = sample(chosen)
        let secondary = ranked.dropFirst().first { bucket in
            guard bucket.weight >= chosen.weight * 0.1 else { return false }
            let color = sample(bucket)
            let distance = pow(color.redComponent - primary.redComponent, 2)
                + pow(color.greenComponent - primary.greenComponent, 2)
                + pow(color.blueComponent - primary.blueComponent, 2)
            return distance > 0.12
        }
        let first = readable(primary)
        let last = secondary.map { readable(sample($0)) }
            ?? first.blended(withFraction: 0.3, of: .white) ?? first
        return [first, last]
    }

    private static func readable(_ color: NSColor) -> NSColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if saturation < 0.08 { return NSColor(white: max(0.75, brightness), alpha: 1) }
        return NSColor(hue: hue, saturation: min(0.72, saturation), brightness: max(0.78, brightness), alpha: 1)
    }
}
