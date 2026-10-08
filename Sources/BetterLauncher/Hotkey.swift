import Carbon.HIToolbox

final class Hotkey {
    nonisolated(unsafe) private static var action: (() -> Void)?
    private var ref: EventHotKeyRef?

    /// Registers Cmd+Space. Returns false if the system refused (Spotlight's shortcut still owns it).
    func register(action: @escaping () -> Void) -> Bool {
        Hotkey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Hotkey.action?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: 0x424C_4348, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey), id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }
}
