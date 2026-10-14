import XCTest
@testable import OrdinaryNotch

@MainActor private final class DefaultPlayerMusicService: MusicServing {
    var onChange: ((MusicPlaybackState) -> Void)?
    var commands: [String] = []
    var refreshCount = 0
    func refresh() { refreshCount += 1 }
    func updatePosition() {}
    func command(_ command: String) { commands.append(command) }
    func seek(to seconds: Double) {}
    func stop() {}
}

@MainActor private final class TestDefaultPlayerLauncher: DefaultMediaLaunching {
    var selections: [DefaultMediaSelection] = []
    var onFinish: (() -> Void)?
    var pending: CheckedContinuation<Void, Never>?
    var message: String? = "Choose a track to begin playback."
    func play(_ selection: DefaultMediaSelection, shouldContinue: @escaping @MainActor () -> Bool) async throws -> String? {
        selections.append(selection)
        await withCheckedContinuation { pending = $0 }
        defer { onFinish?() }
        try Task.checkCancellation()
        return shouldContinue() ? message : nil
    }
    func finish() { pending?.resume(); pending = nil }
}

final class DefaultMediaPlayerTests: XCTestCase {
    @MainActor private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Playback did not reach the expected state")
    }

    func testSelectionSurvivesRoundTripAndOldSettingsRemainOptIn() throws {
        XCTAssertEqual(try JSONDecoder().decode(NotchSettings.self, from: Data("{}".utf8)).defaultMediaPlayer, .none)
        XCTAssertEqual(try JSONDecoder().decode(NotchSettings.self,
            from: Data(#"{"defaultMediaPlayer":"futurePlayer"}"#.utf8)).defaultMediaPlayer, .none)
        for player in DefaultMediaPlayer.allCases {
            var settings = NotchSettings()
            settings.defaultMediaPlayer = player
            settings.defaultMediaApplicationPath = "/Applications/My Player.app"
            let restored = try JSONDecoder().decode(NotchSettings.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(restored.defaultMediaSelection, settings.defaultMediaSelection)
        }
    }

    @MainActor func testPausedAndPlayingTracksAlwaysKeepTheirCurrentPlayer() {
        let service = DefaultPlayerMusicService(), launcher = TestDefaultPlayerLauncher()
        let model = MusicViewModel(service: service, defaultLauncher: launcher)
        model.defaultPlayer = .init(player: .spotify)
        for playing in [false, true] {
            var state = MusicPlaybackState()
            state.hasTrack = true; state.isPlaying = playing; state.sourceIdentifier = "com.apple.Music"
            service.onChange?(state)
            XCTAssertTrue(model.canPlay)
            model.command("playpause")
        }
        XCTAssertEqual(service.commands, ["playpause", "playpause"])
        XCTAssertTrue(launcher.selections.isEmpty)
        model.stop()
    }

    @MainActor func testEmptyStateLaunchesOnceAndReportsMissingQueue() async throws {
        let service = DefaultPlayerMusicService(), launcher = TestDefaultPlayerLauncher()
        let model = MusicViewModel(service: service, defaultLauncher: launcher)
        model.defaultPlayer = .init(player: .soundcloud)
        XCTAssertTrue(model.canPlay)
        model.command("playpause"); model.command("playpause")
        try await eventually { !launcher.selections.isEmpty }
        XCTAssertTrue(model.isStartingDefaultPlayer)
        XCTAssertEqual(launcher.selections.map(\.player), [.soundcloud])
        XCTAssertTrue(service.commands.isEmpty, "Never send a global toggle to an unrelated player")
        launcher.finish()
        try await eventually { !model.isStartingDefaultPlayer }
        XCTAssertEqual(model.idlePlaybackDetail, launcher.message)
        XCTAssertEqual(service.refreshCount, 1)
        model.stop()
    }

    @MainActor func testPauseCancelsPendingLaunchAndCannotPublishAnOldResult() async throws {
        let service = DefaultPlayerMusicService(), launcher = TestDefaultPlayerLauncher()
        let model = MusicViewModel(service: service, defaultLauncher: launcher)
        var finished = false
        launcher.onFinish = { finished = true }
        model.defaultPlayer = .init(player: .youtubeMusic)
        model.command("playpause")
        try await eventually { !launcher.selections.isEmpty }
        model.command("pause")
        launcher.finish()
        try await eventually { finished }
        XCTAssertFalse(model.isStartingDefaultPlayer)
        XCTAssertNil(model.defaultPlaybackMessage)
        XCTAssertEqual(service.commands, ["pause"])
        XCTAssertEqual(service.refreshCount, 0)
        model.stop()
    }

    @MainActor func testPreferenceChangesReachExistingMusicModelAndDisableIncompleteChoice() throws {
        let suite = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesViewModel(defaults: defaults)
        let music = MusicViewModel(service: DefaultPlayerMusicService(), defaultLauncher: TestDefaultPlayerLauncher())
        let notch = NotchViewModel(preferences: preferences, isPreview: true, music: music)
        XCTAssertFalse(music.canPlay)
        preferences.values.defaultMediaPlayer = .other
        XCTAssertFalse(music.canPlay)
        preferences.values.defaultMediaApplicationPath = "/Applications/My Player.app"
        XCTAssertTrue(music.canPlay)
        XCTAssertEqual(music.playHint, "Play in My Player")
        XCTAssertEqual(PreferencesViewModel(defaults: defaults).values.defaultMediaSelection, music.defaultPlayer)
        withExtendedLifetime(notch) {}
        music.stop()
    }

    @MainActor func testTransportMatcherRejectsTrackTilesAndPauseButtons() {
        XCTAssertTrue(DefaultMediaLauncher.isPlayControl(label: "Play current", siblingLabels: []))
        XCTAssertTrue(DefaultMediaLauncher.isPlayControl(label: "Play (k)", siblingLabels: []))
        XCTAssertTrue(DefaultMediaLauncher.isPlayControl(label: "Play", siblingLabels: ["Play", "Next", "Previous"]))
        XCTAssertFalse(DefaultMediaLauncher.isPlayControl(label: "Play", siblingLabels: ["Like", "Share"]))
        for label in ["Pause", "Pause current", "Play playlist", "Play advertisement"] {
            XCTAssertFalse(DefaultMediaLauncher.isPlayControl(label: label, siblingLabels: ["Next", "Previous"]))
        }
    }

    func testWebsiteScopeRejectsOtherServicesAndLookalikeDomains() {
        let player = DefaultMediaPlayer.soundcloud
        XCTAssertTrue(player.acceptsWebURL(URL(string: "https://soundcloud.com/discover")!))
        XCTAssertFalse(player.acceptsWebURL(URL(string: "https://soundcloud.com.example.org/")!))
        XCTAssertFalse(player.acceptsWebURL(URL(string: "https://music.youtube.com/")!))
        XCTAssertFalse(player.acceptsWebURL(URL(string: "http://soundcloud.com/")!))
        XCTAssertTrue(DefaultMediaPlayer.deezer.acceptsWebURL(URL(string: "https://deezer.com/en/")!))
    }
}
