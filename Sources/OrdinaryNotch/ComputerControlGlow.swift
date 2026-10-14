import SwiftUI

struct ComputerControlGlow: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.purple.opacity(0.9), lineWidth: 1)
                        .background(Color.purple.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                        .shadow(color: .purple.opacity(0.8), radius: 4)
                        .padding(.horizontal, -3).padding(.vertical, -2)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .accessibilityValue(active ? "Using your computer" : "")
    }
}

struct ComputerControlNoticeView: View {
    let provider: CodeProvider
    private var title: String { (provider == .codex ? "Codex" : "Claude") + " started using your computer" }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cursorarrow.motionlines").foregroundStyle(.purple)
            Text(title).font(AppFont.subtitle).foregroundStyle(.white).lineLimit(2)
        }.frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore).accessibilityLabel(title)
    }
}
