import SwiftUI

/// Runtime display presentation, selected from hardware unless overridden in Developer mode.
enum NotchStyle: String, CaseIterable { case notch, island }

/// Measurements informed by Boring Notch's published sizing defaults.
/// Geometry is constructed locally with circular, tangent-continuous shoulders.
enum NotchGeometry {
    static let expandedSize = CGSize(width: 640, height: 166)
    static let islandExpandedWidth: CGFloat = 560
    static let islandIdleWidth: CGFloat = 160
    static let islandCompactHeight: CGFloat = 36
    static let islandCenterWidth: CGFloat = 80
    static let islandTopInset: CGFloat = 8
    static let islandSeparation: CGFloat = 8
    static let canvasMargin: CGFloat = 24
    static let compactShoulder: CGFloat = 6
    static let compactBottomRadius: CGFloat = 14
    static let compactContentInset: CGFloat = 6
    static let compactMediaSize: CGFloat = 20
    static let compactOuterPadding = compactShoulder + compactContentInset
    static let expandedShoulder: CGFloat = 19
    static let expandedBottomRadius: CGFloat = 24
    static let expandedContentPadding: CGFloat = 31
    static let tabCornerRadius: CGFloat = 13
    static let detailHeadingHeight: CGFloat = 20
    static let detailIconSize: CGFloat = 14
    static let detailHeadingGap: CGFloat = 6
    static let detailContentGap: CGFloat = 6
    static let detailSidebarWidth: CGFloat = 200
    static let alertWidth: CGFloat = 400
    static let alertContentHeight: CGFloat = 44

    static func insetRadius(_ radius: CGFloat, padding: CGFloat) -> CGFloat {
        max(0, radius - max(0, padding))
    }
    static let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    static let closeSpring = Animation.spring(response: 0.45, dampingFraction: 1, blendDuration: 0)

    static func compactWidth(hardwareWidth: CGFloat, wingWidth: CGFloat) -> CGFloat {
        // Idle fits the physical cutout. Active wings share the inset used by the artwork.
        hardwareWidth + (wingWidth > 0 ? 2 * (wingWidth + compactOuterPadding) : 0)
    }
    static func pixelAlignedSize(_ size: CGSize, scale: CGFloat) -> CGSize {
        let scale = max(1, scale)
        return CGSize(width: ceil(size.width * scale) / scale, height: ceil(size.height * scale) / scale)
    }
    static func frame(size: CGSize, in screen: CGRect) -> CGRect {
        CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height, width: size.width, height: size.height)
    }
}

/// The top edge flares outward to meet the menu bar; the lower corners turn inward.
/// Both radii interpolate with the same transaction as the surface dimensions.
struct NotchSilhouette: Shape {
    var shoulder: CGFloat
    var bottom: CGFloat
    var island = false
    var detachedWidth: CGFloat = 0
    var detachedGap: CGFloat = 0
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(shoulder, bottom), AnimatablePair(detachedWidth, detachedGap)) }
        set {
            shoulder = newValue.first.first; bottom = newValue.first.second
            detachedWidth = newValue.second.first; detachedGap = newValue.second.second
        }
    }
    func path(in rect: CGRect) -> Path {
        if island {
            let offWidth = min(max(0, detachedWidth), rect.width)
            let gap = offWidth > 0 ? max(0, detachedGap) : 0
            let main = CGRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - offWidth - gap), height: rect.height)
            var result = RoundedRectangle(cornerRadius: min(rect.height / 2, 24), style: .continuous).path(in: main)
            if offWidth > 0 {
                let off = CGRect(x: main.maxX + gap, y: rect.minY, width: offWidth,
                                 height: min(rect.height, NotchGeometry.islandCompactHeight))
                result.addPath(Capsule().path(in: off))
            }
            return result
        }
        let top = min(max(0, shoulder), rect.height / 2, rect.width / 4)
        let lower = min(max(0, bottom), rect.height - top, (rect.width - 2 * top) / 2)
        let left = rect.minX + top
        let right = rect.maxX - top
        let y = rect.minY
        let base = rect.maxY
        // Cubic approximation of quarter-circles; all joins share their tangents.
        let k: CGFloat = 0.5522847498
        var result = Path()
        result.move(to: CGPoint(x: rect.minX, y: y))
        result.addLine(to: CGPoint(x: rect.maxX, y: y))
        result.addCurve(to: CGPoint(x: right, y: y + top),
                        control1: CGPoint(x: rect.maxX - k * top, y: y),
                        control2: CGPoint(x: right, y: y + (1 - k) * top))
        result.addLine(to: CGPoint(x: right, y: base - lower))
        result.addCurve(to: CGPoint(x: right - lower, y: base),
                        control1: CGPoint(x: right, y: base - lower + k * lower),
                        control2: CGPoint(x: right - lower + k * lower, y: base))
        result.addLine(to: CGPoint(x: left + lower, y: base))
        result.addCurve(to: CGPoint(x: left, y: base - lower),
                        control1: CGPoint(x: left + lower - k * lower, y: base),
                        control2: CGPoint(x: left, y: base - lower + k * lower))
        result.addLine(to: CGPoint(x: left, y: y + top))
        result.addCurve(to: CGPoint(x: rect.minX, y: y),
                        control1: CGPoint(x: left, y: y + (1 - k) * top),
                        control2: CGPoint(x: rect.minX + k * top, y: y))
        result.closeSubpath()
        return result
    }
}
