import Foundation
import IOKit
import IOKit.pwr_mgt

protocol LidStateObserving: AnyObject {
    var currentState: Bool? { get }
    func start(changed: @escaping (Bool) -> Void)
    func stop()
}

/// Receives the lid-close notification before system sleep, so opening the lid
/// can be distinguished from waking an already-open Mac with its trackpad.
final class LidStateService: LidStateObserving {
    var currentState: Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, kAppleClamshellStateKey as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }
    // IOPM.h's public kIOPMMessageClamshellStateChange macro cannot be imported
    // into Swift: iokit_family_msg(err_sub(13), 0x100), with sys_iokit = 0x38 << 26.
    private static let clamshellStateChange: UInt32 = (0x38 << 26) | (13 << 14) | 0x100
    private var port: IONotificationPortRef?
    private var root: io_service_t = 0
    private var observer: io_object_t = 0
    private var changed: (Bool) -> Void = { _ in }

    func start(changed: @escaping (Bool) -> Void) {
        stop()
        self.changed = changed
        root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0, let port = IONotificationPortCreate(kIOMainPortDefault) else { stop(); return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let result = IOServiceAddInterestNotification(port, root, kIOGeneralInterest, { context, _, message, argument in
            guard message == LidStateService.clamshellStateChange, let context else { return }
            let service = Unmanaged<LidStateService>.fromOpaque(context).takeUnretainedValue()
            service.changed(UInt(bitPattern: argument) & UInt(kClamshellStateBit) != 0)
        }, Unmanaged.passUnretained(self).toOpaque(), &observer)
        if result != KERN_SUCCESS { stop() }
    }
    func stop() {
        if observer != 0 { IOObjectRelease(observer); observer = 0 }
        if let port { IONotificationPortDestroy(port); self.port = nil }
        if root != 0 { IOObjectRelease(root); root = 0 }
        changed = { _ in }
    }
    deinit { stop() }
}
