import AppKit
import SwiftUI
import XCTest
@testable import OrdinaryNotch

@MainActor final class LockScreenMediaControlTests: XCTestCase {
    func testNativeSliderPreviewsDragAndCommitsOnlyOnRelease() {
        let media = LockScreenActivitySnapshot.preview.rows[0].media!
        var preview: Double?
        var seeks: [Double] = []
        let bar = LockScreenMediaSeekBar(media: media, preview: Binding(get: { preview }, set: { preview = $0 })) {
            seeks.append($0); XCTAssertEqual($1, media.identity)
        }
        let coordinator = bar.makeCoordinator()
        let slider = MediaProgressSlider()
        slider.minValue = 0; slider.maxValue = media.duration
        slider.isDragging = true
        coordinator.begin()
        slider.doubleValue = 120
        coordinator.changed(slider)
        XCTAssertEqual(preview, 120)
        XCTAssertTrue(seeks.isEmpty)
        coordinator.parent.media.position = 85
        slider.isDragging = false
        coordinator.finish(slider)
        coordinator.finish(slider)
        XCTAssertEqual(seeks, [120])
        XCTAssertNil(preview)
        coordinator.begin()
        coordinator.parent.media = .init(identity: .init(source: "other", title: "Next", artist: "Artist", hasTrack: true),
            isPlaying: true, source: "Music", remaining: nil, duration: 300)
        coordinator.finish(slider)
        XCTAssertEqual(seeks, [120], "A changed track cancels the original drag")
    }

    func testLockScreenUsesNativeSliderAndSharedMenuWithCurrentDeviceCheckmark() async throws {
        let media = LockScreenActivitySnapshot.preview.rows[0].media!
        let speakers = AudioOutput.Device(id: 1, uid: "speakers", route: .init(name: "MacBook Speakers", symbol: "laptopcomputer"), selected: true)
        let airpods = AudioOutput.Device(id: 2, uid: "airpods", route: .init(name: "AirPods Pro", symbol: "airpodspro"), selected: false)
        var reads = 0, selected: AudioOutput.Device?, seeks: [Double] = []
        let root = VStack {
            LockScreenAudioOutputButton(media: media, availableOutputs: { reads += 1; return [speakers, airpods] }) { selected = $0 }
            LockScreenMediaSeekBar(media: media, preview: .constant(nil)) { seeks.append($0); _ = $1 }.frame(height: 20)
        }
        let host = NSHostingView(rootView: root)
        let window = LockScreenActivityPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let match = view as? T { return match }
            return view.subviews.lazy.compactMap { find(type, in: $0) }.first
        }
        let button = try XCTUnwrap(find(NotchPressAndHoldControl.self, in: host))
        XCTAssertTrue(button.menuOnClick)
        XCTAssertEqual(reads, 0)
        button.menuItems = try XCTUnwrap(button.loadMenuItems)()
        let menu = button.makeMenu()
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(menu.items.map(\.title), ["MacBook Speakers", "AirPods Pro"])
        XCTAssertEqual(menu.items.map(\.state), [.on, .off])
        menu.performActionForItem(at: 1)
        XCTAssertEqual(selected, airpods)
        let slider = try XCTUnwrap(find(MediaProgressSlider.self, in: host))
        XCTAssertTrue(slider.cell is MediaProgressCell, "Use the same thin track and drag-only thumb as the notch")
        XCTAssertEqual(slider.doubleValue, 84)
        _ = slider.accessibilityPerformIncrement()
        XCTAssertGreaterThan(try XCTUnwrap(seeks.first), 84)
    }
}
