import SwiftUI

/// Missing usage has an empty neutral track, without inventing a reporting window.
struct CodeUsageView: View {
    let usage: CodexUsage?
    let now: Date
    var showsReset = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let usage, !usage.windows.isEmpty {
                ForEach(usage.windows.sorted { $0.minutes < $1.minutes }.prefix(2)) { window in
                    let expired = window.resetsAt.map { $0 <= now } == true
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 2) {
                            Text(window.label)
                            Spacer(minLength: 0)
                            Text(expired ? "–" : "\(Int(window.remaining.rounded()))%")
                                .monospacedDigit()
                        }.font(AppFont.label).foregroundStyle(.white.opacity(0.7))
                        AccentProgress(value: expired ? 0 : window.remaining / 100, color: !expired && window.isLow(at: now) ? Color(nsColor: .systemRed) : .white)
                        if showsReset, !expired, let reset = window.resetsAt {
                            Text(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                                .font(AppFont.label).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .help(expired ? "Updating usage…" : window.resetsAt.map { "Resets \($0.formatted(.dateTime.month(.abbreviated).day().hour().minute()))" } ?? "Reset time unavailable")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(window.label), \(expired ? "updating" : "\(Int(window.remaining.rounded())) percent remaining")")
                        .accessibilityValue(expired ? "Usage unavailable" : window.resetsAt.map { "Resets \($0.formatted())" } ?? "Reset time unavailable")
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Usage")
                        Spacer(minLength: 0)
                        Text("–").monospacedDigit()
                    }.font(AppFont.label).foregroundStyle(.white.opacity(0.7))
                    AccentProgress(value: 0, color: .white)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .help("Usage unavailable")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Usage unavailable")
            }
        }
    }
}
