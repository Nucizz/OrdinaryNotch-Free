import SwiftUI

/// Ordinary Notch controls keep native button semantics with monochrome states.
struct NotchActionButton: View {
    let title: String
    var prominent = false
    var shortcut: String? = nil
    var progress: Double? = nil
    var hint: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let shortcut { Text(shortcut).font(.system(size: 11)).opacity(0.6).accessibilityHidden(true) }
            }.padding(.horizontal, 12).frame(minHeight: 32)
                .background {
                    if let progress {
                        GeometryReader { geometry in
                            Color.white.opacity(0.22).frame(width: geometry.size.width * min(1, max(0, progress)))
                        }.clipShape(RoundedRectangle(cornerRadius: NotchControlMetrics.cornerRadius, style: .continuous))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(NotchButtonStyle(prominent ? .selected : .standard, padded: false))
        .notchHint(hint ?? title)
        .keyboardShortcut(shortcut == "↩" ? KeyboardShortcut.defaultAction : (shortcut == "⎋" ? KeyboardShortcut.cancelAction : nil))
    }
}
