import ApolloShellCore
import Carbon.HIToolbox

@MainActor
final class GlobalHotKey {
    private static let signature = OSType(0x4C4E_4348)
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false
    private static var actions: [UInt32: @MainActor () -> Void] = [:]

    private let id: UInt32
    private var ref: EventHotKeyRef?

    private init(id: UInt32, ref: EventHotKeyRef) {
        self.id = id
        self.ref = ref
    }

    static func register(_ key: HotKey, action: @escaping @MainActor () -> Void) -> Result<GlobalHotKey, HotKeyRegistrationError> {
        let installed = installHandler()
        guard installed == noErr else { return .failure(HotKeyRegistrationError(status: installed)) }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            key.keyCode, key.modifiers.rawValue, EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return .failure(HotKeyRegistrationError(status: status)) }
        actions[id] = action
        return .success(GlobalHotKey(id: id, ref: ref))
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.actions[id] = nil
    }

    private static func installHandler() -> OSStatus {
        guard !handlerInstalled else { return noErr }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                let hit = pressed
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard status == noErr, hit.signature == GlobalHotKey.signature,
                          let action = GlobalHotKey.actions[hit.id]
                    else { return false }
                    action()
                    return true
                }
                return handled ? noErr : OSStatus(eventNotHandledErr)
            },
            1, &spec, nil, nil
        )
        if status == noErr { handlerInstalled = true }
        return status
    }
}

struct HotKeyRegistrationError: Error, Equatable {
    let status: OSStatus

    var alreadyTaken: Bool { status == OSStatus(eventHotKeyExistsErr) }

    var message: String {
        HotKeyText.registrationFailed(alreadyTaken: alreadyTaken, status: status)
    }
}
