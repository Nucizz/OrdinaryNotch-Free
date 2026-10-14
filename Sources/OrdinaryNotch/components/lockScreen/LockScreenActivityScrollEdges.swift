import AppKit
import SwiftUI

struct LockScreenActivityScrollOverflow: Equatable {
    var top = false
    var bottom = false
}

/// Fade the viewport into the clock/login margins, with native blur confined to
/// the edges. No duplicate activity views or private Core Animation filters.
struct LockScreenActivityScrollEdges: ViewModifier {
    // Older systems retain both soft boundaries; modern macOS tracks which
    // boundaries actually have more content beyond them.
    @State private var overflow = LockScreenActivityScrollOverflow(top: true, bottom: true)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let height = min(LockScreenActivityLayout.scrollEdgeHeight, geometry.size.height / 4)
            trackScrolling(content)
                .overlay(alignment: .top) { if overflow.top { edge(top: true, height: height) } }
                .overlay(alignment: .bottom) { if overflow.bottom { edge(top: false, height: height) } }
                .mask {
                    if reduceTransparency {
                        Rectangle()
                    } else {
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: overflow.top ? height : 0)
                            Rectangle()
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: overflow.bottom ? height : 0)
                        }
                    }
                }
        }
    }

    @ViewBuilder private func trackScrolling(_ content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: LockScreenActivityScrollOverflow.self) { geometry in
                LockScreenActivityScrollOverflow(top: geometry.visibleRect.minY > 1,
                    bottom: geometry.visibleRect.maxY < geometry.contentSize.height - 1)
            } action: { _, value in
                overflow = value
            }
        } else {
            content
        }
    }

    @ViewBuilder private func edge(top: Bool, height: CGFloat) -> some View {
        if !reduceTransparency {
            LockScreenEdgeBlur(top: top)
                .frame(height: height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct LockScreenEdgeBlur: NSViewRepresentable {
    let top: Bool

    func makeNSView(context: Context) -> Surface {
        Surface(top: top)
    }
    func updateNSView(_ nsView: Surface, context: Context) {}

    final class Surface: NSVisualEffectView {
        init(top: Bool) {
            super.init(frame: .zero)
            material = .hudWindow
            blendingMode = .withinWindow
            state = .active
            maskImage = Self.makeMask(top: top)
            setAccessibilityElement(false)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private static func makeMask(top: Bool) -> NSImage {
            // maskImage masks AppKit's material itself, including its backdrop.
            // Feather every exposed side so no rectangular strip remains visible.
            let inset = LockScreenActivityLayout.scrollEdgeHeight
            let image = NSImage(size: NSSize(width: inset * 2 + 1, height: inset), flipped: false) { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                let clear = CGColor(gray: 1, alpha: 0), white = CGColor(gray: 1, alpha: 1)
                guard let vertical = CGGradient(colorsSpace: nil, colors: (top ? [clear, white] : [white, clear]) as CFArray, locations: [0, 1]),
                      let horizontal = CGGradient(colorsSpace: nil, colors: [clear, white, white, clear] as CFArray,
                        locations: [0, inset / rect.width, 1 - inset / rect.width, 1]) else { return false }
                context.drawLinearGradient(vertical, start: .zero, end: CGPoint(x: 0, y: rect.height), options: [])
                context.setBlendMode(.destinationIn)
                context.drawLinearGradient(horizontal, start: .zero, end: CGPoint(x: rect.width, y: 0), options: [])
                return true
            }
            image.capInsets = NSEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
            image.resizingMode = .stretch
            return image
        }
    }
}
