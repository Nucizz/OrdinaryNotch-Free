import AppKit
import QuartzCore
import SwiftUI

/// A small playback indicator. Core Animation drives the bars without per-frame
/// SwiftUI layout.
struct Waveform: View {
    let active: Bool
    let visible: Bool
    var colors: [NSColor] = [.white, .white]
    var reduceMotionOverride = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WaveformLayers(active: active, moving: active && visible && !reduceMotion && !reduceMotionOverride,
                       colors: colors, smoothTransitions: visible && !reduceMotion && !reduceMotionOverride)
            .frame(width: 20, height: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(active ? "Music playing" : "Music paused")
    }
}

struct WaveformLayers: NSViewRepresentable {
    let active: Bool
    let moving: Bool
    let colors: [NSColor]
    var smoothTransitions = true

    func makeNSView(context: Context) -> BarsView { BarsView() }
    func updateNSView(_ view: BarsView, context: Context) { view.update(active: active, moving: moving, colors: colors, smoothTransitions: smoothTransitions) }
    static func dismantleNSView(_ view: BarsView, coordinator: ()) { view.stopAnimations() }

    final class BarsView: NSView {
        private let bars: [CALayer]
        private let gradient = CAGradientLayer()
        private var lastActive: Bool?
        private var lastMoving: Bool?
        private var lastColors: [NSColor]?
        override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 12) }

        init() {
            bars = (0..<6).map { _ in CALayer() }
            super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 12))
            wantsLayer = true
            gradient.startPoint = CGPoint(x: 0, y: 1)
            gradient.endPoint = CGPoint(x: 1, y: 0)
            let mask = CALayer()
            mask.frame = bounds
            gradient.mask = mask
            layer = gradient
            for (index, bar) in bars.enumerated() {
                bar.bounds = CGRect(x: 0, y: 0, width: 2, height: 3)
                bar.position = CGPoint(x: 2.5 + 3 * Double(index), y: 6)
                // Animate height instead of scaling so the round ends stay circular.
                bar.cornerRadius = 1
                bar.backgroundColor = NSColor.white.cgColor
                mask.addSublayer(bar)
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func update(active: Bool, moving: Bool, colors: [NSColor], smoothTransitions: Bool = true) {
            // Model ticks and metadata refreshes must not restart the animation.
            guard active != lastActive || moving != lastMoving || colors != lastColors else { return }
            let hadState = lastMoving != nil
            lastColors = colors
            lastActive = active
            let motionChanged = moving != lastMoving
            lastMoving = moving
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let previousColors = (gradient.presentation() as? CAGradientLayer)?.colors ?? gradient.colors
            let previousOpacity = gradient.presentation()?.opacity ?? gradient.opacity
            gradient.colors = (colors.count >= 2 ? colors : [.white, .white]).map(\.cgColor)
            gradient.opacity = active ? 0.9 : 0.35
            if smoothTransitions && hadState {
                let fade = CABasicAnimation(keyPath: "colors")
                fade.fromValue = previousColors
                fade.toValue = gradient.colors
                fade.duration = 0.3
                gradient.add(fade, forKey: "colors")
                let dim = CABasicAnimation(keyPath: "opacity")
                dim.fromValue = previousOpacity
                dim.toValue = gradient.opacity
                dim.duration = 0.3
                gradient.add(dim, forKey: "opacity")
            }
            CATransaction.commit()
            guard motionChanged else { return }
            for (index, bar) in bars.enumerated() {
                let currentHeight = bar.presentation()?.bounds.height ?? bar.bounds.height
                bar.removeAnimation(forKey: "playback")
                bar.removeAnimation(forKey: "settle")
                bar.removeAnimation(forKey: "resume")
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                bar.bounds.size.height = 3
                CATransaction.commit()
                if moving {
                    let motion = CAKeyframeAnimation(keyPath: "bounds.size.height")
                    let peaks: [[NSNumber]] = [
                        [0.25, 0.65, 0.35, 0.80, 0.25],
                        [0.25, 0.90, 0.50, 0.65, 0.25],
                        [0.25, 0.55, 1.00, 0.45, 0.25],
                        [0.25, 0.80, 0.30, 0.60, 0.25],
                        [0.25, 0.45, 0.85, 0.55, 0.25],
                        [0.25, 0.70, 0.40, 0.90, 0.25]
                    ]
                    motion.values = peaks[index].map { $0.doubleValue * 12 }
                    motion.keyTimes = [0, 0.25, 0.5, 0.75, 1]
                    motion.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
                    motion.duration = [1.10, 0.95, 1.25, 1.05, 0.85, 0.75][index]
                    motion.repeatCount = .infinity
                    bar.add(motion, forKey: "playback")
                    if smoothTransitions && hadState {
                        let resume = CABasicAnimation(keyPath: "bounds.size.height")
                        resume.isAdditive = true
                        resume.fromValue = currentHeight - 3
                        resume.toValue = 0
                        resume.duration = 0.3
                        resume.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        bar.add(resume, forKey: "resume")
                    }
                } else if smoothTransitions && hadState {
                    let settle = CABasicAnimation(keyPath: "bounds.size.height")
                    settle.fromValue = currentHeight
                    settle.toValue = 3
                    settle.duration = 0.3
                    settle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    bar.add(settle, forKey: "settle")
                }
            }
        }
        func stopAnimations() { gradient.removeAllAnimations(); bars.forEach { $0.removeAllAnimations() } }
    }
}
