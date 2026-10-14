import XCTest
@testable import OrdinaryNotch

final class LockScreenActivityActionTests: XCTestCase {
    @MainActor private final class Fixture {
        var context = LockScreenActivityActions.Context(lock: .init(locked: true, currentConsoleUser: true), enabled: true, sessionAvailable: true)
        var snapshot = LockScreenActivitySnapshot.preview
        var commands: [LockScreenActivityAction.MediaCommand] = []
        var outputs: [AudioOutput.Device] = []
        var seeks: [Double] = []
        var opened: [(String, Bool)] = []
        var time: TimeInterval = 0
        lazy var actions = LockScreenActivityActions(context: { self.context }, snapshot: { self.snapshot },
            media: { self.commands.append($0) }, open: { self.opened.append(($0, $1)) },
            output: { self.outputs.append($0); return true }, seek: { self.seeks.append($0); _ = $1 }, uptime: { self.time })
        var media: MusicContentIdentity { snapshot.rows[0].media!.identity }
    }

    @MainActor func testSeekingClampsAndRejectsReplacedTracksLiveMediaAndUnavailableSessions() {
        let f = Fixture()
        for seconds: Double in [42, -10, 500, .nan, .infinity] {
            f.actions.perform(.seek(seconds, f.media))
        }
        XCTAssertEqual(f.seeks, [42, 0, 210])
        XCTAssertTrue(f.opened.isEmpty)
        for blocked in 0..<7 {
            let f = Fixture(), identity = f.media
            switch blocked {
            case 0: f.context.lock = .init(locked: false, currentConsoleUser: true)
            case 1: f.context.lock = .init(locked: true, currentConsoleUser: false)
            case 2: f.context.enabled = false
            case 3: f.context.sessionAvailable = false
            case 4: f.snapshot.rows.removeFirst()
            case 5: f.snapshot.rows[0].media?.duration = 0
            default: f.snapshot.rows[0].media?.duration = .infinity
            }
            f.actions.perform(.seek(20, identity))
            XCTAssertTrue(f.seeks.isEmpty)
        }
    }

    @MainActor func testOutputSwitchesWhileLockedAndRejectsStaleOrUnavailableSessions() {
        let device = AudioOutput.Device(id: 2, uid: "airpods", route: .init(name: "AirPods Pro", symbol: "airpodspro"), selected: false)
        let f = Fixture()
        XCTAssertTrue(f.actions.selectOutput(device, for: f.media))
        XCTAssertEqual(f.outputs, [device])
        XCTAssertTrue(f.opened.isEmpty, "Output routing never launches an app or waits for unlock")
        XCTAssertNil(f.actions.message)
        for blocked in 0..<5 {
            let f = Fixture(), identity = f.media
            switch blocked {
            case 0: f.context.lock = .init(locked: false, currentConsoleUser: true)
            case 1: f.context.lock = .init(locked: true, currentConsoleUser: false)
            case 2: f.context.enabled = false
            case 3: f.context.sessionAvailable = false
            default: f.snapshot.rows.removeFirst()
            }
            XCTAssertFalse(f.actions.selectOutput(device, for: identity))
            XCTAssertTrue(f.outputs.isEmpty)
        }
    }

    @MainActor func testMediaWorksOnlyForCurrentTrackInAnEnabledLockedSession() {
        let f = Fixture(), identity = Fixture().media
        for command: LockScreenActivityAction.MediaCommand in [.previous, .playpause, .next] {
            f.actions.perform(.media(command, identity))
        }
        XCTAssertEqual(f.commands, [.previous, .playpause, .next])
        XCTAssertTrue(f.opened.isEmpty)
        f.snapshot.rows.removeFirst()
        f.actions.perform(.media(.playpause, identity))
        XCTAssertEqual(f.commands.count, 3, "A missing/replaced track must not launch the default player")
        for blocked in 0..<4 {
            let f = Fixture()
            switch blocked {
            case 0: f.context.lock = .init(locked: false, currentConsoleUser: true)
            case 1: f.context.lock = .init(locked: true, currentConsoleUser: false)
            case 2: f.context.enabled = false
            default: f.context.sessionAvailable = false
            }
            f.actions.perform(.media(.next, identity))
            f.actions.perform(.open("code"))
            XCTAssertTrue(f.commands.isEmpty)
            XCTAssertNil(f.actions.message)
        }
        XCTAssertNotNil(NowPlayingClient.commandNumber(LockScreenActivityAction.MediaCommand.next.rawValue))
        XCTAssertNotNil(NowPlayingClient.commandNumber(LockScreenActivityAction.MediaCommand.previous.rawValue))
    }

    @MainActor func testNavigationWaitsForUnlockAndRunsOnlyOnce() {
        for id in ["code", "timer", "stopwatch"] {
            let f = Fixture()
            XCTAssertNotNil(f.actions.perform(.open(id)))
            f.actions.update()
            XCTAssertTrue(f.opened.isEmpty)
            f.context.lock = .init(locked: false, currentConsoleUser: true)
            f.actions.update(); f.actions.update()
            XCTAssertEqual(f.opened.map(\.0), [id])
            XCTAssertFalse(f.opened[0].1)
            XCTAssertNil(f.actions.message)
        }
    }

    @MainActor func testPendingNavigationIsCancelledOnSleepUserSwitchExpiryPreferenceOrActivityRemoval() {
        for change in 0..<7 {
            let f = Fixture()
            f.actions.perform(.open("code"))
            switch change {
            case 0: f.context.sessionAvailable = false
            case 1: f.context.lock = .init(locked: true, currentConsoleUser: false)
            case 2: f.time = 61
            case 3: f.context.enabled = false
            case 4: f.snapshot.rows.removeAll { $0.id == "code" }
            case 5: f.actions.perform(.cancelOpen)
            default: f.actions.perform(.open("timer")) // Last explicit selection wins.
            }
            f.actions.update()
            f.context = .init(lock: .init(locked: false, currentConsoleUser: true), enabled: true, sessionAvailable: true)
            f.actions.update()
            XCTAssertEqual(f.opened.map(\.0), change == 6 ? ["timer"] : [])
            XCTAssertNil(f.actions.message)
        }
    }

    @MainActor func testReviewRevalidatesThePendingRequestAfterUnlock() {
        for resolved in [false, true] {
            let f = Fixture()
            f.snapshot.rows[1].code = .init(provider: "Codex", account: "Work", needsInput: true, statusSymbol: "hand.raised.fill")
            XCTAssertNotNil(f.actions.perform(.review("code")))
            f.actions.update()
            XCTAssertTrue(f.opened.isEmpty)
            if resolved { f.snapshot.rows[1].code = LockScreenActivitySnapshot.preview.rows[1].code }
            f.context.lock = .init(locked: false, currentConsoleUser: true)
            f.actions.update()
            XCTAssertEqual(f.opened.count, resolved ? 0 : 1)
            if !resolved { XCTAssertTrue(f.opened[0].1) }
        }
        let f = Fixture()
        XCTAssertNil(f.actions.perform(.review("code")), "A running task without a request has nothing to approve")
        XCTAssertNil(f.actions.perform(.open("media")), "Locked media cannot launch an app")
        XCTAssertNil(f.actions.perform(.open("unknown")))
        f.snapshot.rows[1].code = .init(provider: "Codex", account: "Work", needsInput: true, statusSymbol: "hand.raised.fill", canOpen: false, canReview: false)
        XCTAssertNil(f.actions.perform(.open("code")))
        XCTAssertNil(f.actions.perform(.review("code")), "Do not offer an action without a task link or a pending request")
    }
}
