import Foundation
import IOKit.ps

protocol BatteryReadingService { func read() -> BatteryReading? }
struct BatteryService: BatteryReadingService {
    func read() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let value = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  value[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = value[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = value[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let percent = min(100, max(0, Int((Double(capacity) / Double(maximum) * 100).rounded())))
            let connected = value[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return BatteryReading(percent: percent, connected: connected,
                                  charging: value[kIOPSIsChargingKey] as? Bool ?? false,
                                  full: connected && (value[kIOPSIsChargedKey] as? Bool == true || percent == 100))
        }
        return nil
    }
}
