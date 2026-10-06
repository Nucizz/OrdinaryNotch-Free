import AppKit
import SwiftUI

/// Scroll only the clipped text; the badge and its icon remain stationary.
struct MarqueeText: NSViewRepresentable {
    let text: String
    let color: NSColor
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.notchReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> MarqueeView { MarqueeView() }
    func updateNSView(_ view: MarqueeView, context: Context) {
        view.update(text: text, color: color, reduceMotion: reduceMotion || systemReduceMotion)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarqueeView, context: Context) -> CGSize? {
        CGSize(width: min(nsView.textWidth, max(0, proposal.width ?? nsView.textWidth)), height: 14)
    }
    static func dismantleNSView(_ view: MarqueeView, coordinator: ()) { view.textLayer.removeAllAnimations() }

    final class MarqueeView: NSView {
        let textLayer = CATextLayer()
        private let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        private var text = ""
        private var reduceMotion = false
        private var animationWidth: CGFloat = -1
        private(set) var textWidth: CGFloat = 0

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
            layer?.masksToBounds = true
            textLayer.anchorPoint = .zero
            layer?.addSublayer(textLayer)
            setAccessibilityElement(true)
            setAccessibilityRole(.staticText)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func update(text: String, color: NSColor, reduceMotion: Bool) {
            let changed = self.text != text || self.reduceMotion != reduceMotion
            self.text = text
            self.reduceMotion = reduceMotion
            let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            textWidth = ceil(attributed.size().width)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            textLayer.string = attributed
            CATransaction.commit()
            setAccessibilityLabel(text)
            if changed { animationWidth = -1 }
            needsLayout = true
            invalidateIntrinsicContentSize()
        }
        override var intrinsicContentSize: NSSize { NSSize(width: textWidth, height: 14) }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            animationWidth = -1
            needsLayout = true
        }
        override func layout() {
            super.layout()
            textLayer.contentsScale = window?.backingScaleFactor ?? 2
            guard animationWidth != bounds.width else { return }
            animationWidth = bounds.width
            textLayer.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            textLayer.frame = CGRect(x: 0, y: 0, width: reduceMotion ? bounds.width : textWidth, height: 14)
            textLayer.truncationMode = reduceMotion ? .end : .none
            CATransaction.commit()
            let overflow = textWidth - bounds.width
            guard overflow > 1, bounds.width > 0, !reduceMotion, window != nil else { return }
            let travel = max(1, Double(overflow) / 24)
            let duration = 2 * travel + 2.4
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.values = [0, 0, -overflow, -overflow, 0]
            animation.keyTimes = [0, NSNumber(value: 1.2 / duration),
                                  NSNumber(value: (1.2 + travel) / duration),
                                  NSNumber(value: (2.4 + travel) / duration), 1]
            animation.duration = duration
            animation.repeatCount = .infinity
            animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
            textLayer.add(animation, forKey: "marquee")
        }
    }
}
