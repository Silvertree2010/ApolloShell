import AppKit
import ApolloShellCore
import Carbon.HIToolbox
import Observation
import os
import SwiftUI

/// Die globalen Tastenkuerzel der Shell: registriert, was in settings.json
/// steht (`hotKeys`), und gleicht bei jeder Aenderung ab - ein neues Kuerzel
/// in Nexus gilt sofort, ohne Neustart.
///
/// Nimmt auch neue Kuerzel auf. Solange aufgenommen wird, sind ALLE
/// Kuerzel abgemeldet: Carbon faengt ein registriertes Kuerzel ab, bevor die
/// App den Tastendruck sieht - man koennte das bisherige sonst nie noch
/// einmal eingeben oder zwei Aktionen tauschen.
@MainActor
@Observable
final class HotKeyCenter {
    enum Status: Equatable {
        /// Kein Kuerzel eingestellt.
        case none
        case active
        case failed(String)
        /// Gerade abgemeldet, weil aufgenommen wird.
        case paused
    }

    /// Welche Aktion gerade ein neues Kuerzel aufnimmt.
    private(set) var recording: HotKeyAction?
    /// Waehrend der Aufnahme schon gedrueckte Sondertasten ("⌥⌘ …").
    private(set) var liveModifiers: HotKeyModifiers = []
    /// Letzte Rueckmeldung beim Aufnehmen (abgelehnt, schon vergeben).
    private(set) var feedback: [HotKeyAction: String] = [:]
    private(set) var failures: [HotKeyAction: HotKeyRegistrationError] = [:]

    @ObservationIgnored private let store: ShellSettingsStore
    /// `false` fuer Bildproben: registriert und belauscht nie etwas.
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var handlers: [HotKeyAction: @MainActor () -> Void] = [:]
    @ObservationIgnored private var registered: [HotKeyAction: (key: HotKey, hotKey: GlobalHotKey)] = [:]
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private let log = Logger(category: "hotkeys")

    init(store: ShellSettingsStore) {
        self.store = store
        live = true
    }

    private init(preview store: ShellSettingsStore) {
        self.store = store
        live = false
    }

    /// Fuer Bildproben: fester Stand, keine Registrierung.
    static func preview(store: ShellSettingsStore, failures: [HotKeyAction: HotKeyRegistrationError] = [:],
                        recording: HotKeyAction? = nil, liveModifiers: HotKeyModifiers = [],
                        feedback: [HotKeyAction: String] = [:]) -> HotKeyCenter {
        let center = HotKeyCenter(preview: store)
        center.failures = failures
        center.recording = recording
        center.liveModifiers = liveModifiers
        center.feedback = feedback
        return center
    }

    /// Was ein Kuerzel ausloest. Aktionen ohne Handler (Nur-Launcher-Modus:
    /// alles ausser dem Launcher) werden nicht registriert.
    func setHandler(_ action: HotKeyAction, _ handler: @escaping @MainActor () -> Void) {
        handlers[action] = handler
    }

    /// Einmal nach dem Setzen der Handler. Liefert zuerst den aktuellen
    /// Stand, danach jede Aenderung aus Nexus; lebt so lange wie die App.
    func start() {
        guard live, observation == nil else { return }
        apply()
        observation = Task { [weak self, store] in
            for await _ in Observations({ store.settings.hotKeys }) {
                self?.apply()
            }
        }
    }

    func status(for action: HotKeyAction) -> Status {
        guard store.settings.hotKeys[action] != nil else { return .none }
        if recording != nil { return .paused }
        if let failure = failures[action] { return .failed(failure.message) }
        return .active
    }

    /// Registrierte Kuerzel mit den Einstellungen abgleichen.
    private func apply() {
        guard live, recording == nil else { return }
        let wanted = store.settings.hotKeys
        // Erst alle abmelden, die sich aendern: sonst scheiterte ein Tausch
        // zweier Kuerzel daran, dass das andere noch registriert ist.
        for (action, entry) in registered where wanted[action] != entry.key || handlers[action] == nil {
            entry.hotKey.unregister()
            registered[action] = nil
        }
        var failed: [HotKeyAction: HotKeyRegistrationError] = [:]
        for action in HotKeyAction.allCases {
            guard registered[action] == nil, let key = wanted[action], let handler = handlers[action] else { continue }
            switch GlobalHotKey.register(key, action: handler) {
            case .success(let hotKey):
                registered[action] = (key, hotKey)
            case .failure(let error):
                failed[action] = error
                log.error("\(action.rawValue, privacy: .public): \(key.display(), privacy: .public) nicht registriert (OSStatus \(error.status, privacy: .public))")
            }
        }
        if failed != failures { failures = failed }
    }

    private func unregisterAll() {
        for entry in registered.values { entry.hotKey.unregister() }
        registered = [:]
    }

    // MARK: - Aufnehmen

    func startRecording(_ action: HotKeyAction) {
        if recording != nil { stopRecording() }
        recording = action
        liveModifiers = []
        feedback[action] = nil
        guard live else { return }
        unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let type = event.type
            let code = event.keyCode
            let flags = event.modifierFlags
            let consumed = MainActor.assumeIsolated {
                self?.handle(type: type, keyCode: code, flags: flags) ?? false
            }
            return consumed ? nil : event
        }
        // Wechselt man die App, kommen keine Tasten mehr an - dann nicht
        // mit abgemeldeten Kuerzeln haengen bleiben.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelRecording() }
        }
    }

    /// Abbrechen, ohne etwas zu aendern (⎋, Fenster zu, andere App).
    func cancelRecording() {
        guard recording != nil else { return }
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        recording = nil
        liveModifiers = []
        apply()
    }

    /// `true`: Tastendruck verbraucht (geht an kein Feld und kein Menue).
    private func handle(type: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard let action = recording else { return false }
        let modifiers = Self.modifiers(from: flags)
        if type == .flagsChanged {
            liveModifiers = modifiers
            return false
        }
        switch HotKeyRecording.evaluate(keyCode: UInt32(keyCode), modifiers: modifiers) {
        case .cancel:
            stopRecording()
        case .clear:
            store.settings.hotKeys[action] = nil
            stopRecording()
        case .rejected(let reason):
            // Weiter aufnehmen: gleich die naechste Kombination probieren.
            feedback[action] = HotKeyText.rejection(reason)
        case .record(let key):
            if let owner = store.settings.hotKeys.action(using: key, except: action) {
                feedback[action] = HotKeyText.taken(by: owner)
            } else {
                store.settings.hotKeys[action] = key
                stopRecording()
            }
        }
        return true
    }

    /// Nur die vier, die ein Kuerzel ausmachen; Feststell-, fn- und
    /// Ziffernblock-Merker (kommen bei F- und Pfeiltasten mit) fallen weg.
    static func modifiers(from flags: NSEvent.ModifierFlags) -> HotKeyModifiers {
        var result: HotKeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}

/// Beschriftung einer Taste auf der aktuellen Tastaturbelegung. Carbon
/// kennt nur die Lage der Taste (kVK_ANSI_Z ist auf einer deutschen Tastatur
/// das Y) - fuer Buchstaben und Satzzeichen fragt die Anzeige deshalb macOS
/// (UCKeyTranslate, ohne Sondertasten). Alles andere steht in `HotKeyKey`.
enum HotKeyKeyboard {
    static func display(_ key: HotKey) -> String {
        key.display(keyName: keyName(for: key.keyCode))
    }

    static func keyName(for keyCode: UInt32) -> String? {
        guard HotKeyKey.isCharacterKey(keyCode),
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let text = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout -> String in
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            // Tote Tasten (´ ^ `) als ihr eigenes Zeichen, nicht als "nichts".
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
            )
            return status == noErr ? String(utf16CodeUnits: chars, count: length) : ""
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !trimmed.isEmpty else { return nil }
        // "ß" wuerde gross zu "SS" - dann lieber klein lassen.
        let upper = trimmed.uppercased()
        return upper.count == trimmed.count ? upper : trimmed
    }
}

// MARK: - Oberflaeche

/// Feld, das ein Kuerzel zeigt und per Klick ein neues aufnimmt - wie die
/// Kuerzel-Felder in den Systemeinstellungen (Tastatur > Tastaturkurzbefehle).
struct HotKeyRecorder: View {
    let center: HotKeyCenter
    let store: ShellSettingsStore
    let action: HotKeyAction

    var body: some View {
        let key = store.settings.hotKeys[action]
        let recording = center.recording == action
        HStack(spacing: 6) {
            Button {
                recording ? center.cancelRecording() : center.startRecording(action)
            } label: {
                Text(label(key: key, recording: recording))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(recording ? AnyShapeStyle(Color.accentColor)
                        : key == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .frame(minWidth: 104)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(recording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.12),
                                          lineWidth: recording ? 1.5 : 1)
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(recording ? HotKeyText.recordingHelp : String(localized: "Click and press the new combination"))
            .accessibilityLabel("Shortcut for \(action.title)")
            .accessibilityValue(key.map(HotKeyKeyboard.display) ?? HotKeyText.none)

            // Platz halten, damit das Feld beim Aufnehmen nicht springt.
            Button {
                store.settings.hotKeys[action] = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("Remove Shortcut")
            .opacity(key != nil && !recording ? 1 : 0)
            .disabled(key == nil || recording)
        }
    }

    private func label(key: HotKey?, recording: Bool) -> String {
        if recording {
            return center.liveModifiers.isEmpty ? HotKeyText.recordingPrompt : center.liveModifiers.symbols + " …"
        }
        return key.map(HotKeyKeyboard.display) ?? HotKeyText.none
    }
}

/// Eine Zeile: Kachel, Aktion, Aufnahmefeld - darunter, falls noetig, warum
/// es nicht geht oder was daran heikel ist.
struct HotKeyRow: View {
    let center: HotKeyCenter
    let store: ShellSettingsStore
    let action: HotKeyAction
    var tint: Color = .purple

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                NexusTile(symbol: action.symbol, tint: tint, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                HotKeyRecorder(center: center, store: store, action: action)
            }
            if let message {
                Label(message.text, systemImage: message.symbol)
                    .font(.caption)
                    .foregroundStyle(message.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 34)
            }
        }
    }

    private var message: (text: String, symbol: String, color: Color)? {
        if center.recording == action {
            if let feedback = center.feedback[action] { return (feedback, "exclamationmark.circle.fill", .orange) }
            return (HotKeyText.recordingHelp, "keyboard", .secondary)
        }
        if case .failed(let text) = center.status(for: action) {
            return (text, "exclamationmark.triangle.fill", .red)
        }
        if let key = store.settings.hotKeys[action], let warning = HotKeyAdvice.warning(for: key) {
            return (HotKeyText.warning(warning), "exclamationmark.triangle.fill", .orange)
        }
        return nil
    }
}
