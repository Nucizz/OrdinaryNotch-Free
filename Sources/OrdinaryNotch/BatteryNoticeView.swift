import SwiftUI

struct BatteryNoticeView: View {
    let notice: BatteryNotice
    private var accent: Color { notice.kind == .low ? (notice.percent <= 10 ? .red : .orange) : .green }
    var body: some View {
        CompactNoticeView(symbol: notice.symbol, title: notice.title, detail: notice.subtitle,
                          value: "\(notice.percent)%", accent: accent)
    }
}
