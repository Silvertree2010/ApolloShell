import ApolloShellCore
import Carbon.HIToolbox

@MainActor
final class GlobalHotKey {
    private static let signature = OSType(0x4C4E_4348)
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var releases: [UInt32: @MainActor () -> Void] = [:]

    private let id: UInt32
    private var ref: EventHotKeyRef?

    private init(id: UInt32, ref: EventHotKeyRef) {
        self.id = id
        self.ref = ref
    }

    static func register(_ key: HotKey, action: @escaping @MainActor () -> Void) -> Result<GlobalHotKey, HotKeyRegistrationError> {
        register(key, pressed: action, released: nil)
    }

    static func register(_ key: HotKey, pressed action: @escaping @MainActor () -> Void, released: (@MainActor () -> Void)?) -> Result<GlobalHotKey, HotKeyRegistrationError> {
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
        releases[id] = released
        return .success(GlobalHotKey(id: id, ref: ref))
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.actions[id] = nil
        Self.releases[id]?()
        Self.releases[id] = nil
    }

    private static func installHandler() -> OSStatus {
        guard !handlerInstalled else { return noErr }
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
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
                let isRelease = GetEventKind(event) == UInt32(kEventHotKeyReleased)
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard status == noErr, hit.signature == GlobalHotKey.signature,
                          GlobalHotKey.actions[hit.id] != nil
                    else { return false }
                    if isRelease {
                        GlobalHotKey.releases[hit.id]?()
                    } else {
                        GlobalHotKey.actions[hit.id]?()
                    }
                    return true
                }
                return handled ? noErr : OSStatus(eventNotHandledErr)
            },
            specs.count, &specs, nil, nil
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
