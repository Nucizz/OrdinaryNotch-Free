import CoreAudio
import Foundation

struct OutputMuteTarget: Hashable {
    let device: AudioDeviceID
    let element: AudioObjectPropertyElement
}

@MainActor protocol OutputMuteControlling: AnyObject {
    /// Preserve supported controls even if another output cannot be muted.
    func targets() -> (controls: [OutputMuteTarget], complete: Bool)
    func muted(_ target: OutputMuteTarget) -> Bool?
    func setMuted(_ muted: Bool, target: OutputMuteTarget) -> Bool
    func observe(_ targets: [OutputMuteTarget], changed: @escaping () -> Void)
    func stopObserving()
}

@MainActor protocol ClosedLidAudioSilencing: AnyObject {
    var onError: (String?) -> Void { get set }
    func silence()
    func restore()
}

/// Owns only the mute changes made during this lid closure. No volume is changed.
@MainActor final class ClosedLidAudioService: ClosedLidAudioSilencing {
    var onError: (String?) -> Void = { _ in }
    private let output: any OutputMuteControlling
    private var originals: [OutputMuteTarget: Bool] = [:]
    private var active = false
    private var silenceError: String?

    init(output: (any OutputMuteControlling)? = nil) { self.output = output ?? CoreAudioOutputMute() }
    func silence() {
        active = true
        enforceMute()
    }
    private func enforceMute() {
        guard active else { return }
        let available = output.targets()
        let targets = available.controls
        var failed = !available.complete
        // Restore outputs that stopped being selected, so detached headphones do
        // not inherit the temporary mute when they are used again later.
        for target in Array(originals.keys) where !targets.contains(target) {
            if restore(target) { originals[target] = nil }
        }
        for target in targets {
            guard let muted = output.muted(target) else { failed = true; continue }
            if originals[target] == nil { originals[target] = muted }
            if !muted && !output.setMuted(true, target: target) { failed = true }
        }
        output.observe(targets) { [weak self] in self?.enforceMute() }
        silenceError = failed ? "Media was asked to pause, but this audio output could not be muted while the lid was closed." : nil
        onError(silenceError)
    }
    @discardableResult private func restore(_ target: OutputMuteTarget) -> Bool {
        guard let previous = originals[target], let current = output.muted(target) else { return false }
        // Don't overwrite a later external change when we no longer own the value.
        return current == previous || !current || output.setMuted(previous, target: target)
    }
    func restore() {
        active = false
        output.stopObserving()
        for target in Array(originals.keys) where restore(target) { originals[target] = nil }
        onError(originals.isEmpty ? silenceError : "The previous audio mute state could not be restored. Check your sound output.")
    }
}

@MainActor private final class CoreAudioOutputMute: OutputMuteControlling {
    private struct Listener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var listeners: [Listener] = []
    private var observed: Set<OutputMuteTarget>?

    private func address(_ target: OutputMuteTarget) -> AudioObjectPropertyAddress {
        .init(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: target.element)
    }
    func targets() -> (controls: [OutputMuteTarget], complete: Bool) {
        var devices: Set<AudioDeviceID> = []
        var complete = true
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var device = AudioDeviceID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioDeviceID>.size)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else {
                complete = false; continue
            }
            if device != kAudioObjectUnknown { devices.insert(device) }
        }
        var result: [OutputMuteTarget] = []
        for device in devices {
            let master = OutputMuteTarget(device: device, element: kAudioObjectPropertyElementMain)
            if writable(master) { result.append(master); continue }
            // Some USB interfaces expose per-channel mute instead of a master.
            let channels = (1...32).map { OutputMuteTarget(device: device, element: UInt32($0)) }.filter(writable)
            if channels.isEmpty { complete = false }
            result.append(contentsOf: channels)
        }
        return (result, complete)
    }
    private func writable(_ target: OutputMuteTarget) -> Bool {
        var property = address(target), settable = DarwinBoolean(false)
        return AudioObjectHasProperty(target.device, &property)
            && AudioObjectIsPropertySettable(target.device, &property, &settable) == noErr && settable.boolValue
    }
    func muted(_ target: OutputMuteTarget) -> Bool? {
        var property = address(target), value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(target.device, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }
    func setMuted(_ muted: Bool, target: OutputMuteTarget) -> Bool {
        var property = address(target), value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(target.device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
            && self.muted(target) == muted
    }
    func observe(_ targets: [OutputMuteTarget], changed: @escaping () -> Void) {
        let next = Set(targets)
        guard observed != next else { return }
        stopObserving(); observed = next
        var properties = targets.map { ($0.device, address($0)) }
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            properties.append((AudioObjectID(kAudioObjectSystemObject), .init(mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)))
        }
        for (object, property) in properties {
            var property = property
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                MainActor.assumeIsolated { changed() }
            }
            if AudioObjectAddPropertyListenerBlock(object, &property, .main, block) == noErr {
                listeners.append(Listener(object: object, address: property, block: block))
            }
        }
    }
    func stopObserving() {
        for var listener in listeners {
            AudioObjectRemovePropertyListenerBlock(listener.object, &listener.address, .main, listener.block)
        }
        listeners = []; observed = nil
    }
    deinit {
        for var listener in listeners {
            AudioObjectRemovePropertyListenerBlock(listener.object, &listener.address, .main, listener.block)
        }
    }
}
