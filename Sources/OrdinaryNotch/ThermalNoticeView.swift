import SwiftUI

struct ThermalNoticeView: View {
    let notice: ThermalNotice
    var body: some View {
        CompactNoticeView(symbol: "thermometer.high", title: "High temperature",
                          detail: notice.sensorName,
                          value: String(format: "%.1f°C", notice.celsius), accent: .red)
    }
}
