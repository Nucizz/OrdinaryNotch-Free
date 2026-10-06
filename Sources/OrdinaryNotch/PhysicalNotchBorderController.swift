import AppKit

/// Diagnostic bounds from NSScreen, independent of the app's animated surface.
enum PhysicalNotchBounds {
    static func cutout(screen: CGRect, safeAreaTop: CGFloat, left: CGRect?, right: CGRect?) -> CGRect? {
        guard safeAreaTop > 0, safeAreaTop < screen.height,
              let left, let right, right.minX > left.maxX,
              left.maxX > screen.minX, right.minX < screen.maxX else { return nil }
        // Auxiliary areas use global screen coordinates, including on secondary displays.
        return CGRect(x: left.maxX, y: screen.maxY - safeAreaTop,
                      width: right.minX - left.maxX, height: safeAreaTop)
    }
}

@MainActor
final class PhysicalNotchBorderController {
    private(set) var panel: NSPanel?

    func update(screen: NSScreen?, settings: NotchSettings, canPresent: Bool) {
        let bounds = screen.flatMap {
            PhysicalNotchBounds.cutout(screen: $0.frame, safeAreaTop: $0.safeAreaInsets.top,
                                      left: $0.auxiliaryTopLeftArea, right: $0.auxiliaryTopRightArea)
        }
        update(cutout: bounds, enabled: settings.showDeveloperMenu && settings.highlightPhysicalNotch && canPresent)
    }

    func update(cutout: CGRect?, enabled: Bool) {
        guard enabled, let cutout else { hide(); return }
        // Put all of the two-point border on drawable pixels outside the cutout.
        let frame = CGRect(x: cutout.minX - 2, y: cutout.minY - 2,
                           width: cutout.width + 4, height: cutout.height + 2)
        if panel == nil {
            let window = PhysicalNotchBorderPanel(contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.isMovable = false
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .stationary]
            window.contentView = PhysicalNotchBorderView(frame: CGRect(origin: .zero, size: frame.size))
            panel = window
        }
        guard let panel else { return }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() { panel?.orderOut(nil) }
}

private final class PhysicalNotchBorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// NSScreen supplies the bounding rectangle, not a hardware mask. Fit the lower
/// corner radius to the cutout height so it scales with the display's resolution.
enum PhysicalNotchOutline {
    static func path(in bounds: CGRect, lineWidth: CGFloat = 2) -> NSBezierPath {
        let inset = lineWidth / 2
        let left = bounds.minX + inset, right = bounds.maxX - inset
        let bottom = bounds.minY + inset
        let hardwareHeight = max(0, bounds.height - lineWidth)
        // Offset the centerline outside the estimated hardware curve, matching
        // the straight sides and bottom rather than rounding the stroke's joins.
        let radius = min(hardwareHeight / 4 + inset, (right - left) / 2, bounds.height - inset)
        let k: CGFloat = 0.5522847498
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: left, y: bounds.maxY))
        outline.line(to: NSPoint(x: left, y: bottom + radius))
        outline.curve(to: NSPoint(x: left + radius, y: bottom),
                      controlPoint1: NSPoint(x: left, y: bottom + radius * (1 - k)),
                      controlPoint2: NSPoint(x: left + radius * (1 - k), y: bottom))
        outline.line(to: NSPoint(x: right - radius, y: bottom))
        outline.curve(to: NSPoint(x: right, y: bottom + radius),
                      controlPoint1: NSPoint(x: right - radius * (1 - k), y: bottom),
                      controlPoint2: NSPoint(x: right, y: bottom + radius * (1 - k)))
        outline.line(to: NSPoint(x: right, y: bounds.maxY))
        // The top stays open where the cutout meets the bezel.
        outline.lineWidth = lineWidth
        outline.lineCapStyle = .butt
        return outline
    }
}

private final class PhysicalNotchBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.cyan.setStroke()
        PhysicalNotchOutline.path(in: bounds).stroke()
    }
}
