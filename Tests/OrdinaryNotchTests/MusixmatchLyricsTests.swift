import XCTest
@testable import OrdinaryNotch

private actor FallbackLyrics: LyricsServing {
    private(set) var calls = 0
    func fetch(_ track: LyricsTrack) async throws -> LyricsResult {
        calls += 1
        return .synced([.init(time: 1, text: "Fallback line")])
    }
}
private final class MusixmatchHTTPStub: URLProtocol, @unchecked Sendable {
    struct Reply { var status = 200; var data: Data }
    private static let lock = NSLock()
    private static var replies: [Reply] = []
    private static var captured: [URLRequest] = []
    static func reset(_ values: [Reply]) {
        lock.lock(); defer { lock.unlock() }; replies = values; captured = []
    }
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        let reply = Self.replies.isEmpty ? Reply(status: 500, data: Data()) : Self.replies.removeFirst()
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "120"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class MusixmatchLyricsTests: XCTestCase {
    private let track = LyricsTrack(title: "Fixture", artist: "Test artist", duration: 180, album: "Deluxe")!
    private func envelope(_ body: [String: Any], status: Int = 200) -> [String: Any] {
        ["message": ["header": ["status_code": status], "body": body]]
    }
    private func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func fixture(title: String = "Fixture", album: String = "Deluxe", duration: Double = 180,
                         restricted: Int = 0, subtitleStatus: Int = 200, lrc: String = "[00:01.20]First line\n[00:05.50]Second line") throws -> Data {
        try data(envelope(["macro_calls": [
            "matcher.track.get": envelope(["track": ["track_name": title, "artist_name": "Test artist", "album_name": album, "instrumental": 0]]),
            "track.subtitles.get": envelope(["subtitle_list": [["subtitle": ["subtitle_length": duration, "restricted": restricted, "subtitle_body": lrc]]]], status: subtitleStatus)
        ]]))
    }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MusixmatchHTTPStub.self]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel() }
        return session
    }
    func testRequestsEncodeRecordingAndKeepTokensOffTokenRequest() throws {
        let track = LyricsTrack(title: "A & B?", artist: "Café + Friends", duration: 180.4, album: "Deluxe")!
        let request = MusixmatchLyricsService.request(track: track, token: "fixture-token")
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "apic-desktop.musixmatch.com")
        XCTAssertEqual(items["q_track"], track.title)
        XCTAssertEqual(items["q_artist"], track.artist)
        XCTAssertEqual(items["q_album"], "Deluxe")
        XCTAssertEqual(items["f_subtitle_length"], "180")
        XCTAssertEqual(items["subtitle_format"], "lrc")
        XCTAssertEqual(items["usertoken"], "fixture-token")
        XCTAssertFalse(MusixmatchLyricsService.request().url!.absoluteString.contains("usertoken"))
    }
    func testDecodesTimedLyricsAndRejectsUnrelatedOrRestrictedRecordings() throws {
        XCTAssertEqual(try MusixmatchLyricsService.decode(fixture(), for: track),
                       .synced([.init(time: 1.2, text: "First line"), .init(time: 5.5, text: "Second line")], source: .musixmatch))
        for value in [try fixture(title: "Unrelated"), try fixture(album: "Original"), try fixture(duration: 200),
                      try fixture(restricted: 1), try fixture(lrc: "Plain lyrics"), try fixture(lrc: "[09:00]Wrong timeline")] {
            XCTAssertEqual(try MusixmatchLyricsService.decode(value, for: track), .unavailable)
        }
        XCTAssertThrowsError(try MusixmatchLyricsService.decode(Data("<html>Service unavailable</html>".utf8), for: track))
    }
    func testCachesTokenAndLyricsAndRetriesExpiredTokenOnce() async throws {
        let token = try data(envelope(["user_token": "fixture-token"]))
        MusixmatchHTTPStub.reset([.init(data: token), .init(data: try data(envelope([:], status: 401))),
                                 .init(data: token), .init(data: try fixture()), .init(data: try fixture(title: "Next"))])
        let service = MusixmatchLyricsService(session: session(), fallback: nil)
        let first = try await service.fetch(track)
        let cached = try await service.fetch(track)
        XCTAssertEqual(first, cached)
        let next = LyricsTrack(title: "Next", artist: track.artist, duration: 180, album: track.album)!
        _ = try await service.fetch(next)
        XCTAssertEqual(MusixmatchHTTPStub.requests.map { $0.url!.lastPathComponent },
                       ["token.get", "macro.subtitles.get", "token.get", "macro.subtitles.get", "macro.subtitles.get"])
    }
    func testMismatchesFallBackAndKeepCorrectSource() async throws {
        MusixmatchHTTPStub.reset([.init(data: try data(envelope(["user_token": "fixture-token"]))),
                                 .init(data: try fixture(title: "Wrong song"))])
        let fallback = FallbackLyrics(), service = MusixmatchLyricsService(session: session(), fallback: fallback)
        let result = try await service.fetch(track)
        XCTAssertEqual(result, .synced([.init(time: 1, text: "Fallback line")], source: .lrclib))
        _ = try await service.fetch(track)
        let calls = await fallback.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(MusixmatchHTTPStub.requests.count, 2)
    }
    func testRateLimitFallsBackWithoutRequestingAgainForNextTrack() async throws {
        MusixmatchHTTPStub.reset([.init(status: 429, data: Data())])
        let fallback = FallbackLyrics(), service = MusixmatchLyricsService(session: session(), fallback: fallback)
        _ = try await service.fetch(track)
        _ = try await service.fetch(LyricsTrack(title: "Next", artist: track.artist, duration: 180)!)
        XCTAssertEqual(MusixmatchHTTPStub.requests.count, 1)
        let calls = await fallback.calls
        XCTAssertEqual(calls, 2)
    }
    func testRejectedTokenDoesNotLoopAndMissingSubtitleUsesFallback() async throws {
        let token = try data(envelope(["user_token": "fixture-token"]))
        let denied = try data(envelope([:], status: 401))
        MusixmatchHTTPStub.reset([.init(data: token), .init(data: denied), .init(data: token), .init(data: denied)])
        let fallback = FallbackLyrics(), service = MusixmatchLyricsService(session: session(), fallback: fallback)
        _ = try await service.fetch(track)
        XCTAssertEqual(MusixmatchHTTPStub.requests.count, 4)
        let calls = await fallback.calls
        XCTAssertEqual(calls, 1)
        MusixmatchHTTPStub.reset([.init(data: token), .init(data: try fixture(subtitleStatus: 404))])
        let missing = MusixmatchLyricsService(session: session(), fallback: fallback)
        let result = try await missing.fetch(track)
        XCTAssertEqual(result, .synced([.init(time: 1, text: "Fallback line")]))
    }
    @MainActor func testViewModelUsesAndClearsProviderAttribution() async throws {
        MusixmatchHTTPStub.reset([.init(data: try data(envelope(["user_token": "fixture-token"]))), .init(data: try fixture())])
        let model = LyricsViewModel(service: MusixmatchLyricsService(session: session(), fallback: nil))
        model.update(track: track, position: 3); model.toggle()
        for _ in 0..<150 { if model.status == .ready { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.source, .musixmatch)
        XCTAssertEqual(model.text, "First line")
        model.toggle(); XCTAssertNil(model.source)
    }
}
