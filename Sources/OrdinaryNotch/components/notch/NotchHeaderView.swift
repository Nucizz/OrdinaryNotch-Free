import SwiftUI

/// The same header layout and controls in the live notch and Settings preview.
struct NotchHeaderView: View {
    let left: [String]
    let right: [String]
    let selectedTab: NotchTab?
    var pinned = false
    var visibility: FullScreenVisibility
    var hasAgentRequests = false
    let contentWidth: CGFloat
    let reservedWidth: CGFloat
    var activate: (String) -> Void
    private let muted = Color.white.opacity(0.42)
    private var wingWidth: CGFloat { (contentWidth - reservedWidth - 8) / 2 }
    private var count: CGFloat { CGFloat(max(4, left.count, right.count)) }
    // Tighten spacing before shrinking buttons. Narrow wings use smaller squares.
    private var slotWidth: CGFloat { min(32, max(20, wingWidth / count)) }
    private var slotHeight: CGFloat { min(NotchControlMetrics.size, slotWidth) }
    private var spacing: CGFloat { min(6, max(0, (wingWidth - count * slotWidth) / (count - 1))) }
    var body: some View {
        HStack(spacing: 0) {
            wing(left, alignment: .leading)
            Color.clear.frame(width: reservedWidth + 8)
            wing(right, alignment: .trailing)
        }
    }
    private func wing(_ items: [String], alignment: Alignment) -> some View {
        HStack(spacing: spacing) {
            ForEach(items, id: \.self) { item in headerItem(item) }
        }.frame(maxWidth: .infinity, alignment: alignment)
    }
    @ViewBuilder private func headerItem(_ item: String) -> some View {
        if let tab = NotchTab(rawValue: item) {
            NotchIconButton(symbol: tab.icon, label: tab == .codex && hasAgentRequests ? "Code & AI — Answer agent requests" : tab.title,
                selected: selectedTab == tab, width: slotWidth, height: slotHeight, tint: selectedTab == tab ? .white : muted) { activate(item) }
                .overlay(alignment: .topTrailing) {
                    if tab == .codex && hasAgentRequests {
                        Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9))
                            .foregroundStyle(.black, .orange).allowsHitTesting(false)
                    }
                }
        } else if item == NotchTabLayout.settings {
            NotchIconButton(symbol: "gearshape", label: "Settings", width: slotWidth, height: slotHeight, tint: muted) { activate(item) }
        } else if item == NotchTabLayout.visibility {
            NotchIconButton(symbol: visibility.icon, label: "Notch visibility", value: visibility.title,
                hint: "\(visibility.title). Click to switch to \(visibility.next.title).", width: slotWidth, height: slotHeight) { activate(item) }
        } else {
            NotchIconButton(symbol: pinned ? "pin.fill" : "pin", label: pinned ? "Unpin panel" : "Keep expanded",
                selected: pinned, width: slotWidth, height: slotHeight, tint: pinned ? .white : muted) { activate(item) }
        }
    }
}
