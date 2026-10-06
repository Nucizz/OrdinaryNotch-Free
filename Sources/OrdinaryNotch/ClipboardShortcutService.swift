import Carbon

@MainActor
final class ClipboardShortcutService {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    init(keyCode: UInt32 = UInt32(kVK_ANSI_V), modifiers: UInt32 = UInt32(cmdKey | shiftKey)) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }
    func start(action: @escaping () -> Void) -> Bool {
        stop()
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Receive the registered hotkey before AppKit routes events through menus/windows.
        guard let dispatcher = GetEventDispatcherTarget() else { stop(); return false }
        let installed = InstallEventHandler(dispatcher, { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x4F4E434C, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<ClipboardShortcutService>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &event, context, &handler)
        guard installed == noErr else { stop(); return false }
        let id = EventHotKeyID(signature: 0x4F4E434C, id: 1) // ONCL
        let registered = RegisterEventHotKey(keyCode, modifiers, id,
                                             dispatcher, OptionBits(kEventHotKeyExclusive), &hotKey)
        guard registered == noErr else { stop(); return false }
        return true
    }
    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; action = nil
    }
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
