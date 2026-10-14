import AppKit
import ApplicationServices
import Carbon

/// Operates Apple's own controls; Clock remains the owner of timers and stopwatch data.
/// No writes are made to Clock's database or preferences.
@MainActor
final class ClockController {
    enum Action {
        case startTimer(Int), pauseTimer, resumeTimer, stopTimer
        case startStopwatch, pauseStopwatch, stopStopwatch
        var stopwatch: Bool {
            switch self { case .startStopwatch, .pauseStopwatch, .stopStopwatch: return true; default: return false }
        }
    }
    enum Failure: LocalizedError {
        case permission, unavailable, control(String), multipleTimers, duration, durationNotAccepted
        var errorDescription: String? {
            switch self {
            case .permission: return "Allow Ordinary Notch in System Settings → Privacy & Security → Accessibility, then retry."
            case .unavailable: return "Apple Clock could not be opened."
            case .control(let name): return "Clock’s \(name) control is unavailable. Open Clock and retry."
            case .multipleTimers: return "Open Clock to choose a timer when several are active."
            case .duration: return "Choose a timer duration from 00:00:01 to 23:59:59."
            case .durationNotAccepted: return "Clock did not confirm the selected duration, so the timer was not started. Open Clock and retry."
            }
        }
    }
    func perform(_ action: Action, timerCount: Int, returnTo: NSRunningApplication? = nil) async throws {
        guard AXIsProcessTrusted() else {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            throw Failure.permission
        }
        let app: NSRunningApplication
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.clock").first { app = running }
        else {
            let config = NSWorkspace.OpenConfiguration(); config.activates = false
            app = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Clock.app"), configuration: config)
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? returnTo : frontmost
        app.activate(options: [])
        defer {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
               let previousApp, previousApp.processIdentifier != app.processIdentifier {
                previousApp.activate(options: [])
            }
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.6)
        let tab = try await wait(root) { self.string($0, kAXRoleAttribute) == kAXRadioButtonRole && self.string($0, kAXDescriptionAttribute) == (action.stopwatch ? "Stopwatch" : "Timers") }
        try press(tab)
        switch action {
        case .startStopwatch: try await button(root, id: "StartStopButton", labels: ["Start", "Resume"])
        case .pauseStopwatch: try await button(root, id: "StartStopButton", labels: ["Stop", "Pause"])
        case .stopStopwatch:
            let control = try await wait(root) { self.string($0, kAXIdentifierAttribute) == "StartStopButton" }
            if ["Stop", "Pause"].contains(string(control, kAXDescriptionAttribute)) { try press(control) }
            try await button(root, id: "LapResetButton", labels: ["Reset"])
        case .startTimer(let seconds):
            // Never repurpose or overwrite an active timer.
            if timerCount > 0 { throw Failure.multipleTimers }
            try await Self.startTimer(seconds: seconds, controls: TimerControls(
                read: { try await self.durationValues(root) },
                enter: { index, value in try await self.enterDuration(root, index: index, value: value, app: app) },
                start: {
                    try await self.button(root, id: "PauseResumeButton", labels: ["Start"])
                    _ = try await self.wait(root) {
                        self.string($0, kAXIdentifierAttribute) == "PauseResumeButton"
                            && self.string($0, kAXDescriptionAttribute) == "Pause"
                    }
                }))
        case .pauseTimer, .resumeTimer, .stopTimer:
            guard timerCount == 1 else { throw Failure.multipleTimers }
            if case .stopTimer = action { try await button(root, id: "CancelButton", labels: ["Cancel", "Stop"]) }
            else if case .pauseTimer = action { try await button(root, id: "PauseResumeButton", labels: ["Pause"]) }
            else { try await button(root, id: "PauseResumeButton", labels: ["Resume", "Start"]) }
        }
    }
    private func button(_ root: AXUIElement, id: String, labels: [String]) async throws {
        let button = try await wait(root) { self.string($0, kAXIdentifierAttribute) == id && labels.contains(self.string($0, kAXDescriptionAttribute)) }
        try press(button)
    }
    struct TimerControls {
        var read: () async throws -> [Int]
        var enter: (Int, Int) async throws -> Void
        var start: () async throws -> Void
    }
    static func startTimer(seconds: Int, controls: TimerControls) async throws {
        guard DurationText.timerRange.contains(seconds) else { throw Failure.duration }
        let wanted = [seconds / 3600, seconds % 3600 / 60, seconds % 60]
        let current = try await controls.read()
        guard current.count == 3 else { throw Failure.control("duration") }
        for index in wanted.indices where current[index] != wanted[index] {
            try await controls.enter(index, wanted[index])
        }
        // AX step actions can report success without changing Clock's value.
        // Never start until the picker confirms the complete requested duration.
        guard try await controls.read() == wanted else { throw Failure.durationNotAccepted }
        try await controls.start()
    }
    private func durationSliders(_ root: AXUIElement) async throws -> [AXUIElement] {
        let picker = try await wait(root) { self.string($0, kAXIdentifierAttribute) == "TimePicker" }
        let sliders = nodes(picker).filter { string($0, kAXRoleAttribute) == kAXSliderRole }
        guard sliders.count == 3 else { throw Failure.control("duration") }
        return sliders
    }
    private func durationValues(_ root: AXUIElement) async throws -> [Int] {
        try await durationSliders(root).map { slider in
            let raw = attribute(slider, kAXValueAttribute)
            guard let value = (raw as? NSNumber)?.intValue
                ?? Int((raw as? String ?? "").prefix(while: { $0.isNumber })) else { throw Failure.control("duration") }
            return value
        }
    }
    private func enterDuration(_ root: AXUIElement, index: Int, value: Int, app: NSRunningApplication) async throws {
        // Clock accepts typed digits, but its AX increment/decrement actions can be no-ops.
        // Re-read the picker each time because SwiftUI replaces elements after editing.
        let slider = try await durationSliders(root)[index]
        guard let position = attribute(slider, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(slider, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw Failure.control("duration")
        }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0 else {
            throw Failure.control("duration")
        }
        func post(_ event: CGEvent?, mouse: Bool = false) throws {
            guard let event, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                throw Failure.control("duration")
            }
            event.flags = []
            if mouse {
                // Clock needs normal WindowServer hit testing to select a segment.
                // A click posted directly to its PID leaves the previous segment
                // focused, so the following digits edit the wrong part of the time.
                event.post(tap: .cghidEventTap)
            } else {
                event.postToPid(app.processIdentifier)
            }
        }
        let point = CGPoint(x: origin.x + dimensions.width / 2, y: origin.y + dimensions.height / 2)
        try post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left), mouse: true)
        try post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left), mouse: true)
        var selected = false
        for _ in 0..<10 {
            if try await durationIsSelected(root, index: index) { selected = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard selected else { throw Failure.control("duration selection") }
        for (down, up) in Self.durationKeyEvents(value) {
            guard try await durationIsSelected(root, index: index) else { throw Failure.control("duration selection") }
            try post(down)
            try post(up)
            try await Task.sleep(for: .milliseconds(80))
        }
        for _ in 0..<10 {
            if try await durationValues(root)[index] == value { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Failure.durationNotAccepted
    }
    private func durationIsSelected(_ root: AXUIElement, index: Int) async throws -> Bool {
        let slider = try await durationSliders(root)[index]
        // Clock's AXFocusedUIElement can remain on the previous segment even
        // after clicking another one. AXSelected tracks the actual digit target.
        return (attribute(slider, kAXSelectedAttribute) as? Bool) == true
    }
    /// Clock's segmented picker also reads virtual key codes. Sending every
    /// digit as key code 0 (the A key) can leave a valid preset unchanged.
    static func durationKeyEvents(_ value: Int) -> [(CGEvent?, CGEvent?)] {
        let keys = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                    kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        guard (0...59).contains(value) else { return [] }
        return String(format: "%02d", value).utf16.map { digit in
            func event(down: Bool) -> CGEvent? {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keys[Int(digit - 48)]), keyDown: down)
                var character = digit
                event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
                event?.flags = []
                return event
            }
            return (event(down: true), event(down: false))
        }
    }
    private func press(_ element: AXUIElement) throws {
        guard (attribute(element, kAXEnabledAttribute) as? Bool) != false,
              AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { throw Failure.control("button") }
    }
    private func wait(_ root: AXUIElement, matching predicate: (AXUIElement) -> Bool) async throws -> AXUIElement {
        for _ in 0..<25 {
            if let node = nodes(root).first(where: predicate) { return node }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw Failure.control("requested")
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func string(_ element: AXUIElement, _ name: String) -> String { attribute(element, name) as? String ?? "" }
    private func nodes(_ root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = [], pending = [(root, 0)]
        while let (node, depth) = pending.popLast(), result.count < 400 {
            result.append(node)
            if depth < 15, let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.reversed().map { ($0, depth + 1) })
            }
        }
        return result
    }
}
