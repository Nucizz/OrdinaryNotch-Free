import AppKit

/// Read-only. Showing an overlay must never become a reason to wake a display.
enum DisplayPowerService {
    @MainActor static func isAwake(on screen: NSScreen?) -> Bool {
        guard let id = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
        return CGDisplayIsActive(id) != 0 && CGDisplayIsAsleep(id) == 0
    }
}
