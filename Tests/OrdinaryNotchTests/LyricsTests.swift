import XCTest
import SwiftUI
@testable import OrdinaryNotch

private actor PendingLyrics: LyricsServing {
    private var pending: [String: CheckedContinuation<LyricsResult, Error>] = [:]
    private(set) var titles: [String] = []
    private(set) var tracks: [LyricsTrack] = []
    func fetch(_ track: LyricsTrack) async throws -> LyricsResult {
        titles.append(track.title); tracks.append(track)
        return try await withCheckedThrowingContinuation { pending[track.title] = $0 }
    }
    func complete(_ title: String, result: LyricsResult) { pending.removeValue(forKey: title)?.resume(returning: result) }
}
private struct PreviewLyrics: LyricsServing {
    func fetch(_ track: LyricsTrack) async throws -> LyricsResult {
        .synced([.init(time: 0, text: "A quiet moment, then the melody begins"), .init(time: 10, text: "Follow the rhythm into the morning light")])
    }
}
@MainActor private final class LyricsMusic: MusicServing {
    var onChange: ((MusicPlaybackState) -> Void)?
    func refresh() {}
    var positionUpdates = 0
    func updatePosition() { positionUpdates += 1 }
    func command(_ command: String) {}
    func stop() {}
}
final class LyricsTests: XCTestCase {
    private func track(_ title: String = "Fixture") -> LyricsTrack { LyricsTrack(title: title, artist: "Test artist", duration: 180)! }
    func testLRCHandlesRepeatedTimesOffsetBlankGapsAndBackwardSeeks() {
        let lines = TimedLyrics.parse("[ar:Fixture]\n[offset:500]\n[00:02.50][00:12.500]First line\n[00:05]\n[00:08.25]Second line\ninvalid")
        XCTAssertEqual(lines.map(\.time), [2, 4.5, 7.75, 12])
        XCTAssertNil(TimedLyrics.current(in: lines, at: 1.9))
        XCTAssertEqual(TimedLyrics.current(in: lines, at: 2)?.text, "First line")
        XCTAssertEqual(TimedLyrics.current(in: lines, at: 6)?.text, "")
        XCTAssertEqual(TimedLyrics.current(in: lines, at: 8)?.text, "Second line")
        XCTAssertEqual(TimedLyrics.current(in: lines, at: 3)?.text, "First line")
        XCTAssertNil(TimedLyrics.current(in: lines, at: .nan))
    }
    func testMetadataEncodingAndWrongRecordingRejection() throws {
        let special = LyricsTrack(title: "A & B?", artist: "Café + Friends", duration: 180.4)!
        let request = LyricsService.request(for: special)
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "track_name" }?.value, "A & B?")
        XCTAssertEqual(items.first { $0.name == "artist_name" }?.value, "Café + Friends")
        XCTAssertEqual(items.count, 3)
        var record: [String: Any] = ["trackName": "Fixture", "artistName": "Test artist", "duration": 180, "instrumental": false, "syncedLyrics": "[00:00]Example line"]
        func decode() throws -> LyricsResult { try LyricsService.decode(JSONSerialization.data(withJSONObject: record), for: track()) }
        XCTAssertEqual(try decode(), .synced([.init(time: 0, text: "Example line")]))
        record["duration"] = 190; XCTAssertEqual(try decode(), .unavailable)
        record["duration"] = 180; record["trackName"] = "Different recording"
        XCTAssertEqual(try decode(), .unavailable)
        record["trackName"] = "Fixture"; record["syncedLyrics"] = NSNull()
        XCTAssertEqual(try decode(), .unavailable)
        record["instrumental"] = true; XCTAssertEqual(try decode(), .instrumental)
    }
    func testAlbumIsUsedToSelectAndValidateTheRecording() throws {
        let deluxe = LyricsTrack(title: "Fixture", artist: "Test artist", duration: 180, album: "  Album (Deluxe)  ")!
        let original = LyricsTrack(title: "Fixture", artist: "Test artist", duration: 180, album: "Album")!
        XCTAssertNotEqual(deluxe, original, "Different albums must have separate cache entries")
        let items = URLComponents(url: LyricsService.request(for: deluxe).url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "album_name" }?.value, "Album (Deluxe)")
        var record: [String: Any] = ["trackName": "Fixture", "artistName": "Test artist", "albumName": "Album", "duration": 180, "instrumental": false, "syncedLyrics": "[00:01]Fixture line"]
        func decode() throws -> LyricsResult { try LyricsService.decode(JSONSerialization.data(withJSONObject: record), for: deluxe) }
        XCTAssertEqual(try decode(), .unavailable, "Matching title and duration do not justify another album's timing")
        record["albumName"] = "album (deluxe)"
        XCTAssertEqual(try decode(), .synced([.init(time: 1, text: "Fixture line")]))
        record.removeValue(forKey: "albumName")
        XCTAssertEqual(try decode(), .unavailable)
        XCTAssertNil(LyricsTrack(title: "Fixture", artist: "Test artist", duration: 180, album: "  ")?.album)
    }
    @MainActor func testAlbumChangeFlowsFromPlayerAndFetchesNewTiming() async throws {
        let service = PendingLyrics(), player = LyricsMusic()
        let music = MusicViewModel(service: player, lyrics: LyricsViewModel(service: service))
        var state = MusicPlaybackState()
        state.title = "Fixture"; state.artist = "Test artist"; state.album = "Album"
        state.duration = 180; state.hasTrack = true; state.position = 2
        player.onChange?(state); music.lyrics.toggle()
        for _ in 0..<100 { if await service.tracks.count == 1 { break }; await Task.yield() }
        await service.complete("Fixture", result: .synced([.init(time: 1, text: "First timing")]))
        for _ in 0..<100 { if music.lyrics.status == .ready { break }; await Task.yield() }
        state.album = "Album (Deluxe)"; player.onChange?(state)
        for _ in 0..<100 { if await service.tracks.count == 2 { break }; await Task.yield() }
        XCTAssertEqual(music.lyrics.status, .loading)
        await service.complete("Fixture", result: .synced([.init(time: 1, text: "Deluxe timing")]))
        for _ in 0..<100 { if music.lyrics.status == .ready { break }; await Task.yield() }
        XCTAssertEqual(music.lyrics.text, "Deluxe timing")
        let albums = await service.tracks.map(\.album)
        XCTAssertEqual(albums, ["Album", "Album (Deluxe)"])
    }
    @MainActor func testUnavailableHidesAfterThreeSecondsAndNextSongRetries() async throws {
        let service = PendingLyrics(), player = LyricsMusic()
        let music = MusicViewModel(service: player, lyrics: LyricsViewModel(service: service))
        let suite = "OrdinaryNotch.lyrics-unavailable.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let notch = NotchViewModel(preferences: PreferencesViewModel(defaults: defaults), isPreview: true, music: music)
        notch.dismissWelcome()
        music.title = "Missing"; music.artist = "Test artist"; music.duration = 180; music.hasTrack = true; music.isPlaying = true
        music.lyrics.toggle()
        for _ in 0..<100 { if await service.titles.contains("Missing") { break }; await Task.yield() }
        await service.complete("Missing", result: .unavailable)
        for _ in 0..<100 { if music.lyrics.status == .unavailable { break }; await Task.yield() }
        XCTAssertTrue(notch.lyricsVisible)
        try await Task.sleep(for: .seconds(2))
        XCTAssertFalse(music.lyrics.hiddenForCurrentTrack, "Keep the brief visible for the full three seconds")
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(music.lyrics.hiddenForCurrentTrack)
        XCTAssertTrue(music.lyrics.enabled, "Stay enabled for the next song")
        for presentation in LyricsPresentation.allCases {
            notch.preferences.values.lyricsPresentation = presentation
            XCTAssertFalse(notch.lyricsVisible)
        }
        music.position = 15
        let before = await service.titles
        XCTAssertEqual(before, ["Missing"], "Playback ticks must not retry the same unavailable song")
        music.title = "Next song"
        for _ in 0..<100 { if await service.titles.contains("Next song") { break }; await Task.yield() }
        XCTAssertTrue(notch.lyricsVisible)
        await service.complete("Next song", result: .synced([.init(time: 0, text: "Available")]))
        for _ in 0..<100 { if music.lyrics.status == .ready { break }; await Task.yield() }
        XCTAssertEqual(music.lyrics.text, "Available")
        XCTAssertFalse(music.lyrics.hiddenForCurrentTrack)
    }
    @MainActor func testPreviousUnavailableTimeoutCannotHideTheNextSong() async throws {
        let service = PendingLyrics(), model = LyricsViewModel(service: service)
        model.update(track: track("Missing"), position: 0); model.toggle()
        for _ in 0..<100 { if await service.titles.contains("Missing") { break }; await Task.yield() }
        await service.complete("Missing", result: .instrumental)
        for _ in 0..<100 { if model.status == .instrumental { break }; await Task.yield() }
        model.update(track: track("Next"), position: 1)
        for _ in 0..<100 { if await service.titles.contains("Next") { break }; await Task.yield() }
        await service.complete("Next", result: .synced([.init(time: 0, text: "Keep visible")]))
        try await Task.sleep(for: .milliseconds(3200))
        XCTAssertEqual(model.text, "Keep visible")
        XCTAssertFalse(model.hiddenForCurrentTrack)
    }
    @MainActor func testOptInTrackChangesPauseAndStaleResponses() async throws {
        let service = PendingLyrics()
        // A separate fixture ensures merely observing a track never fetches lyrics.
        let active = LyricsViewModel(service: service)
        active.update(track: track("First"), position: 3)
        let before = await service.titles
        XCTAssertTrue(before.isEmpty)
        active.toggle()
        for _ in 0..<100 { if await service.titles.contains("First") { break }; await Task.yield() }
        active.update(track: track("Second"), position: 11)
        for _ in 0..<100 { if await service.titles.contains("Second") { break }; await Task.yield() }
        await service.complete("Second", result: .synced([.init(time: 0, text: "Opening"), .init(time: 10, text: "Current")]))
        for _ in 0..<100 { if active.status == .ready { break }; await Task.yield() }
        XCTAssertEqual(active.text, "Current")
        await service.complete("First", result: .synced([.init(time: 0, text: "Stale")]))
        await Task.yield()
        XCTAssertEqual(active.text, "Current")
        active.update(track: track("Second"), position: 1)
        XCTAssertEqual(active.text, "Opening")
        active.update(track: track("Second"), position: 1) // Paused position remains fixed.
        XCTAssertEqual(active.text, "Opening")
        let titles = await service.titles
        XCTAssertEqual(titles, ["First", "Second"])
        active.toggle(); XCTAssertFalse(active.enabled); XCTAssertNil(active.currentLine)
    }
    @MainActor func testTimingAdjustmentAppliesImmediatelyAndAfterLoadingWithoutRefetch() async throws {
        let service = PendingLyrics(), model = LyricsViewModel(service: service)
        model.update(track: track(), position: 9.5)
        model.setTimingOffset(0.6)
        model.toggle()
        for _ in 0..<100 { if await service.titles.count == 1 { break }; await Task.yield() }
        await service.complete("Fixture", result: .synced([.init(time: 0, text: "Opening"), .init(time: 10, text: "Next")]))
        for _ in 0..<100 { if model.status == .ready { break }; await Task.yield() }
        XCTAssertEqual(model.text, "Next", "Positive offset advances lyrics, including the initial response")
        model.setTimingOffset(0)
        XCTAssertEqual(model.text, "Opening")
        model.update(track: track(), position: 10.2)
        XCTAssertEqual(model.text, "Next")
        model.setTimingOffset(-0.5)
        XCTAssertEqual(model.text, "Opening", "Negative offset delays lyrics immediately while paused")
        model.setTimingOffset(.nan)
        XCTAssertEqual(model.text, "Next")
        model.update(track: track(), position: 1)
        XCTAssertEqual(model.text, "Opening")
        let titles = await service.titles
        XCTAssertEqual(titles, ["Fixture"], "Timing changes must not fetch lyrics again")
    }
    @MainActor func testLyricsClockRunsOnlyWhileEnabledAndPlaying() async throws {
        let service = LyricsMusic(), model = MusicViewModel(service: service, lyrics: LyricsViewModel(service: PreviewLyrics()))
        model.title = "Fixture"; model.artist = "Test artist"; model.duration = 180; model.hasTrack = true
        model.isPlaying = true
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(service.positionUpdates, 0)
        model.lyrics.toggle()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertGreaterThan(service.positionUpdates, 0)
        model.isPlaying = false
        let paused = service.positionUpdates
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(service.positionUpdates, paused)
        model.isPlaying = true
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertGreaterThan(service.positionUpdates, paused)
        model.lyrics.toggle()
        let disabled = service.positionUpdates
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(service.positionUpdates, disabled)
        model.lyrics.toggle(); model.stop()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(service.positionUpdates, disabled)
    }
    @MainActor func testTimingPreferencePersistsAndUpdatesVisibleLyrics() async throws {
        let suite = "OrdinaryNotch.lyrics-timing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesViewModel(defaults: defaults)
        XCTAssertEqual(preferences.values.lyricsTimingOffset, 0)
        let music = MusicViewModel(service: LyricsMusic(), lyrics: LyricsViewModel(service: PreviewLyrics()))
        let notch = NotchViewModel(preferences: preferences, isPreview: true, music: music)
        music.title = "Fixture"; music.artist = "Test artist"; music.duration = 180; music.hasTrack = true; music.isPlaying = true; music.position = 9.5
        music.lyrics.toggle()
        for _ in 0..<100 { if music.lyrics.status == .ready { break }; await Task.yield() }
        XCTAssertEqual(music.lyrics.currentLine?.time, 0)
        notch.preferences.values.lyricsTimingOffset = 0.6
        XCTAssertEqual(music.lyrics.currentLine?.time, 10)
        XCTAssertEqual(PreferencesViewModel(defaults: defaults).values.lyricsTimingOffset, 0.6)
        var settings = NotchSettings()
        settings.lyricsTimingOffset = 20; XCTAssertEqual(settings.normalized().lyricsTimingOffset, 5)
        settings.lyricsTimingOffset = -.infinity; XCTAssertEqual(settings.normalized().lyricsTimingOffset, 0)
    }
    @MainActor func testTurningOffAndStoppingPlaybackRejectLateLyrics() async throws {
        let service = PendingLyrics(), model = LyricsViewModel(service: service)
        model.update(track: track(), position: 0); model.toggle()
        for _ in 0..<100 { if await service.titles.count == 1 { break }; await Task.yield() }
        model.toggle()
        await service.complete("Fixture", result: .synced([.init(time: 0, text: "Too late")]))
        await Task.yield()
        XCTAssertFalse(model.enabled); XCTAssertNil(model.currentLine); XCTAssertEqual(model.status, .idle)
        model.update(track: nil, position: 0)
        XCTAssertNil(model.currentLine)
    }
    @MainActor func testLyricsFitCollapsedExpandedAndYieldToPrompts() async throws {
        let music = MusicViewModel(service: LyricsMusic(), lyrics: LyricsViewModel(service: PreviewLyrics()))
        let suite = "OrdinaryNotch.lyrics-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = NotchViewModel(preferences: PreferencesViewModel(defaults: defaults), isPreview: true, music: music)
        model.dismissWelcome()
        music.title = "Fixture"; music.artist = "Test artist"; music.duration = 180; music.hasTrack = true; music.isPlaying = true
        let baseHeight = model.surfaceSize.height
        music.lyrics.toggle()
        for _ in 0..<100 { if music.lyrics.status == .ready { break }; await Task.yield() }
        XCTAssertEqual(model.surfaceSize.height, baseHeight + 44)
        XCTAssertGreaterThanOrEqual(model.surfaceSize.width, 400)
        model.expanded = true
        XCTAssertEqual(model.expandedHeight, model.pageHeight + 44)
        XCTAssertTrue(model.lyricsVisible)
        model.tab = .focus; XCTAssertFalse(model.lyricsVisible)
        model.tab = .overview
        var activity = CodexActivity.idle; activity.state = "running"
        let task = CodeTask(id: "q", provider: .codex, activity: activity)
        model.agentActions.apply([AgentPrompt(id: "q", task: task, kind: .question, requestID: "q")])
        XCTAssertFalse(model.lyricsVisible)
        model.agentActions.apply([])
        for style in NotchStyle.allCases {
            model.displayStyle = style
            XCTAssertTrue(model.lyricsVisible)
            XCTAssertLessThanOrEqual(model.surfaceSize.height, model.canvasSize.height)
        }
        music.hasTrack = false
        XCTAssertFalse(model.lyricsVisible)
    }
    @MainActor func testFloatingModePreservesNotchSizeAndDoesNotClaimClicks() async throws {
        let music = MusicViewModel(service: LyricsMusic(), lyrics: LyricsViewModel(service: PreviewLyrics()))
        let suite = "OrdinaryNotch.lyrics-layout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesViewModel(defaults: defaults)
        XCTAssertEqual(preferences.values.lyricsPresentation, .integrated)
        let model = NotchViewModel(preferences: preferences, isPreview: true, music: music)
        model.dismissWelcome()
        music.title = "Fixture"; music.artist = "Test artist"; music.duration = 180; music.hasTrack = true; music.isPlaying = true
        preferences.values.lyricsPresentation = .floating
        XCTAssertEqual(PreferencesViewModel(defaults: defaults).values.lyricsPresentation, .floating)
        music.lyrics.toggle()
        for _ in 0..<100 { if music.lyrics.status == .ready { break }; await Task.yield() }
        for style in NotchStyle.allCases {
            model.displayStyle = style
            for expanded in [false, true] {
                model.expanded = expanded
                XCTAssertTrue(model.floatingLyricsVisible)
                XCTAssertFalse(model.integratedLyricsVisible)
                XCTAssertEqual(model.lyricsHeight, 0)
                XCTAssertEqual(model.surfaceSize.height, expanded ? model.pageHeight : model.compactHeight)
                XCTAssertEqual(model.surfaceSize.width, expanded ? model.expandedSurfaceWidth : model.compactWidth)
                XCTAssertLessThan(model.floatingLyricsTop + 44 + 24, model.canvasSize.height)

            }
        }
        preferences.values.lyricsPresentation = .integrated
        XCTAssertTrue(model.integratedLyricsVisible)
        XCTAssertFalse(model.floatingLyricsVisible)
        XCTAssertEqual(model.surfaceSize.height, model.pageHeight + 44)
        music.lyrics.toggle()
        XCTAssertFalse(model.lyricsVisible)
    }
    @MainActor func testPauseHidesLyricsAndResumeRestoresWithoutFetchingAgain() async throws {
        let service = PendingLyrics()
        let music = MusicViewModel(service: LyricsMusic(), lyrics: LyricsViewModel(service: service))
        defer { music.stop() }
        let suite = "OrdinaryNotch.lyrics-pause.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = NotchViewModel(preferences: PreferencesViewModel(defaults: defaults), isPreview: true, music: music)
        model.dismissWelcome()
        music.title = "Fixture"; music.artist = "Test artist"; music.duration = 180
        music.hasTrack = true; music.isPlaying = true; music.position = 10
        music.lyrics.toggle()
        for _ in 0..<100 { if await service.titles.count == 1 { break }; await Task.yield() }
        await service.complete("Fixture", result: .synced([.init(time: 0, text: "Current line")]))
        for _ in 0..<100 { if music.lyrics.status == .ready { break }; await Task.yield() }
        for style in NotchStyle.allCases {
            model.displayStyle = style
            for presentation in LyricsPresentation.allCases {
                model.preferences.values.lyricsPresentation = presentation
                for expanded in [false, true] {
                    model.expanded = expanded
                    music.isPlaying = true
                    XCTAssertTrue(model.lyricsVisible)
                    music.isPlaying = false
                    XCTAssertFalse(model.lyricsVisible)
                    XCTAssertFalse(model.integratedLyricsVisible)
                    XCTAssertFalse(model.floatingLyricsVisible)
                    XCTAssertEqual(model.lyricsHeight, 0)
                    XCTAssertTrue(music.lyrics.enabled, "Pause hides the presentation without disabling lyrics")
                    music.isPlaying = true
                    XCTAssertTrue(model.lyricsVisible)
                    XCTAssertEqual(music.lyrics.text, "Current line")
                }
            }
        }
        let titles = await service.titles
        XCTAssertEqual(titles, ["Fixture"], "Play/pause must reuse the loaded lyrics")
    }


}

private final class LyricsHTTPStub: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    private static var status = 200
    private static var count = 0
    static func reset(status: Int) { lock.lock(); defer { lock.unlock() }; Self.status = status; count = 0 }
    static var requests: Int { lock.lock(); defer { lock.unlock() }; return count }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; let status = Self.status; Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "120"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"trackName":"Fixture","artistName":"Test artist","duration":180,"instrumental":false,"syncedLyrics":"[00:00]Example line"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
extension LyricsTests {
    func testCacheAndRateLimitPreventRepeatedNetworkRequests() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LyricsHTTPStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        LyricsHTTPStub.reset(status: 200)
        let service = LyricsService(session: session)
        let first = try await service.fetch(track())
        let second = try await service.fetch(track())
        XCTAssertEqual(first, second)
        XCTAssertEqual(LyricsHTTPStub.requests, 1)
        LyricsHTTPStub.reset(status: 429)
        let limited = LyricsService(session: session)
        for _ in 0..<2 {
            do { _ = try await limited.fetch(track()); XCTFail("Expected rate limit") }
            catch { XCTAssertEqual((error as? URLError)?.code, .resourceUnavailable) }
        }
        XCTAssertEqual(LyricsHTTPStub.requests, 1, "Honor Retry-After even if the button is toggled again")
    }
}
