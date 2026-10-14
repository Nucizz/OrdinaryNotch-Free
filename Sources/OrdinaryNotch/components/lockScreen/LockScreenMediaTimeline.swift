import SwiftUI

struct LockScreenMediaTimeline: View {
    var media: LockScreenActivityRow.Media
    var value: String
    var seek: (Double, MusicContentIdentity) -> Void
    @State private var preview: Double?

    var body: some View {
        VStack(spacing: 0) {
            if media.canSeek {
                LockScreenMediaSeekBar(media: media, preview: $preview, seek: seek)
                    .frame(height: 20)
            }
            HStack {
                Text(preview.map { ClockFormat.format($0.rounded(.down)) } ?? value)
                Spacer()
                Text(preview.map { "−" + ClockFormat.format(max(0, media.duration - $0).rounded(.down)) }
                     ?? media.remaining ?? "Live")
            }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/// Reuses the notch's thin slider and drag-only thumb. Send one seek on release, retaining the
/// original track identity so a mid-drag track change cannot seek its replacement.
struct LockScreenMediaSeekBar: NSViewRepresentable {
    var media: LockScreenActivityRow.Media
    @Binding var preview: Double?
    var seek: (Double, MusicContentIdentity) -> Void

    func makeNSView(context: Context) -> MediaProgressSlider {
        let slider = MediaProgressSlider()
        slider.cell = MediaProgressCell()
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.editingChanged = { [weak slider, weak coordinator = context.coordinator] editing in
            guard let slider, let coordinator else { return }
            if editing { coordinator.begin() } else { coordinator.finish(slider) }
        }
        slider.setAccessibilityLabel("Playback position")
        return slider
    }

    func updateNSView(_ slider: MediaProgressSlider, context: Context) {
        context.coordinator.parent = self
        slider.minValue = 0
        slider.maxValue = media.canSeek ? media.duration : 1
        slider.isEnabled = media.canSeek
        if !slider.isDragging {
            slider.doubleValue = media.position.isFinite ? min(slider.maxValue, max(0, media.position)) : 0
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: LockScreenMediaSeekBar
        private var identity: MusicContentIdentity?
        init(_ parent: LockScreenMediaSeekBar) { self.parent = parent }
        func begin() { identity = parent.media.identity }
        @objc func changed(_ slider: MediaProgressSlider) {
            guard parent.media.canSeek else { return }
            if slider.isDragging {
                guard identity == parent.media.identity else { return }
                parent.preview = slider.doubleValue
            } else {
                begin(); finish(slider)
            }
        }
        func finish(_ slider: MediaProgressSlider) {
            defer { identity = nil; parent.preview = nil }
            guard let identity, identity == parent.media.identity, parent.media.canSeek,
                  slider.doubleValue.isFinite else { return }
            parent.seek(min(parent.media.duration, max(0, slider.doubleValue)), identity)
        }
    }
}
