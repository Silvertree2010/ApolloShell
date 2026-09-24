import ApolloShellCore
import Carbon.HIToolbox

/// Globaler Hotkey ueber Carbon (RegisterEventHotKey).
///
/// Braucht keine Bedienungshilfen-Rechte, anders als ein Event-Tap. Die
/// fn-Taste selbst kann Carbon nicht abfangen; wer sie als Launcher-Taste
/// will, laesst sie von einem Tastatur-Werkzeug (z. B. Karabiner-Elements)
/// als F20 schicken und nimmt F20 als Kuerzel.
///
/// Ein einziger Ereignis-Handler fuer alle Hotkeys der App; er sucht die
/// Aktion ueber die Kennung heraus. Die erste Fassung installierte pro Hotkey
/// einen Handler, der auf JEDES Hotkey-Ereignis ansprang - mit mehreren
/// haette jeder Tastendruck alle ausgeloest. Und seit sich Kuerzel zur
/// Laufzeit aendern, muessen sie sich sauber abmelden lassen: ein Handler
/// mit Zeiger auf ein freigegebenes Objekt waere ein Absturz.
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

    /// Registriert das Kuerzel. Scheitert es (z. B. hat eine andere App es
    /// schon), kommt Carbons Fehlercode zurueck - Nexus zeigt ihn an.
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

    /// Kuerzel freigeben; danach tut das Objekt nichts mehr.
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
                // Carbon liefert Hotkey-Ereignisse auf dem Main-Thread; erst
                // dort Kennung vergleichen (die Tabelle ist Main-Actor-Zustand).
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard status == noErr, hit.signature == GlobalHotKey.signature,
                          let action = GlobalHotKey.actions[hit.id]
                    else { return false }
                    action()
                    return true
                }
                // Fremde Hotkeys an den naechsten Handler weiterreichen.
                return handled ? noErr : OSStatus(eventNotHandledErr)
            },
            1, &spec, nil, nil
        )
        if status == noErr { handlerInstalled = true }
        return status
    }
}

/// Carbon hat das Kuerzel nicht angenommen.
struct HotKeyRegistrationError: Error, Equatable {
    let status: OSStatus

    /// eventHotKeyExistsErr: jemand anderes hat es zuerst registriert.
    var alreadyTaken: Bool { status == OSStatus(eventHotKeyExistsErr) }

    var message: String {
        HotKeyText.registrationFailed(alreadyTaken: alreadyTaken, status: status)
    }
}
