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
            ForEach(Array(presets.enumerated()), id: \.offset) { index, seconds in
                Button { start(seconds) } label: {
                    Text(durationLabel(seconds))
                        .font(AppFont.button).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 20)
                }
                .buttonStyle(NotchButtonStyle()).frame(height: 26)
                .accessibilityLabel("Start \(durationLabel(seconds)) timer")
                .opacity(appeared ? 1 : 0)
                .offset(y: reduceMotion || appeared ? 0 : 6)
                .animation(reduceMotion ? .easeOut(duration: 0.1) :
                    .easeOut(duration: appeared ? 0.22 : 0.12).delay(appeared ? Double(index) * 0.02 : 0), value: appeared)
            }
        }
        .task(id: visible) {
            guard visible else { appeared = false; return }
            // Establish the hidden first frame before animating a newly inserted grid.
            do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            appeared = true
        }
        .onDisappear { appeared = false }
    }

    private func durationLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        if seconds == 3600 { return "1 hr" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
