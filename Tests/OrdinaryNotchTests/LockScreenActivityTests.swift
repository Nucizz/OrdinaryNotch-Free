import AppKit
import SwiftUI
import XCTest
@testable import OrdinaryNotch

final class LockScreenActivityTests: XCTestCase {
    func testPreferenceMigrationRoundTripAndUnknownMode() throws {
        XCTAssertEqual(NotchSettings().lockScreenActivity, .screen)
        XCTAssertEqual(try JSONDecoder().decode(NotchSettings.self, from: Data("{}".utf8)).lockScreenActivity, .screen)
        for mode in LockScreenActivityMode.allCases {
            var settings = NotchSettings(); settings.lockScreenActivity = mode
            let decoded = try JSONDecoder().decode(NotchSettings.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(decoded.lockScreenActivity, mode)
            XCTAssertEqual(decoded.normalized().lockScreenActivity, mode)
        }
        XCTAssertEqual(try JSONDecoder().decode(NotchSettings.self, from: Data(#"{"lockScreenActivity":"future-mode"}"#.utf8)).lockScreenActivity, .none)
        XCTAssertEqual(try JSONDecoder().decode(NotchSettings.self, from: Data(#"{"lockScreenActivity":42}"#.utf8)).lockScreenActivity, .none)
    }
    func testOnlyCurrentLockedAwakeSessionCanShowActivity() {
        XCTAssertFalse(LockScreenActivityPolicy.allowed(lock: .init(locked: true, currentConsoleUser: true), inactiveReasons: [], displayAwake: false),
            "A sleeping display must stay hidden even when the app missed the earlier sleep notification")
        XCTAssertTrue(LockScreenActivityPolicy.allowed(lock: .init(locked: true, currentConsoleUser: true), inactiveReasons: ["lock"]))
        for locked in [false, true] {
            for current in [false, true] {
                for reasons: Set<String> in [[], ["lock"], ["display"], ["sleep"], ["session"], ["lock", "display"]] {
                    XCTAssertEqual(LockScreenActivityPolicy.allowed(lock: .init(locked: locked, currentConsoleUser: current), inactiveReasons: reasons),
                        locked && current && reasons.subtracting(["lock"]).isEmpty)
                }
            }
        }
    }
    func testLayoutStaysBetweenClockAndLoginAcrossDisplays() throws {
        for size in [CGSize(width: 1280, height: 800), CGSize(width: 1512, height: 982), CGSize(width: 1920, height: 1080), CGSize(width: 360, height: 540)] {
            for origin in [CGPoint.zero, CGPoint(x: -1920, y: -300)] {
                let screen = CGRect(origin: origin, size: size)
                let activities = LockScreenActivitySnapshot(rows: Array(repeating: LockScreenActivitySnapshot.preview.rows[0], count: 20))
                let layout = try XCTUnwrap(LockScreenActivityLayout.make(screen: screen, snapshot: activities))
                XCTAssertTrue(screen.contains(layout.frame))
                XCTAssertEqual(layout.frame.midX, screen.midX, accuracy: 0.01)
                XCTAssertEqual(layout.frame.minY - screen.minY, max(170, min(220, size.height * 0.22)), accuracy: 0.01)
                XCTAssertEqual(screen.maxY - layout.frame.maxY, max(190, size.height * 0.28), accuracy: 0.01)
                XCTAssertLessThanOrEqual(layout.frame.height, size.height - 360)
            }
        }
        XCTAssertNil(LockScreenActivityLayout.make(screen: CGRect(x: 0, y: 0, width: 1280, height: 800), snapshot: .init()))
        XCTAssertNil(LockScreenActivityLayout.make(screen: CGRect(x: 0, y: 0, width: 320, height: 480), snapshot: .preview))
    }
    func testActivityChangesKeepTheSameClockToLoginViewport() throws {
        let screen = CGRect(x: -1512, y: -200, width: 1512, height: 982)
        let single = try XCTUnwrap(LockScreenActivityLayout.make(screen: screen, snapshot: .init(rows: [LockScreenActivitySnapshot.preview.rows[1]])))
        let multiple = try XCTUnwrap(LockScreenActivityLayout.make(screen: screen, snapshot: .preview))
        XCTAssertEqual(single.frame, multiple.frame)
        XCTAssertGreaterThan(single.frame.height, LockScreenActivityLayout.previewHeight - 2)
    }
    func testHiddenLoginAreaExpandsViewportWithoutMovingTheClockBoundary() throws {
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -1920, y: -300, width: 1920, height: 1080)] {
            let visible = try XCTUnwrap(LockScreenActivityLayout.make(screen: screen, snapshot: .preview))
            let hidden = try XCTUnwrap(LockScreenActivityLayout.make(screen: screen, snapshot: .preview, loginAreaVisible: false))
            XCTAssertEqual(hidden.frame.maxY, visible.frame.maxY, accuracy: 0.01)
            XCTAssertEqual(hidden.frame.width, visible.frame.width)
            XCTAssertGreaterThan(hidden.frame.height, visible.frame.height + 100)
            XCTAssertTrue(screen.contains(hidden.frame))
        }
    }
    @MainActor func testLoginAreaVisibilityMovesPanelAndDoesNotExpandDuringUnlock() async throws {
        var lock = SessionLockSnapshot(locked: true, currentConsoleUser: true)
        let space = Space()
        let controller = LockScreenActivityController(readLock: { lock }, getSpace: { space }, displayAwake: { _ in true })
        defer { controller.hide() }
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        controller.update(visible: true, snapshot: .preview, screen: screen, reduceMotion: true)
        for _ in 0..<100 where space.reply == nil { await Task.yield() }
        space.finish(true)
        for _ in 0..<50 where controller.panel?.isVisible != true { await Task.yield() }
        let panel = try XCTUnwrap(controller.panel)
        let initial = panel.frame
        controller.loginAreaChanged(visible: false)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertLessThan(panel.frame.minY, initial.minY)
        XCTAssertGreaterThan(panel.frame.height, initial.height)
        controller.loginAreaChanged(visible: true)
        XCTAssertEqual(panel.frame, initial)
        controller.loginAreaChanged(visible: false)
        controller.loginAreaChanged(visible: true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(panel.frame, initial, "A quick hide/show must not lower the cards afterward")
        controller.loginAreaChanged(visible: false)
        lock.locked = false
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.frame, initial, "Unlock should dismiss instead of expanding into the login area")
    }
    @MainActor func testSnapshotShowsAllActivitiesAndTaskDetailsWithoutUnlocking() throws {
        let name = "OrdinaryNotch.lock-activity.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = PreferencesViewModel(defaults: defaults)
        let model = NotchViewModel(preferences: preferences, isPreview: true)
        let now = Date(timeIntervalSince1970: 1000)
        model.clock.timers = [AppleTimer(id: "1", title: "Focus", duration: 300, remaining: 150, deadline: nil, state: 2),
                              AppleTimer(id: "2", title: "Tea", duration: 60, remaining: 30, deadline: nil, state: 2)]
        var task = CodexActivity(title: "Build", detail: "Private tool output", state: "running", updatedAt: now)
        task.taskName = "Compile app"; task.project = "/private/project"; task.startedAt = now.addingTimeInterval(-45)
        model.codexMonitor.setPreviewTasks([CodeTask(id: "test", provider: .codex, activity: task)])
        var snapshot = LockScreenActivitySnapshot.read(model, at: now)
        XCTAssertEqual(snapshot.rows.map(\.kind), [.timer, .codex, .timer], "Give different activities a row before additional timers")
        XCTAssertEqual(snapshot.rows[0].value, "02:30")
        XCTAssertEqual(snapshot.rows[0].progress, 0.5)
        XCTAssertEqual(snapshot.rows[1].title, "Build", "Use the saved chat title instead of the latest user message")
        XCTAssertEqual(snapshot.rows[1].subtitle, "")
        XCTAssertEqual(snapshot.rows[1].code?.provider, "GPT")
        XCTAssertEqual(snapshot.rows[1].value, "00:45")
        XCTAssertTrue(snapshot.rows[1].code?.detail.contains("Private tool output") == true)
        XCTAssertFalse(snapshot.rows[1].code?.detail.contains("/private/project") == true)
        preferences.values.hiddenActivities = ["timer", "codex"]
        snapshot = LockScreenActivitySnapshot.read(model, at: now)
        XCTAssertEqual(snapshot.rows.map(\.kind), [.timer, .codex, .timer])
    }
    @MainActor func testDetailedSnapshotTracksMediaProgressStopwatchAndApprovalState() throws {
        let name = "OrdinaryNotch.lock-details.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = NotchViewModel(preferences: PreferencesViewModel(defaults: defaults), isPreview: true)
        let now = Date(timeIntervalSince1970: 1000)
        model.music.hasTrack = true; model.music.title = "Song"; model.music.artist = "Artist"
        model.music.source = "Music"; model.music.isPlaying = true
        model.music.position = 80; model.music.duration = 200
        let artwork = NSImage(size: NSSize(width: 64, height: 64))
        model.music.artwork = artwork
        model.clock.stopwatch = AppleStopwatch(elapsed: 120, started: now.addingTimeInterval(-10), laps: [30, 40])
        var activity = CodexActivity(title: "Task", detail: "Request details visible while locked", state: "running", updatedAt: now)
        activity.attention = "approval"
        model.codexMonitor.setPreviewTasks([CodeTask(id: "waiting", provider: .codex, activity: activity)])
        let snapshot = LockScreenActivitySnapshot.read(model, at: now)
        let media = try XCTUnwrap(snapshot.rows.first { $0.kind == .media })
        XCTAssertEqual(media.media?.isPlaying, true)
        XCTAssertEqual(media.media?.identity, model.music.contentIdentity)
        XCTAssertEqual(media.media?.remaining, "−02:00")
        XCTAssertEqual(media.progress, 0.4)
        XCTAssertTrue(media.artwork === artwork)
        let stopwatch = try XCTUnwrap(snapshot.rows.first { $0.kind == .stopwatch })
        XCTAssertEqual(stopwatch.value, "02:10")
        XCTAssertEqual(stopwatch.clockDetail, "2 laps · Last 00:40")
        XCTAssertEqual(snapshot.rows.first { $0.kind == .codex }?.code?.needsInput, true)
        XCTAssertEqual(snapshot.rows.first { $0.kind == .codex }?.code?.detail, "Request details visible while locked")
    }

    @MainActor func testScreenPlayerKeepsPausedTracksWhileNotchFollowsItsPreference() throws {
        let name = "OrdinaryNotch.lock-paused-media.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = PreferencesViewModel(defaults: defaults)
        preferences.values.lockScreenActivity = .screen
        let model = NotchViewModel(preferences: preferences, isPreview: true)
        model.music.hasTrack = true
        model.music.title = "Song"
        model.clock.timers = [AppleTimer(id: "focus", title: "Focus", duration: 300, remaining: 150, deadline: nil, state: 2)]
        for showPaused in [false, true] {
            preferences.values.showPausedMedia = showPaused
            for isPlaying in [false, true, false] {
                model.music.isPlaying = isPlaying
                let rows = LockScreenActivitySnapshot.read(model, at: Date()).rows
                let media = try XCTUnwrap(rows.first { $0.kind == .media })
                XCTAssertEqual(media.media?.isPlaying, isPlaying)
                XCTAssertEqual(CompactActivity.media.isActive(in: model), isPlaying || showPaused)
                XCTAssertTrue(rows.contains { $0.kind == .timer })
            }
        }
        model.music.hasTrack = false
        XCTAssertFalse(LockScreenActivitySnapshot.read(model, at: Date()).rows.contains { $0.kind == .media })
        model.clock.timers = []
        XCTAssertTrue(LockScreenActivitySnapshot.read(model, at: Date()).rows.isEmpty)
    }

    func testReadOnlyDetailsIncludeQuestionChoicesAndDescriptions() {
        var activity = CodexActivity(title: "Task", detail: "Running tests", state: "running", updatedAt: Date())
        activity.project = "/project/App"; activity.model = "gpt-6-astra"
        let task = CodeTask(id: "task", provider: .codex, activity: activity)
        let prompt = AgentPrompt(id: "request", task: task, kind: .question, requestID: "q",
            questions: [.init(id: "choice", title: "Which target?", options: ["Mac", "Phone"], descriptions: ["Desktop app"])],
            detail: "Running tests")
        XCTAssertEqual(LockScreenActivitySnapshot.codeDetail(activity: activity, prompt: prompt),
            "Running tests\nWhich target?\nMac — Desktop app\nPhone")
    }

    func testRoutineStatusAndHandoffInstructionsAreOmittedFromDetails() {
        for detail in ["Working", "Working in Codex", " Working in Codex\n"] {
            let activity = CodexActivity(title: "Camera controls", detail: detail, state: "running", updatedAt: Date())
            let task = CodeTask(id: "task", provider: .codex, activity: activity)
            let handoff = AgentPrompt(id: "handoff", task: task, kind: .handoff, requestID: "q",
                detail: "Open this task to review and respond to its pending request.")
            XCTAssertEqual(LockScreenActivitySnapshot.codeDetail(activity: activity, prompt: handoff), "")
        }
    }


    @MainActor private final class Space: LockScreenSpaceDelegating {
        var calls = 0, removals = 0
        var reply: CheckedContinuation<Bool, Never>?
        func delegate(_ window: NSWindow) async -> Bool {
            calls += 1
            return await withCheckedContinuation { reply = $0 }
        }
        func undelegate(_ window: NSWindow) { removals += 1 }
        func finish(_ success: Bool) { reply?.resume(returning: success); reply = nil }
    }
    @MainActor func testPendingPlacementCannotAppearAfterUnlockOrSettingOff() async {
        for unlock in [false, true] {
            _ = NSApplication.shared
            var locked = true
            let space = Space()
            let controller = LockScreenActivityController(readLock: { .init(locked: locked, currentConsoleUser: true) }, getSpace: { space }, displayAwake: { _ in true })
            let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
            controller.update(visible: true, snapshot: .preview, screen: frame)
            for _ in 0..<100 where space.reply == nil { await Task.yield() }
            XCTAssertEqual(space.calls, 1)
            XCTAssertFalse(controller.panel?.isVisible ?? true)
            if unlock { locked = false }
            else { controller.update(visible: false, snapshot: .init(), screen: frame) }
            space.finish(true)
            for _ in 0..<20 { await Task.yield() }
            XCTAssertFalse(controller.panel?.isVisible ?? true)
            XCTAssertGreaterThan(space.removals, 0)
            controller.hide()
        }
    }
    @MainActor func testPanelAcceptsOnlyPointerInputAfterDelegationAndClosesWhenActivitiesFinish() async throws {
        _ = NSApplication.shared
        let space = Space()
        let controller = LockScreenActivityController(readLock: { .init(locked: true, currentConsoleUser: true) }, getSpace: { space }, displayAwake: { _ in true })
        defer { controller.hide() }
        var actions = 0
        controller.onAction = { _ in actions += 1; return nil }
        var outputSelections = 0
        let device = AudioOutput.Device(id: 1, uid: "speakers", route: .init(name: "MacBook Speakers", symbol: "laptopcomputer"), selected: true)
        let identity = LockScreenActivitySnapshot.preview.rows[0].media!.identity
        controller.onSelectOutput = { _, _ in outputSelections += 1; return true }
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        controller.update(visible: true, snapshot: .preview, screen: screen)
        controller.perform(.open("code"))
        XCTAssertEqual(actions, 0, "Hidden or unconfirmed windows cannot act")
        XCTAssertFalse(controller.selectOutput(device, for: identity))
        for _ in 0..<100 where space.reply == nil { await Task.yield() }
        space.finish(true)
        for _ in 0..<50 where controller.panel?.isVisible != true { await Task.yield() }
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey); XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(panel.title, "Ordinary Notch")
        XCTAssertEqual(panel.sharingType, .none)
        controller.perform(.open("code"))
        XCTAssertEqual(actions, 1)
        XCTAssertTrue(controller.selectOutput(device, for: identity))
        XCTAssertEqual(outputSelections, 1)
        controller.update(visible: true, snapshot: .init(), screen: screen)
        XCTAssertFalse(panel.isVisible)
        controller.perform(.open("code"))
        XCTAssertEqual(actions, 1)
        XCTAssertFalse(controller.selectOutput(device, for: identity))
        XCTAssertEqual(outputSelections, 1)
    }
    @MainActor func testNoPlacementWhenUnlockedOtherUserOrPrivateSpaceUnavailable() async {
        for lock in [SessionLockSnapshot(locked: false, currentConsoleUser: true), .init(locked: true, currentConsoleUser: false)] {
            let space = Space(), controller = LockScreenActivityController(readLock: { lock }, getSpace: { nil }, displayAwake: { _ in true })
            controller.update(visible: true, snapshot: .preview, screen: CGRect(x: 0, y: 0, width: 1512, height: 982))
            XCTAssertNil(controller.panel); XCTAssertEqual(space.calls, 0)
        }
        let controller = LockScreenActivityController(readLock: { .init(locked: true, currentConsoleUser: true) }, getSpace: { nil }, displayAwake: { _ in true })
        controller.update(visible: true, snapshot: .preview, screen: CGRect(x: 0, y: 0, width: 1512, height: 982))
        XCTAssertFalse(controller.panel?.isVisible ?? true)
        controller.hide()
    }
    @MainActor func testDisabledPanelDoesNotPollSessionOnPointerEvents() {
        var reads = 0
        let controller = LockScreenActivityController(readLock: {
            reads += 1; return .init(locked: false, currentConsoleUser: true)
        }, getSpace: { nil }, displayAwake: { _ in true })
        for _ in 0..<100 { controller.update(visible: false, snapshot: .init(), screen: nil) }
        XCTAssertEqual(reads, 0)
        XCTAssertNil(controller.panel)
    }
    @MainActor func testDisplaySleepingDuringPlacementCannotRevealPanel() async {
        _ = NSApplication.shared
        var awake = true
        let space = Space()
        let controller = LockScreenActivityController(readLock: { .init(locked: true, currentConsoleUser: true) },
            getSpace: { space }, displayAwake: { _ in awake })
        controller.update(visible: true, snapshot: .preview, screen: CGRect(x: 0, y: 0, width: 1512, height: 982))
        for _ in 0..<100 where space.reply == nil { await Task.yield() }
        awake = false; space.finish(true)
        for _ in 0..<50 { await Task.yield() }
        XCTAssertFalse(controller.panel?.isVisible ?? true)
        XCTAssertGreaterThan(space.removals, 0)
        controller.hide()
    }
    @MainActor func testFailedDelegationStaysHiddenAndDoesNotRetryEveryTick() async {
        _ = NSApplication.shared
        let space = Space()
        let controller = LockScreenActivityController(readLock: { .init(locked: true, currentConsoleUser: true) }, getSpace: { space }, displayAwake: { _ in true })
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        controller.update(visible: true, snapshot: .preview, screen: screen)
        for _ in 0..<100 where space.reply == nil { await Task.yield() }
        space.finish(false)
        for _ in 0..<30 { await Task.yield() }
        for _ in 0..<30 { controller.update(visible: true, snapshot: .preview, screen: screen) }
        XCTAssertEqual(space.calls, 1)
        XCTAssertFalse(controller.panel?.isVisible ?? true)
        controller.hide()
    }
    @MainActor func testUnlockScalesAndFadesImmediatelyWithoutMovingOntoDesktop() async throws {
        _ = NSApplication.shared
        var locked = true
        let space = Space()
        let controller = LockScreenActivityController(readLock: { .init(locked: locked, currentConsoleUser: true) }, getSpace: { space }, displayAwake: { _ in true })
        defer { controller.hide() }
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        controller.update(visible: true, snapshot: .preview, screen: screen)
        for _ in 0..<100 where space.reply == nil { await Task.yield() }
        space.finish(true)
        for _ in 0..<100 where controller.panel?.isVisible != true { await Task.yield() }
        locked = false
        let originalFrame = controller.panel?.frame
        controller.update(visible: false, snapshot: .init(), screen: screen, animateExit: true)
        XCTAssertTrue(controller.panel?.isVisible == true, "The fast exit begins immediately")
        XCTAssertTrue(controller.panel?.ignoresMouseEvents == true, "Exit animations never intercept input")
        XCTAssertFalse(controller.pollsForUnlock)
        XCTAssertEqual(space.removals, 0, "Never transfer a visible outgoing panel onto the desktop")
        XCTAssertEqual(controller.panel?.frame, originalFrame, "Scale the surface without resizing or reflowing its content")
        XCTAssertEqual(try XCTUnwrap(controller.panel?.contentView?.layer?.transform.m11), 0.96, accuracy: 0.001)
        // A late update with cached lock state cannot reverse the exit.
        controller.update(visible: true, snapshot: .preview, screen: screen)
        XCTAssertTrue(controller.panel?.ignoresMouseEvents == true)
        locked = true
        controller.beginLockedSession()
        controller.update(visible: true, snapshot: .preview, screen: screen)
        for _ in 0..<100 where space.reply == nil { await Task.yield() }
        space.finish(true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(controller.panel?.isVisible == true, "An old exit must not hide a newly locked activity")
        controller.update(visible: false, snapshot: .init(), screen: screen, animateExit: true)
        let exitDeadline = ContinuousClock.now + .seconds(3)
        while controller.panel?.isVisible == true && ContinuousClock.now < exitDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(controller.panel?.isVisible ?? true)
    }
    @MainActor func testVisiblePanelDetectsUnlockWithoutTheOneSecondContextPoll() async throws {
        _ = NSApplication.shared
        var locked = true
        let space = Space()
        let controller = LockScreenActivityController(readLock: { .init(locked: locked, currentConsoleUser: true) },
            getSpace: { space }, displayAwake: { _ in true })
        defer { controller.hide() }
        XCTAssertFalse(controller.pollsForUnlock)
        let detected = expectation(description: "Fast unlock observation")
        controller.onUnlock = { detected.fulfill() }
        controller.update(visible: true, snapshot: .preview, screen: CGRect(x: 0, y: 0, width: 1512, height: 982))
        for _ in 0..<100 where space.reply == nil { await Task.yield() }
        space.finish(true)
        for _ in 0..<100 where controller.panel?.isVisible != true { await Task.yield() }
        XCTAssertTrue(controller.pollsForUnlock)
        locked = false
        await fulfillment(of: [detected], timeout: 0.5)
        XCTAssertFalse(controller.pollsForUnlock)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertFalse(controller.panel?.isVisible ?? true)
        XCTAssertGreaterThan(space.removals, 0)
        XCTAssertEqual(try XCTUnwrap(controller.panel?.contentView?.layer?.transform.m11), 1, accuracy: 0.001)
    }
    @MainActor func testReduceMotionUnlockFadesWithoutScalingAndUserSwitchHidesImmediately() async throws {
        _ = NSApplication.shared
        var current = true
        let space = Space()
        let controller = LockScreenActivityController(readLock: { .init(locked: true, currentConsoleUser: current) },
            getSpace: { space }, displayAwake: { _ in true })
        defer { controller.hide() }
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        controller.update(visible: true, snapshot: .preview, screen: screen, reduceMotion: true)
        for _ in 0..<100 where space.reply == nil { await Task.yield() }
        space.finish(true)
        for _ in 0..<100 where controller.panel?.isVisible != true { await Task.yield() }
        controller.dismissForUnlock(reduceMotion: true)
        XCTAssertEqual(try XCTUnwrap(controller.panel?.contentView?.layer?.transform.m11), 1, accuracy: 0.001)
        try await Task.sleep(for: .milliseconds(140))
        XCTAssertFalse(controller.panel?.isVisible ?? true)
        controller.beginLockedSession()
        controller.update(visible: true, snapshot: .preview, screen: screen)
        for _ in 0..<100 where space.reply == nil { await Task.yield() }
        space.finish(true)
        for _ in 0..<100 where controller.panel?.isVisible != true { await Task.yield() }
        current = false; controller.checkLockState()
        XCTAssertFalse(controller.panel?.isVisible ?? true)
        XCTAssertFalse(controller.pollsForUnlock)
    }
    @MainActor func testDisplaySleepInterruptsAnAnimatedExitImmediately() async {
        _ = NSApplication.shared
        let space = Space()
        let controller = LockScreenActivityController(readLock: { .init(locked: true, currentConsoleUser: true) }, getSpace: { space }, displayAwake: { _ in true })
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        controller.update(visible: true, snapshot: .preview, screen: screen)
        for _ in 0..<100 where space.reply == nil { await Task.yield() }
        space.finish(true)
        for _ in 0..<100 where controller.panel?.isVisible != true { await Task.yield() }
        controller.hide(animated: true)
        controller.hide()
        XCTAssertFalse(controller.panel?.isVisible ?? true)
    }
    @MainActor func testAuthenticationStartsExitBeforeSessionUnlockAndNeverResumesActionsEarly() async throws {
        _ = NSApplication.shared
        var locked = true
        let space = Space()
        let controller = LockScreenActivityController(readLock: { .init(locked: locked, currentConsoleUser: true) },
            getSpace: { space }, displayAwake: { _ in true })
        defer { controller.hide() }
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        var unlocks = 0, restores = 0, actions = 0
        controller.onUnlock = { unlocks += 1 }
        controller.onRestoreAfterUnlockAttempt = { restores += 1 }
        controller.onAction = { _ in actions += 1; return nil }
        controller.update(visible: true, snapshot: .preview, screen: screen)
        for _ in 0..<100 where space.reply == nil { await Task.yield() }
        space.finish(true)
        for _ in 0..<100 where controller.panel?.isVisible != true { await Task.yield() }
        controller.beginUnlockAttempt(reduceMotion: false)
        XCTAssertTrue(controller.awaitingUnlock)
        XCTAssertEqual(try XCTUnwrap(controller.panel?.contentView?.layer?.transform.m11), 0.96, accuracy: 0.001)
        controller.perform(.open("task"))
        controller.update(visible: true, snapshot: .preview, screen: screen)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertFalse(controller.panel?.isVisible ?? true, "Hide while CGSession still reports locked")
        XCTAssertEqual(unlocks, 0); XCTAssertEqual(actions, 0)
        locked = false
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(unlocks, 1)
        XCTAssertEqual(restores, 0)
        XCTAssertFalse(controller.awaitingUnlock)
    }
    @MainActor func testFailedOrTimedOutAuthenticationRestoresActivities() async throws {
        _ = NSApplication.shared
        for timeout in [false, true] {
            let space = Space()
            let controller = LockScreenActivityController(readLock: { .init(locked: true, currentConsoleUser: true) },
                getSpace: { space }, displayAwake: { _ in true })
            defer { controller.hide() }
            let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
            var restores = 0
            controller.onRestoreAfterUnlockAttempt = { restores += 1 }
            controller.onUnlock = { XCTFail("An attempt must never grant access") }
            controller.update(visible: true, snapshot: .preview, screen: screen)
            for _ in 0..<100 where space.reply == nil { await Task.yield() }
            space.finish(true)
            for _ in 0..<100 where controller.panel?.isVisible != true { await Task.yield() }
            let id = UUID()
            controller.beginUnlockAttempt(id: id, reduceMotion: true, recoveryTimeout: timeout ? 0.15 : 2)
            controller.finishUnlockAttempt(id: UUID())
            XCTAssertTrue(controller.awaitingUnlock, "A stale face attempt cannot cancel this one")
            if timeout { try await Task.sleep(for: .milliseconds(250)) }
            else { controller.finishUnlockAttempt(id: id) }
            XCTAssertEqual(restores, 1)
            XCTAssertFalse(controller.awaitingUnlock)
            controller.update(visible: true, snapshot: .preview, screen: screen)
            for _ in 0..<100 where space.reply == nil { await Task.yield() }
            space.finish(true)
            for _ in 0..<100 where controller.panel?.isVisible != true { await Task.yield() }
            XCTAssertTrue(controller.panel?.isVisible == true)
        }
    }
    @MainActor func testRelockAndSleepCancelAuthenticationRecovery() async throws {
        _ = NSApplication.shared
        for sleeping in [false, true] {
            let controller = LockScreenActivityController(readLock: { .init(locked: true, currentConsoleUser: true) },
                getSpace: { nil }, displayAwake: { _ in true })
            controller.onRestoreAfterUnlockAttempt = { XCTFail("Old attempt must not restore a new or sleeping session") }
            controller.onUnlock = { XCTFail("Still locked") }
            let id = UUID()
            controller.beginUnlockAttempt(id: id, reduceMotion: false, recoveryTimeout: 0.1)
            if sleeping { controller.hide() }
            else { controller.beginLockedSession() }
            controller.finishUnlockAttempt(id: id)
            try await Task.sleep(for: .milliseconds(180))
            XCTAssertFalse(controller.awaitingUnlock)
        }
    }
    @MainActor func testNativeUnlockSurfaceActuallyInterpolatesScaleWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["ORDINARY_VERIFY_UNLOCK_MOTION"] == "1" else {
            throw XCTSkip("Opt-in native compositor timing check")
        }
        _ = NSApplication.shared
        var locked = true
        let space = Space()
        let controller = LockScreenActivityController(readLock: { .init(locked: locked, currentConsoleUser: true) },
            getSpace: { space }, displayAwake: { _ in true })
        defer { controller.hide() }
        controller.update(visible: true, snapshot: .preview, screen: CGRect(x: 0, y: 0, width: 1512, height: 982))
        for _ in 0..<100 where space.reply == nil { await Task.yield() }
        space.finish(true)
        try await Task.sleep(for: .milliseconds(350))
        // Authenticate while the system still reports locked, then check the
        // actual compositor frames rather than only the layer's target value.
        controller.beginUnlockAttempt(reduceMotion: false)
        var scales: [CGFloat] = []
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(16))
            if controller.panel?.isVisible == true, let scale = controller.panel?.contentView?.layer?.presentation()?.transform.m11 {
                scales.append(scale)
            }
        }
        XCTAssertTrue(scales.contains { $0 < 0.999 && $0 > 0.961 }, "The surface must animate between full size and its target, not jump: \(scales)")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(controller.panel?.isVisible ?? true)
        locked = false
    }
    @MainActor func testRenderActualPanelViewWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["ORDINARY_LOCK_ACTIVITY_PREVIEW"] else { throw XCTSkip("Opt-in lock-screen activity rendering") }
        _ = NSApplication.shared
        var snapshot = LockScreenActivitySnapshot.preview
        snapshot.rows[1].code = .init(provider: "Claude", account: "Work", needsInput: true, statusSymbol: "hand.raised.fill")
        let content = NSHostingView(rootView: LockScreenActivityView(snapshot: snapshot, lockScreenAppearance: true))
        content.sizingOptions = []
        let surface = content
        surface.wantsLayer = true
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: LockScreenActivityLayout.width, height: LockScreenActivityLayout.previewHeight), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = surface; window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false; window.backgroundColor = .clear
        defer { window.close() }
        func render(to destination: String) throws {
            surface.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(surface.bitmapImageRepForCachingDisplay(in: surface.bounds))
            surface.cacheDisplay(in: surface.bounds, to: bitmap)
            if let context = NSGraphicsContext(bitmapImageRep: bitmap), let layer = surface.layer {
                context.cgContext.translateBy(x: 0, y: surface.bounds.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                layer.render(in: context.cgContext)
            }
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: destination))
        }
        if ProcessInfo.processInfo.environment["ORDINARY_LOCK_ACTIVITY_LIVE"] == "1" {
            window.title = "Ordinary Notch Activity Preview"
            window.center(); window.orderFrontRegardless()
            NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .seconds(45))
        }
        for _ in 0..<5 { try await Task.sleep(for: .milliseconds(40)); surface.layoutSubtreeIfNeeded() }
        try render(to: path)
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        let scroll = try XCTUnwrap(scrollView(in: surface))
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertFalse(scroll.hasVerticalScroller, "Hide the scrollbar without disabling native scrolling")
        XCTAssertFalse(scroll.hasHorizontalScroller)
        XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height, "Additional cards remain available to scroll")
        document.scroll(CGPoint(x: 0, y: document.bounds.height - scroll.contentView.bounds.height))
        for _ in 0..<5 { try await Task.sleep(for: .milliseconds(40)); surface.layoutSubtreeIfNeeded() }
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0, "Native scrolling reveals the last activity")
        XCTAssertFalse(scroll.hasVerticalScroller, "Scrolling must not flash a scrollbar")
        try render(to: path + "-scrolled.png")
        window.setContentSize(NSSize(width: 296, height: 440))
        content.rootView = LockScreenActivityView(snapshot: .init(rows: [snapshot.rows[1], snapshot.rows[2]]), lockScreenAppearance: true)
        for _ in 0..<5 { try await Task.sleep(for: .milliseconds(40)); surface.layoutSubtreeIfNeeded() }
        try render(to: path + "-narrow.png")
    }
}
