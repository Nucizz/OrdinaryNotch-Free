import AppKit
import ApplicationServices

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
        case permission, unavailable, control(String), multipleTimers
        var errorDescription: String? {
            switch self {
            case .permission: return "Allow Ordinary Notch in System Settings → Privacy & Security → Accessibility, then retry."
            case .unavailable: return "Apple Clock could not be opened."
            case .control(let name): return "Clock’s \(name) control is unavailable. Open Clock and retry."
            case .multipleTimers: return "Open Clock to choose a timer when several are active."
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
            let picker = try await wait(root) { self.string($0, kAXIdentifierAttribute) == "TimePicker" }
            let sliders = nodes(picker).filter { string($0, kAXRoleAttribute) == kAXSliderRole }
            guard sliders.count == 3 else { throw Failure.control("duration") }
            for (slider, target) in zip(sliders, [seconds / 3600, (seconds % 3600) / 60, seconds % 60]) {
                try await setSlider(slider, to: target)
            }
            try await button(root, id: "PauseResumeButton", labels: ["Start"])
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
    private func setSlider(_ slider: AXUIElement, to target: Int) async throws {
        // SwiftUI's Clock picker exposes its value as a localized string and supports step actions.
        // Increment/decrement avoids relying on whether direct AXValue writes are supported.
        for _ in 0..<120 {
            let raw = attribute(slider, kAXValueAttribute)
            let current = (raw as? NSNumber)?.intValue ?? Int((raw as? String ?? "").prefix(while: { $0.isNumber }))
            guard let current else { throw Failure.control("duration") }
            if current == target { return }
            let action = current < target ? kAXIncrementAction : kAXDecrementAction
            guard AXUIElementPerformAction(slider, action as CFString) == .success else { throw Failure.control("duration") }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        throw Failure.control("duration")
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
