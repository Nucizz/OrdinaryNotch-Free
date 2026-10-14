import SwiftUI

struct MediaSeekBar: NSViewRepresentable {
    @ObservedObject var music: MusicViewModel
    func makeNSView(context: Context) -> MediaProgressSlider {
        let slider = MediaProgressSlider()
        slider.cell = MediaProgressCell()
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.editingChanged = { editing in
            if editing { music.beginSeeking() } else { music.finishSeeking() }
        }
        slider.setAccessibilityLabel("Playback position")
        return slider
    }
    func updateNSView(_ slider: MediaProgressSlider, context: Context) {
        slider.minValue = 0; slider.maxValue = music.seekDuration
        slider.doubleValue = music.displayedPosition
        slider.isEnabled = music.canSeek
        (slider.cell as? MediaProgressCell)?.accent = music.accent
        slider.needsDisplay = true
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MediaProgressSlider, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 160, height: 12)
    }
    func makeCoordinator() -> Coordinator { Coordinator(music: music) }
    @MainActor final class Coordinator: NSObject {
        let music: MusicViewModel
        init(music: MusicViewModel) { self.music = music }
        @objc func changed(_ sender: MediaProgressSlider) {
            music.previewSeek(to: sender.doubleValue)
            if !sender.isDragging { music.finishSeeking() }
        }
    }
}

final class MediaProgressSlider: NSSlider {
    var isDragging = false
    var editingChanged: (Bool) -> Void = { _ in }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isDragging = true; editingChanged(true); needsDisplay = true
        defer { isDragging = false; editingChanged(false); needsDisplay = true }
        super.mouseDown(with: event)
    }
}

final class MediaProgressCell: NSSliderCell {
    var accent = NSColor.white
    private var fraction: Double {
        guard maxValue > minValue else { return 0 }
        return min(1, max(0, (doubleValue - minValue) / (maxValue - minValue)))
    }
    override func barRect(flipped: Bool) -> NSRect {
        let bounds = controlView?.bounds ?? .zero
        return NSRect(x: bounds.minX + 5, y: bounds.midY - 2, width: max(0, bounds.width - 10), height: 4)
    }
    override func knobRect(flipped: Bool) -> NSRect {
        let track = barRect(flipped: flipped)
        return NSRect(x: track.minX + track.width * fraction - 5, y: track.midY - 5, width: 10, height: 10)
    }
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = barRect(flipped: flipped)
        NSColor.white.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: 4), xRadius: 2, yRadius: 2).fill()
    }
    override func drawKnob(_ rect: NSRect) {
        guard (controlView as? MediaProgressSlider)?.isDragging == true else { return }
        accent.setFill()
        NSBezierPath(ovalIn: knobRect(flipped: controlView?.isFlipped ?? false)).fill()
    }
}
