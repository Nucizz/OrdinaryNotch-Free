import XCTest
import SwiftUI
@testable import OrdinaryNotch

final class ActivityLayoutTests: XCTestCase {
    @MainActor func testEveryCombinationUsesTopTwoAndKeepsPhysicalNotchCentered() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = NotchViewModel(preferences: PreferencesViewModel(defaults: defaults), isPreview: true)
        for mask in 0..<16 {
            model.music.hasTrack = mask & 1 != 0
            model.clock.timers = mask & 2 != 0 ? [AppleTimer(id: "fixture", title: "Timer", duration: 300, remaining: 300, deadline: nil, state: 2)] : []
            model.clock.stopwatch = AppleStopwatch(elapsed: mask & 4 != 0 ? 20 : 0)
            model.codexMonitor.activity = CodexActivity(title: "Test", detail: "Test", state: mask & 8 != 0 ? "running" : "idle", updatedAt: model.now)
            let active: [CompactActivity] = [CompactActivity.media, .timer, .stopwatch, .codex].enumerated()
                .filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            let expected = [CompactActivity.timer, .stopwatch, .codex, .media].filter { active.contains($0) }.prefix(2).map { $0 }
            let layout = model.compactLayout
            XCTAssertEqual(model.compactActivities, expected, "mask \(mask)")
            XCTAssertEqual(layout.placements.map(\.activity), expected)
            XCTAssertEqual(layout.placements.map(\.priority), Array(expected.indices))
            XCTAssertEqual(-layout.width / 2 + layout.wingExtent + model.notchWidth / 2, 0, accuracy: 0.001)
            XCTAssertEqual(model.surfaceOffset, 0)
            if mask == 0 { XCTAssertEqual(layout.width, model.notchWidth) }
            if expected.count == 1 { XCTAssertEqual(layout.leftWidth, 20) }
            for placement in layout.placements {
                let primarySide: CompactActivityLayout.Side = expected.count == 2
                    ? (placement.priority == 0 ? .left : .right) : (placement.activity == .media ? .left : .right)
                let secondarySide: CompactActivityLayout.Side = expected.count == 2
                    ? primarySide : (primarySide == .left ? .right : .left)
                XCTAssertEqual(placement.primary.side, primarySide)
                XCTAssertEqual(placement.secondary!.side, secondarySide)
                for position in [placement.primary, placement.secondary].compactMap { $0 } {
                    if position.side == .left {
                        XCTAssertLessThanOrEqual(position.offset + position.width / 2, -model.notchWidth / 2)
                    } else {
                        XCTAssertGreaterThanOrEqual(position.offset - position.width / 2, model.notchWidth / 2)
                    }
                }
            }
        }
    }
    @MainActor func testExtraClockWidthGrowsBothWingsEquallyForSingleActivity() {
        let model = NotchViewModel(isPreview: true)
        model.music.hasTrack = true
        let mediaExtent = model.compactLayout.wingExtent
        model.music.hasTrack = false
        model.clock.stopwatch = AppleStopwatch(elapsed: 60)
        let layout = model.compactLayout
        XCTAssertGreaterThan(layout.wingExtent, mediaExtent)
        XCTAssertEqual(layout.width, model.notchWidth + 2 * layout.wingExtent)
    }
    @MainActor func testPairedCodeUsesTextWidthWithoutAnEmptyTimerSlot() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = NotchViewModel(preferences: PreferencesViewModel(defaults: defaults), isPreview: true)
        model.compactHeight = 38
        model.music.hasTrack = true
        model.codexMonitor.activity = CodexActivity(title: "Test", detail: "", state: "running", updatedAt: model.now, startedAt: model.now.addingTimeInterval(-8))
        XCTAssertEqual(model.compactActivities, [.codex, .media])
        let pairedCode = try XCTUnwrap(model.compactLayout.placements.first)
        XCTAssertEqual(pairedCode.secondary!.width, 12)
        XCTAssertLessThan(pairedCode.primary.width, 25)
        let shortDurationWidth = pairedCode.primary.width
        XCTAssertEqual(model.compactLayout.leftWidth, 12 + 6 + shortDurationWidth)
        model.codexMonitor.activity.startedAt = model.now.addingTimeInterval(-10921)
        XCTAssertGreaterThan(try XCTUnwrap(model.compactLayout.placements.first).primary.width, shortDurationWidth)
        model.music.hasTrack = false
        XCTAssertEqual(try XCTUnwrap(model.compactLayout.placements.first).secondary!.width, 26)
        model.codexMonitor.activity.startedAt = model.now.addingTimeInterval(-8)
        XCTAssertEqual(try XCTUnwrap(model.compactLayout.placements.first).primary.width, shortDurationWidth)
        let shortNotch = model.compactWidth
        model.codexMonitor.activity.startedAt = model.now.addingTimeInterval(-10921)
        XCTAssertGreaterThan(model.compactWidth, shortNotch)
    }
    @MainActor func testActivityPositionsStayOutsideNotchAcrossReorderingAndSplitting() throws {
        let suite = "OrdinaryNotch.activity-motion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = NotchViewModel(preferences: PreferencesViewModel(defaults: defaults), isPreview: true)
        model.music.hasTrack = true
        model.music.isPlaying = true
        model.clock.timers = [AppleTimer(id: "fixture", title: "Timer", duration: 300, remaining: 300, deadline: nil, state: 2)]
        for order in [["media", "timer"], ["timer", "media"]] {
            model.preferences.values.activityOrder = order
            let layout = model.compactLayout
            let left = try XCTUnwrap(layout.placements.first)
            let right = try XCTUnwrap(layout.placements.last)
            XCTAssertEqual(left.activity.rawValue, order[0])
            XCTAssertEqual(right.activity.rawValue, order[1])
            XCTAssertEqual(left.primary.side, .left)
            XCTAssertEqual(left.secondary!.side, .left)
            XCTAssertEqual(right.primary.side, .right)
            XCTAssertEqual(right.secondary!.side, .right)
            for placement in layout.placements {
                let parts = [placement.primary, placement.secondary].compactMap { $0 }.sorted { $0.offset < $1.offset }
                if placement.activity == .media {
                    XCTAssertLessThan(placement.primary.offset, placement.secondary!.offset)
                } else {
                    XCTAssertGreaterThan(placement.primary.offset, placement.secondary!.offset)
                }
                XCTAssertEqual(parts[1].offset - parts[1].width / 2 - parts[0].offset - parts[0].width / 2, 6, accuracy: 0.001)
                if placement.priority == 0 {
                    XCTAssertEqual(parts[0].offset - parts[0].width / 2, -layout.width / 2 + NotchGeometry.compactOuterPadding, accuracy: 0.001)
                    XCTAssertLessThanOrEqual(parts[1].offset + parts[1].width / 2, -model.notchWidth / 2)
                } else {
                    XCTAssertEqual(parts[1].offset + parts[1].width / 2, layout.width / 2 - NotchGeometry.compactOuterPadding, accuracy: 0.001)
                    XCTAssertGreaterThanOrEqual(parts[0].offset - parts[0].width / 2, model.notchWidth / 2)
                }
            }
        }
        model.clock.timers = []
        XCTAssertEqual(model.compactActivities, [.media])
        let media = try XCTUnwrap(model.compactLayout.placements.first)
        XCTAssertEqual(media.primary.side, .left)
        XCTAssertEqual(media.secondary!.side, .right)
        XCTAssertEqual(media.primary.offset + media.primary.width / 2, -model.notchWidth / 2, accuracy: 0.001)
        XCTAssertEqual(media.secondary!.offset - media.secondary!.width / 2, model.notchWidth / 2, accuracy: 0.001)
    }
    @MainActor func testPrioritySkipsHiddenAndInactiveActivitiesAndSurvivesRelaunch() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesViewModel(defaults: defaults)
        preferences.values.activityOrder = ["codex", "stopwatch", "media", "timer"]
        let model = NotchViewModel(preferences: preferences, isPreview: true)
        model.music.hasTrack = true
        model.clock.stopwatch = AppleStopwatch(elapsed: 20)
        model.clock.timers = [AppleTimer(id: "fixture", title: "Timer", duration: 300, remaining: 300, deadline: nil, state: 2)]
        model.codexMonitor.activity = CodexActivity(title: "Test", detail: "", state: "running", updatedAt: model.now)
        XCTAssertEqual(model.compactActivities, [.codex, .stopwatch])
        preferences.setActivity(.codex, visible: false)
        XCTAssertEqual(model.compactActivities, [.stopwatch, .media])
        model.clock.stopwatch = AppleStopwatch(elapsed: 0)
        XCTAssertEqual(model.compactActivities, [.media, .timer])
        preferences.values.showPausedMedia = false
        XCTAssertEqual(model.compactActivities, [.timer])
        model.music.isPlaying = true
        XCTAssertEqual(model.compactActivities, [.media, .timer])
        preferences.moveActivity(.timer, by: -1)
        XCTAssertEqual(model.compactActivities, [.timer, .media])
        let restored = PreferencesViewModel(defaults: defaults)
        XCTAssertEqual(restored.values.orderedActivities, [.codex, .stopwatch, .timer, .media])
        XCTAssertEqual(restored.values.hiddenActivities, ["codex"])
    }
    @MainActor func testRenderBalancedWingsWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["ORDINARY_WING_PREVIEW"] else {
            throw XCTSkip("Optional compact wing previews")
        }
        let suite = "OrdinaryNotch.wing-preview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = NotchViewModel(preferences: PreferencesViewModel(defaults: defaults), isPreview: true)
        model.preferences.values.reduceMotion = true
        model.notchWidth = 185
        model.compactHeight = 32
        model.music.hasTrack = true; model.music.isPlaying = true
        model.codexMonitor.activity = CodexActivity(title: "Preview", detail: "", state: "running", updatedAt: model.now,
                                                   startedAt: model.now.addingTimeInterval(-93784))
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for style in NotchStyle.allCases {
            model.displayStyle = style
            for paired in [false, true] {
                model.preferences.values.hiddenActivities = paired ? [] : ["media"]
                XCTAssertEqual(model.compactLayout.mainWidth, model.reservedNotchWidth + 2 * model.compactLayout.wingExtent)
                XCTAssertEqual(model.surfaceOffset, model.compactLayout.detachedSpan / 2)
                let host = NSHostingView(rootView: NotchView(model: model)
                    .frame(width: model.canvasSize.width, height: model.canvasSize.height)
                    .transaction { $0.disablesAnimations = true; $0.animation = nil })
                host.frame = CGRect(origin: .zero, size: model.canvasSize)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(style.rawValue)-\(paired ? "pair" : "single").png"))
            }
        }
    }
    func testElapsedStopsAtCompletionAndRestartsPerTurn() throws {
        let start = #"{"timestamp":"2026-09-16T04:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"# + "\n"
        let end = #"{"timestamp":"2026-09-16T04:02:00Z","type":"event_msg","payload":{"type":"task_complete"}}"# + "\n"
        let now = ISO8601DateFormatter().date(from: "2026-09-16T04:02:30Z")!
        let working = CodexSessionStatus.parse(Data(start.utf8))
        XCTAssertEqual(working.activity(title: "Test", now: now).elapsed(at: now), 150)
        let finished = CodexSessionStatus.parse(Data(end.utf8), continuing: working)
        XCTAssertEqual(finished.activity(title: "Test", now: now).elapsed(at: now), 120)
        let restart = start.replacingOccurrences(of: "04:00:00", with: "04:02:20")
        let resumed = CodexSessionStatus.parse(Data(restart.utf8), continuing: finished)
        XCTAssertEqual(resumed.activity(title: "Test", now: now).elapsed(at: now), 10)
    }
    func testUsageUsesReportedWindowAndMissingIsNotZero() throws {
        let date = Date()
        let usage = try XCTUnwrap(CodexUsage.parse(["primary": ["used_percent": 33.0, "window_minutes": 10080, "resets_at": 2000.0]], at: date))
        XCTAssertEqual(usage.windows.count, 1)
        XCTAssertEqual(usage.windows[0].remaining, 67)
        XCTAssertEqual(usage.windows[0].label, "Weekly")
        XCTAssertEqual(usage.windows[0].resetsAt, Date(timeIntervalSince1970: 2000))
        XCTAssertNil(CodexUsage.parse(["primary": NSNull()], at: date))
    }
}
