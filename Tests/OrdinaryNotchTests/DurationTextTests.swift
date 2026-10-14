import XCTest
@testable import OrdinaryNotch

final class DurationTextTests: XCTestCase {
    func testNaturalAndClockInputsPreserveExactSeconds() {
        for (input, seconds) in [("25", 1500), ("25m", 1500), ("1h 30m", 5400), ("37s", 37),
                                 ("1:30", 90), ("2:03:04", 7384), ("1 hour 2 minutes 3 seconds", 3723),
                                 ("  7M  ", 420), ("1s", 1), ("23:59:59", 86399)] {
            XCTAssertEqual(DurationText.parse(input), seconds, input)
            XCTAssertEqual(DurationText.parse(DurationText.format(seconds)), seconds)
        }
    }
    func testMalformedOrOverflowingInputsCannotStartTimers() {
        for input in ["", "0", "0s", "None", "-5", "1.5h", "1:60", "1::30", "1:2:3:4", "24h",
                      "1m garbage", "5 minutes later", "1m 2m", "1h-2m", "9999999999999999999999999h"] {
            XCTAssertNil(DurationText.parse(input), input)
        }
    }
    func testOptionalDurationAllowsCustomWholeMinutesAndNone() {
        func parse(_ text: String) -> Int? {
            DurationText.parse(text, maximum: 480 * 60, allowsNone: true, wholeMinutes: true)
        }
        XCTAssertEqual(parse("None"), 0)
        XCTAssertEqual(parse("0"), 0)
        XCTAssertEqual(parse("7"), 420)
        XCTAssertEqual(parse("1h 13m"), 4380)
        XCTAssertEqual(parse("8h"), 28800)
        for input in ["30s", "1:30", "481m", "9h", "-1", "forever"] { XCTAssertNil(parse(input), input) }
    }
}
