import AppKit
import ApolloShellCore
import Carbon.HIToolbox
import Observation
import os
import SwiftUI

/// The global keyboard shortcuts of the shell: registers what stands in
/// settings.json (`hotKeys`) and matches up on every change - a new shortcut
/// in Nexus holds right away, without a restart.
///
/// Records new shortcuts too. While recording runs, ALL shortcuts are
/// unregistered: Carbon catches a registered shortcut before the app sees the
/// key press - one could otherwise never enter the current one again or swap
/// two actions.
@MainActor
@Observable
final class HotKeyCenter {
    enum Status: Equatable {
        /// No shortcut set.
        case none
        case active
        case failed(String)
        /// Unregistered right now, because recording is running.
        case paused
    }

    /// Which action is recording a new shortcut right now.
    private(set) var recording: HotKeyAction?
    /// The modifier keys already held during the recording ("⌥⌘ …").
    private(set) var liveModifiers: HotKeyModifiers = []
    /// The last feedback while recording (refused, taken already).
    private(set) var feedback: [HotKeyAction: String] = [:]
    private(set) var failures: [HotKeyAction: HotKeyRegistrationError] = [:]

    @ObservationIgnored private let store: ShellSettingsStore
    /// `false` for image samples: never registers and never listens.
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

    /// For image samples: a fixed state, no registration.
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

    /// What a shortcut sets off. Actions without a handler (launcher-only
    /// mode: everything but the launcher) are not registered.
    func setHandler(_ action: HotKeyAction, _ handler: @escaping @MainActor () -> Void) {
        handlers[action] = handler
    }

    /// Once after the handlers are set. Delivers the current state first, then
    /// every change out of Nexus; lives as long as the app.
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

    /// Match the registered shortcuts up with the settings.
    private func apply() {
        guard live, recording == nil else { return }
        let wanted = store.settings.hotKeys
        // Unregister everything that changes first: otherwise swapping two
        // shortcuts would fail because the other one is still registered.
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
                log.error("\(action.rawValue, privacy: .public): \(key.display(), privacy: .public) not registered (OSStatus \(error.status, privacy: .public))")
            }
        }
        if failed != failures { failures = failed }
    }

    private func unregisterAll() {
        for entry in registered.values { entry.hotKey.unregister() }
        registered = [:]
    }

    // MARK: - Recording

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
        // When one switches apps, no more keys arrive - then do not get stuck
        // with unregistered shortcuts.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelRecording() }
        }
    }

    /// Cancel without changing anything (⎋, the window closes, another app).
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

    /// `true`: the key press is used up (it goes to no field and no menu).
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
            // Go on recording: try the next combination right away.
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

    /// Only the four that make up a shortcut; the caps lock, fn and numeric
    /// keypad flags (which come along with F and arrow keys) fall away.
    static func modifiers(from flags: NSEvent.ModifierFlags) -> HotKeyModifiers {
        var result: HotKeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}

/// The label of a key on the current keyboard layout. Carbon only knows the
/// place of the key (kVK_ANSI_Z is the Y on a German keyboard) - so for
/// letters and punctuation the display asks macOS (UCKeyTranslate, without
/// modifiers). Everything else stands in `HotKeyKey`.
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
            // Dead keys (´ ^ `) as their own character, not as "nothing".
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
            )
            return status == noErr ? String(utf16CodeUnits: chars, count: length) : ""
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !trimmed.isEmpty else { return nil }
        // "ß" would become "SS" in capitals - better leave it small.
        let upper = trimmed.uppercased()
        return upper.count == trimmed.count ? upper : trimmed
    }
}

// MARK: - User interface

/// A field that shows a shortcut and records a new one on a click - like the
/// shortcut fields in System Settings (Keyboard > Keyboard Shortcuts).
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

            // Keep the room, so the field does not jump while recording.
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

/// One row: tile, action, recording field - below it, if need be, why it does
/// not work or what is tricky about it.
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
