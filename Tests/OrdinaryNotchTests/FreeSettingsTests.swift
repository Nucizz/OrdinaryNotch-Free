import AppKit
import SwiftUI
import XCTest
@testable import OrdinaryNotch

@MainActor private final class SettingsPreviewMusic: MusicServing {
    var onChange: ((MusicPlaybackState) -> Void)?
    func refresh() {}
    func updatePosition() {}
    func command(_ command: String) {}
    func seek(to seconds: Double) {}
    func stop() {}
}

@MainActor final class FreeSettingsTests: XCTestCase {
    func testNewPreferencesPersistAndTimerPresetsKeepExactSeconds() throws {
        var values = NotchSettings()
        values.timerPresets = [1, 59, 61, 3599, 3600, 3601, 7200, 86398, 86399]
        values.startingTab = .focus
        values.hiddenTabs = [NotchTab.fans.rawValue]
        values.tabLayout.place(NotchTab.codex.rawValue, in: .right)
        values.hapticFeedback = false
        let decoded = try JSONDecoder().decode(NotchSettings.self, from: JSONEncoder().encode(values)).normalized()
        XCTAssertEqual(decoded.timerPresets, values.timerPresets)
        XCTAssertEqual(decoded.startingTab, .focus)
        XCTAssertEqual(decoded.hiddenTabs, values.hiddenTabs)
        XCTAssertEqual(decoded.tabLayout.wing(of: NotchTab.codex.rawValue), .right)
        XCTAssertFalse(decoded.hapticFeedback)
    }

    func testEverySettingsPageRendersWithoutStartingTheNotchCamera() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = NotchViewModel(preferences: PreferencesViewModel(defaults: defaults), isPreview: true,
            music: MusicViewModel(service: SettingsPreviewMusic()))
        model.music.title = "Evening Light"; model.music.artist = "Ordinary Sessions"
        model.music.hasTrack = true; model.music.duration = 210; model.music.position = 84
        for page in SettingsPage.allCases {
            let host = NSHostingView(rootView: FreeSettingsView(model: model, showClipboard: {}, initialPage: page))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 870, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            XCTAssertGreaterThan(host.fittingSize.width, 0)
            XCTAssertFalse(model.camera.running)
            if let path = ProcessInfo.processInfo.environment["ORDINARY_FREE_PREVIEW_DIRECTORY"] {
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: path).appendingPathComponent(page.id + ".png"))
            }
            window.close()
        }
        model.music.stop()
    }
}
