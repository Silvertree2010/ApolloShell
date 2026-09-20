import ApolloShellCore
import Carbon.HIToolbox

/// Global hotkey via Carbon (RegisterEventHotKey).
///
/// Needs no accessibility permission, unlike an event tap. The
/// fn key itself can't be caught by Carbon; whoever wants it as a launcher
/// key has a keyboard tool (e.g. Karabiner-Elements) send it
/// as F20 and uses F20 as the shortcut.
///
/// A single event handler for all of the app's hotkeys; it looks up the
/// action by identifier. The first version installed a handler per hotkey
/// that fired on EVERY hotkey event - with several,
/// every keypress would have triggered all of them. And since shortcuts
/// can change at runtime, they need to unregister cleanly: a handler
/// with a pointer to a released object would be a crash.
@MainActor
final class GlobalHotKey {
    private static let signature = OSType(0x4C4E_4348) // "LNCH"
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false
    private static var actions: [UInt32: @MainActor () -> Void] = [:]

    private let id: UInt32
    private var ref: EventHotKeyRef?

    private init(id: UInt32, ref: EventHotKeyRef) {
        self.id = id
        self.ref = ref
    }

    /// Registers the shortcut. If it fails (e.g. another app already has
    /// it), Carbon's error code comes back - Nexus displays it.
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

    /// Releases the shortcut; afterwards the object does nothing more.
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
                // Carbon delivers hotkey events on the main thread; only
                // there is the identifier compared (the table is main-actor state).
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard status == noErr, hit.signature == GlobalHotKey.signature,
                          let action = GlobalHotKey.actions[hit.id]
                    else { return false }
                    action()
                    return true
                }
                // Pass foreign hotkeys on to the next handler.
                return handled ? noErr : OSStatus(eventNotHandledErr)
            },
            1, &spec, nil, nil
        )
        if status == noErr { handlerInstalled = true }
        return status
    }
}

/// Carbon did not accept the shortcut.
struct HotKeyRegistrationError: Error, Equatable {
    let status: OSStatus

    /// eventHotKeyExistsErr: someone else registered it first.
    var alreadyTaken: Bool { status == OSStatus(eventHotKeyExistsErr) }

    var message: String {
        HotKeyText.registrationFailed(alreadyTaken: alreadyTaken, status: status)
    }
}
