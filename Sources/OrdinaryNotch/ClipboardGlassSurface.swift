import AppKit

/// Clipboard uses the shared native floating surface with its compact corner radius.
enum ClipboardGlassSurface {
    static let cornerRadius: CGFloat = 16
    @MainActor static func make(content: NSView) -> NSView {
        NativeGlassSurface.make(content: content, cornerRadius: cornerRadius)
    }
}
