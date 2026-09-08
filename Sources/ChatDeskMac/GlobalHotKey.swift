import AppKit
import Carbon

/// Exact-key registration, not a keyboard monitor. No Accessibility or event-tap permission.
final class GlobalHotKey {
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    func register(useCommand: Bool = false) -> OSStatus {
        unregister()
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let data, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x4344534B, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let object = Unmanaged<GlobalHotKey>.fromOpaque(data).takeUnretainedValue()
            DispatchQueue.main.async { [weak object] in object?.onPress?() }
            return noErr
        }, 1, &event, context, &handler)
        guard status == noErr else { return status }
        let modifiers = UInt32(optionKey | (useCommand ? cmdKey : controlKey))
        let result = RegisterEventHotKey(UInt32(kVK_Space), modifiers,
            EventHotKeyID(signature: 0x4344534B, id: 1), GetApplicationEventTarget(), 0, &key)
        if result != noErr { unregister() }
        return result
    }
    func unregister() {
        if let key { UnregisterEventHotKey(key); self.key = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
    deinit { unregister() }
}
