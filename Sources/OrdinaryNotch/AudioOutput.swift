import CoreAudio
import Foundation

enum AudioOutput {
    struct Route: Equatable {
        let name: String
        let symbol: String
    }
    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let uid: String
        let route: Route
        let selected: Bool
    }

    /// The selected macOS output, refreshed with the existing media polling cycle.
    static func current() -> Route? {
        guard let device = currentID() else { return nil }
        return route(device)
    }

    /// Enumerate only when the picker opens, not on every playback tick.
    static func devices() -> [Device] {
        var property = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &property, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { return [] }
        let selected = currentID()
        return ids.compactMap { id -> Device? in
            guard number(id, kAudioDevicePropertyDeviceIsAlive) == 1,
                  number(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioDevicePropertyScopeOutput) == 1,
                  let uid = string(id, kAudioDevicePropertyDeviceUID), let route = route(id) else { return nil }
            return Device(id: id, uid: uid, route: route, selected: id == selected)
        }.sorted { $0.route.name.localizedStandardCompare($1.route.name) == .orderedAscending }
    }

    static func select(_ device: Device) -> Bool {
        // Device IDs can be recycled after a disconnect; revalidate the stable UID.
        guard devices().contains(where: { $0.id == device.id && $0.uid == device.uid }) else { return false }
        if currentID() == device.id { return true }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        var writable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(system, &property, &writable) == noErr, writable.boolValue else { return false }
        var id = device.id
        return AudioObjectSetPropertyData(system, &property, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id) == noErr
            && currentID() == device.id
    }

    private static func currentID() -> AudioDeviceID? {
        guard let id = number(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice),
              id != kAudioObjectUnknown else { return nil }
        return id
    }
    private static func route(_ device: AudioDeviceID) -> Route? {
        guard let name = string(device, kAudioObjectPropertyName) else { return nil }
        return Route(name: name, symbol: symbol(name: name, transport: number(device, kAudioDevicePropertyTransportType) ?? 0))
    }
    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    private static func number(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var property = address(selector, scope: scope), value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var property = address(selector)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &name) == noErr,
              let name else { return nil }
        let value = (name.takeRetainedValue() as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func symbol(name: String, transport: UInt32 = 0) -> String {
        let name = name.lowercased()
        if name.contains("airpods") {
            if name.contains("max") { return "airpodsmax" }
            if name.contains("pro") { return "airpodspro" }
            return "airpods"
        }
        if name.contains("headphone") || name.contains("earphone") || name.contains("earpod") {
            return "headphones"
        }
        if name.contains("macbook") { return "laptopcomputer" }
        if name.contains("imac") { return "desktopcomputer" }
        if name.contains("homepod") { return "homepod.fill" }
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "antenna.radiowaves.left.and.right"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt:
            return "cable.connector"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        default:
            return "speaker.wave.2.fill"
        }
    }
}
