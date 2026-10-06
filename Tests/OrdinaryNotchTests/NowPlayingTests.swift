import XCTest
@testable import OrdinaryNotch

final class NowPlayingTests: XCTestCase {
    private let event = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.spotify.client","title":"A song","artist":"Artist","playing":true,"durationMicros":180000000,"elapsedTimeMicros":12000000,"timestampEpochMicros":1000000000,"playbackRate":1}}"#

    func testPlaybackTimelineUsesTimestampAndClampsToDuration() throws {
        let snapshot = try XCTUnwrap(NowPlayingSnapshot.decodeEvent(Data(event.utf8)))
        XCTAssertEqual(snapshot.position(at: Date(timeIntervalSince1970: 1005)), 17)
        XCTAssertEqual(snapshot.position(at: Date(timeIntervalSince1970: 999)), 12)
        XCTAssertEqual(snapshot.position(at: Date(timeIntervalSince1970: 2000)), 180)
        let paused = event.replacingOccurrences(of: "\"playing\":true", with: "\"playing\":false")
        XCTAssertEqual(try NowPlayingSnapshot.decodeEvent(Data(paused.utf8))?.position(at: Date(timeIntervalSince1970: 2000)), 12)
    }

    func testAlbumMetadataIsDecodedWhenPresentAndOptionalForOlderPlayers() throws {
        let withAlbum = event.replacingOccurrences(of: "\"title\":\"A song\"", with: "\"title\":\"A song\",\"album\":\"Album (Deluxe)\"")
        XCTAssertEqual(try NowPlayingSnapshot.decodeEvent(Data(withAlbum.utf8))?.album, "Album (Deluxe)")
        XCTAssertNil(try NowPlayingSnapshot.decodeEvent(Data(event.utf8))?.album)
    }

    func testResumeWaitsForFreshTimestampWithoutJumpingToEnd() throws {
        let paused = event.replacingOccurrences(of: "\"playing\":true", with: "\"playing\":false")
        var timeline = NowPlayingTimeline()
        timeline.update(try NowPlayingSnapshot.decodeEvent(Data(paused.utf8)), at: Date(timeIntervalSince1970: 1100))
        let resumed = try NowPlayingSnapshot.decodeEvent(Data(event.utf8))
        timeline.update(resumed, at: Date(timeIntervalSince1970: 1300))
        XCTAssertEqual(timeline.snapshot?.position(at: Date(timeIntervalSince1970: 1301)), 13)
        // Another notification with the same old timing must retain the corrected baseline.
        timeline.update(resumed, at: Date(timeIntervalSince1970: 1302))
        XCTAssertEqual(timeline.snapshot?.position(at: Date(timeIntervalSince1970: 1303)), 15)
        timeline.update(try NowPlayingSnapshot.decodeEvent(Data(paused.utf8)), at: Date(timeIntervalSince1970: 1304))
        XCTAssertEqual(timeline.snapshot?.position(at: Date(timeIntervalSince1970: 1400)), 16)
        timeline.update(nil, at: Date())
        XCTAssertNil(timeline.snapshot)
    }

    func testEmptySessionClearsTrackAndMalformedEnvelopeIsRejected() throws {
        XCTAssertNil(try NowPlayingSnapshot.decodeEvent(Data(#"{"type":"data","diff":false,"payload":{}}"#.utf8)))
        XCTAssertThrowsError(try NowPlayingSnapshot.decodeEvent(Data(event.replacingOccurrences(of: "\"diff\":false", with: "\"diff\":true").utf8)))
        XCTAssertThrowsError(try NowPlayingSnapshot.decodeEvent(Data("broken".utf8)))
    }

    func testBrowserSessionAndMissingOptionalMetadata() throws {
        let data = Data(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","title":"Video","artist":null,"playing":false}}"#.utf8)
        let snapshot = try XCTUnwrap(NowPlayingSnapshot.decodeEvent(data))
        XCTAssertEqual(snapshot.parentApplicationBundleIdentifier, "com.apple.Safari")
        XCTAssertNil(snapshot.artworkData)
        XCTAssertEqual(snapshot.position(at: Date()), 0)
    }

    func testFramingHandlesPartialReadsAndMultipleUpdates() throws {
        var frames = NowPlayingFrames()
        let data = Data((event + "\n" + event + "\n").utf8)
        XCTAssertTrue(try frames.append(Data(data.prefix(40))).isEmpty)
        let decoded = try frames.append(Data(data.dropFirst(40)))
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(try NowPlayingSnapshot.decodeEvent(decoded[1])?.title, "A song")
        XCTAssertThrowsError(try frames.append(Data(repeating: 65, count: 16 * 1024 * 1024 + 1)))
    }
}
