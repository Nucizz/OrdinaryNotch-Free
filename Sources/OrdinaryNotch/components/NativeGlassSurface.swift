import AppKit

/// Shared native surface for floating panels, with the system's accessibility behavior.
enum NativeGlassSurface {
    @MainActor static func make(content: NSView, cornerRadius: CGFloat) -> NSView {
        let surface: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            surface = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = cornerRadius
            material.layer?.cornerCurve = .continuous
            material.layer?.masksToBounds = true
            material.addSubview(content)
            surface = material
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            content.topAnchor.constraint(equalTo: surface.topAnchor),
            content.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        return surface
    }
}
