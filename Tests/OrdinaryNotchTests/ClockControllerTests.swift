import XCTest
import Carbon
@testable import OrdinaryNotch

final class ClockControllerTests: XCTestCase {
    @MainActor func testTimerDigitsUseTheirOwnKeyCodesAndUnicode() throws {
        let keys = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                    kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for value in [0, 1, 23, 45, 59, 6, 7, 8] {
            let pairs = ClockController.durationKeyEvents(value)
            XCTAssertEqual(pairs.count, 2)
            for (pair, digit) in zip(pairs, String(format: "%02d", value).utf16) {
                for (candidate, type) in [(pair.0, CGEventType.keyDown), (pair.1, .keyUp)] {
                    let event = try XCTUnwrap(candidate)
                    XCTAssertEqual(event.type, type)
                    XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), Int64(keys[Int(digit - 48)]))
                    XCTAssertTrue(event.flags.isEmpty)
                    var text: UniChar = 0, length = 0
                    event.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &length, unicodeString: &text)
                    XCTAssertEqual(text, digit)
                }
            }
        }
    }
    @MainActor func testValidRangeIncludesSecondsAndFullDayBoundary() async throws {
        for seconds in [1, 37, 3600, 45296, 86399] {
            var draft = [0, 20, 0], started: [Int]?
            try await ClockController.startTimer(seconds: seconds, controls: .init(
                read: { draft }, enter: { draft[$0] = $1 }, start: { started = draft }))
            XCTAssertEqual(started, [seconds / 3600, seconds % 3600 / 60, seconds % 60])
        }
    }
    @MainActor func testPresetReplacesPreviousDraftBeforeStarting() async throws {
        var draft = [0, 20, 0], started: [Int]?
        try await ClockController.startTimer(seconds: 3723, controls: .init(
            read: { draft }, enter: { draft[$0] = $1 }, start: { started = draft }))
        XCTAssertEqual(started, [1, 2, 3])
    }
    @MainActor func testNoOpClockControlsNeverStartWrongDuration() async {
        var started = false
        do {
            try await ClockController.startTimer(seconds: 90, controls: .init(
                read: { [0, 20, 0] }, enter: { _, _ in }, start: { started = true }))
            XCTFail("An unchanged picker must reject the start")
        } catch { XCTAssertTrue(error is ClockController.Failure) }
        XCTAssertFalse(started)
    }
    @MainActor func testDigitsSentToPreviouslyFocusedSegmentNeverStartWrongDuration() async {
        var draft = [1, 20, 0], started = false
        do {
            try await ClockController.startTimer(seconds: 3600, controls: .init(
                read: { draft },
                // Clock can keep the hours selected when we try to clear minutes.
                enter: { _, value in draft[0] = value },
                start: { started = true }))
            XCTFail("Typing into a stale selection must not start the timer")
        } catch {
            guard case ClockController.Failure.durationNotAccepted = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(started)
    }
    @MainActor func testInvalidDurationNeverTouchesClock() async {
        for seconds in [0, -1, 86400, Int.max] {
            var touched = false
            do {
                try await ClockController.startTimer(seconds: seconds, controls: .init(
                    read: { touched = true; return [0, 0, 0] },
                    enter: { _, _ in touched = true }, start: { touched = true }))
                XCTFail("Invalid duration accepted")
            } catch { XCTAssertFalse(touched) }
        }
    }
    @MainActor func testMatchingPresetStartsWithoutRetyping() async throws {
        var started = false
        try await ClockController.startTimer(seconds: 37, controls: .init(
            read: { [0, 0, 37] }, enter: { _, _ in XCTFail("Already correct") }, start: { started = true }))
        XCTAssertTrue(started)
    }
}
