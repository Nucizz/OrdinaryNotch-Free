import SwiftUI

/// Native Liquid Glass on macOS 26+, with an accessible material fallback.
struct SettingsGlassSurface: NSViewRepresentable {
    var cornerRadius: CGFloat = SettingsStyle.controlRadius
    var capsule = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) {
        view.configure(opaque: reduceTransparency || contrast == .increased, radius: cornerRadius, capsule: capsule)
    }
    final class Surface: NSView {
        private var effect: NSView?
        private var usesOpaqueSurface: Bool?
        private var requestedRadius: CGFloat = 0
        private var capsule = false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func configure(opaque: Bool, radius: CGFloat, capsule: Bool = false) {
            wantsLayer = true
            requestedRadius = radius; self.capsule = capsule
            // Let the native glass draw its edge lighting beyond the content bounds.
            layer?.masksToBounds = false
            if self.usesOpaqueSurface != opaque {
                effect?.removeFromSuperview(); effect = nil
                self.usesOpaqueSurface = opaque
                if !opaque {
                    if #available(macOS 26, *) {
                        let glass = NSGlassEffectView(frame: bounds)
                        glass.contentView = NSView(frame: bounds)
                        effect = glass
                    } else {
                        let material = NSVisualEffectView(frame: bounds)
                        material.material = .sidebar; material.blendingMode = .behindWindow
                        material.state = .followsWindowActiveState
                        effect = material
                    }
                    if let effect {
                        effect.autoresizingMask = [.width, .height]
                        addSubview(effect)
                    }
                }
            }
            updateAppearance()
            updateShape()
        }
        override func layout() {
            super.layout()
            updateShape()
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateAppearance()
        }
        private func updateAppearance() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = usesOpaqueSurface == true ? NSColor.controlBackgroundColor.cgColor : NSColor.clear.cgColor
            }
        }
        private func updateShape() {
            let radius = capsule ? min(bounds.width, bounds.height) / 2 : requestedRadius
            layer?.cornerRadius = radius
            layer?.cornerCurve = .continuous
            if #available(macOS 26, *), let glass = effect as? NSGlassEffectView {
                glass.cornerRadius = radius
            } else {
                effect?.wantsLayer = true
                effect?.layer?.cornerRadius = radius
                effect?.layer?.cornerCurve = .continuous
                effect?.layer?.masksToBounds = true
            }
        }
    }
}
