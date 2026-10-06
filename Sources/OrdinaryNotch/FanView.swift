import SwiftUI
import FanCore
struct FanTabView: View {
    @ObservedObject var service: FanViewModel
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Fans").font(AppFont.body)
                ForEach(service.snapshot.fans) { fan in
                    Text("\(fan.name): \(service.stale ? "—" : String(Int(fan.rpm))) RPM").monospacedDigit()
                }
                if service.snapshot.hasNoFans { Text("This Mac has no fans.").foregroundStyle(.secondary) }
                if let error = service.snapshot.error { Text(error).font(AppFont.subtitle) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(TemperatureZone.allCases, id: \.self) { zone in
                    if let reading = service.snapshot.temperature(for: zone) {
                        Text("\(zone.rawValue.uppercased()): \(Int(reading.celsius))°C").monospacedDigit()
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.font(AppFont.body)
    }
}
