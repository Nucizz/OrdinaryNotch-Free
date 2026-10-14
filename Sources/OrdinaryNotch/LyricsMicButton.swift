import SwiftUI

struct LyricsMicButton: View {
    var enabled: Bool
    var tint: NSColor
    @Binding var presentation: LyricsPresentation
    var toggle: () -> Void

    var body: some View {
        NotchIconButton(symbol: enabled ? "mic.fill" : "mic", label: "Synced lyrics",
            value: enabled ? "On" : "Off",
            hint: "Click to \(enabled ? "hide" : "show") lyrics. Press and hold to change their presentation.",
            selected: enabled, tint: Color(nsColor: tint),
            symbolFont: .system(size: 13, weight: .medium),
            menuItems: menuItems, menuLabel: "Change lyrics presentation", action: toggle)
    }

    var menuItems: [NotchButtonMenuItem] {
        LyricsPresentation.allCases.map { style in
            NotchButtonMenuItem(title: style.title, selected: style == presentation) { presentation = style }
        }
    }
}
