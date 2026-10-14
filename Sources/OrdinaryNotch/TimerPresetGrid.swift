import SwiftUI

struct TimerPresetGrid: View {
    let presets: [Int]
    let visible: Bool
    let start: (Int) -> Void
    @Environment(\.notchReduceMotion) private var reduceMotion
    @State private var appeared = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(Array(presets.enumerated()), id: \.offset) { _, seconds in
                Button { start(seconds) } label: {
                    Text(DurationText.format(seconds))
                        .font(AppFont.button).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 26)
                }
                .buttonStyle(NotchButtonStyle(.standard, padded: false))
                .accessibilityLabel("Start \(DurationText.format(seconds)) timer")
                .notchHint("Start a \(DurationText.format(seconds)) timer")
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: reduceMotion || appeared ? 0 : 6)
        .animation(NotchMotion.details(expanded: appeared, reduceMotion: reduceMotion), value: appeared)
        .task(id: visible) {
            guard visible else { appeared = false; return }
            // Establish the hidden first frame before animating a newly inserted grid.
            do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            appeared = true
        }
        .onDisappear { appeared = false }
    }
}
