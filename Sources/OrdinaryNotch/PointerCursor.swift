import AppKit
import SwiftUI

/// Native cursor rectangles restore the previous cursor on exit and view removal.
/// They avoid a global push/pop stack when controls overlap or disappear.
struct PointerCursor: NSViewRepresentable {
    @Environment(\.isEnabled) private var enabled
    var active = true
    func makeNSView(context: Context) -> CursorRegion { CursorRegion() }
    func updateNSView(_ view: CursorRegion, context: Context) {
        let effective = enabled && active
        if view.enabled != effective {
            view.enabled = effective
            view.updateTrackingAreas()
        }
        view.window?.invalidateCursorRects(for: view)
    }
    final class CursorRegion: NSView {
        var enabled = true
        private var cursorTracking: NSTrackingArea?
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let cursorTracking { removeTrackingArea(cursorTracking) }
            cursorTracking = nil
            guard enabled else { return }
            let tracking = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .cursorUpdate], owner: self)
            addTrackingArea(tracking)
            cursorTracking = tracking
        }
        override func cursorUpdate(with event: NSEvent) {
            if enabled { NSCursor.pointingHand.set() }
            else { super.cursorUpdate(with: event) }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() {
            if enabled { addCursorRect(visibleRect, cursor: .pointingHand) }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }
    }
}
extension View {
    func pointingCursor(_ active: Bool = true) -> some View { background(PointerCursor(active: active).accessibilityHidden(true)) }
}

/// Keep native Settings buttons while applying the same pointer as notch buttons.
struct SettingsButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(.bordered).pointingCursor()
    }
}
