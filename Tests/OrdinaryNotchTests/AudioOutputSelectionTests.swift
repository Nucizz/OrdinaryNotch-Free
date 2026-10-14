import XCTest
import SwiftUI
@testable import OrdinaryNotch

@MainActor final class AudioOutputSelectionTests: XCTestCase {
    func testNotchOutputControlStaysExactlySquare() {
        let music = MusicViewModel(service: OutputMusicService())
        let host = NSHostingView(rootView: NotchAudioOutputButton(music: music))
        XCTAssertEqual(host.fittingSize.width, NotchControlMetrics.size, accuracy: 0.5)
        XCTAssertEqual(host.fittingSize.height, NotchControlMetrics.size, accuracy: 0.5)
        music.stop()
    }
    func testOpeningMenuReloadsDevicesAndSelectionRefreshesPlaybackState() {
        let speakers = AudioOutput.Device(id: 1, uid: "speakers", route: .init(name: "MacBook Speakers", symbol: "laptopcomputer"), selected: true)
        let headphones = AudioOutput.Device(id: 2, uid: "headphones", route: .init(name: "AirPods Pro", symbol: "airpodspro"), selected: false)
        var devices = [speakers, headphones], reads = 0
        var selected: AudioOutput.Device?
        var succeeds = true
        let service = OutputMusicService()
        let music = MusicViewModel(service: service,
            listAudioOutputs: { reads += 1; return devices },
            selectAudioOutput: { selected = $0; return succeeds })
        service.onChange?(MusicPlaybackState(title: "Track", artist: "Artist", hasTrack: true,
            outputName: speakers.route.name, outputSymbol: speakers.route.symbol))
        let originalTrack = music.contentIdentity
        XCTAssertEqual(reads, 0, "Do not enumerate devices during normal playback")
        let menu = music.outputMenuItems()
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(menu[0].selected)
        XCTAssertFalse(menu[1].selected)
        menu[1].action()
        XCTAssertEqual(selected?.uid, headphones.uid)
        XCTAssertEqual(music.outputName, headphones.route.name)
        XCTAssertEqual(music.outputSymbol, headphones.route.symbol)
        XCTAssertEqual(service.refreshes, 1)
        XCTAssertEqual(music.contentIdentity, originalTrack)

        succeeds = false
        menu[0].action()
        XCTAssertNotNil(music.outputSelectionError)
        XCTAssertEqual(music.outputName, headphones.route.name, "Failed switches must not claim the requested route is active")
        succeeds = true
        menu[0].action()
        XCTAssertNil(music.outputSelectionError)
        XCTAssertEqual(music.outputName, speakers.route.name)
        devices = []
        XCTAssertFalse(music.outputMenuItems()[0].enabled)
        XCTAssertEqual(reads, 2, "Each open must reflect connects and disconnects")
        music.stop()
    }

    func testLiveOutputEnumerationAndCurrentSelectionWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["ORDINARY_AUDIO_OUTPUT_CHECK"] == "1" else {
            throw XCTSkip("Opt-in current output verification")
        }
        let devices = AudioOutput.devices()
        let current = try XCTUnwrap(devices.first(where: \.selected))
        XCTAssertEqual(AudioOutput.current(), current.route)
        XCTAssertTrue(AudioOutput.select(current), "Selecting the already-active device is a no-op")
        var stale = AudioOutput.Device(id: current.id, uid: current.uid + "-disconnected", route: current.route, selected: true)
        XCTAssertFalse(AudioOutput.select(stale), "A reused numeric ID cannot select a different device")
        stale = AudioOutput.Device(id: 0, uid: "missing", route: current.route, selected: false)
        XCTAssertFalse(AudioOutput.select(stale))
    }
}

@MainActor private final class OutputMusicService: MusicServing {
    var onChange: ((MusicPlaybackState) -> Void)?
    var refreshes = 0
    func refresh() { refreshes += 1 }
    func updatePosition() {}
    func command(_ command: String) {}
    func seek(to seconds: Double) {}
    func stop() {}
}
