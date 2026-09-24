import AppKit
import Carbon.HIToolbox
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

enum KeyNameTable {
    static let names: [String] = {
        var list = (UnicodeScalar("a").value...UnicodeScalar("z").value).map { String(UnicodeScalar($0)!) }
        list += (0...9).map(String.init)
        list += (1...20).map { "f\($0)" }
        list += ["space", "return", "tab", "escape", "delete", "forward-delete", "left", "right", "up", "down", "home", "end",
                 "pageup", "pagedown", "minus", "equal", "comma", "period", "slash", "semicolon", "quote", "grave", "backslash",
                 "[", "]", "keypad-enter"]
        return list
    }()

    static let byCode: [UInt32: String] = {
        var table: [UInt32: String] = [:]
        for name in names {
            if let chord = KeyChord.parse(name), table[chord.keyCode] == nil { table[chord.keyCode] = chord.key }
        }
        return table
    }()

    static func name(for keyCode: UInt32) -> String? { byCode[keyCode] }

    static func canonical(_ text: String) -> String? { KeyChord.parse(text)?.canonical }
}

struct LayoutFilterServices: FilterServices {
    let base: DefaultFilterServices
    let keyName: @Sendable (UInt32) -> String?

    init(base: DefaultFilterServices = DefaultFilterServices(), keyName: @escaping @Sendable (UInt32) -> String?) {
        self.base = base
        self.keyName = keyName
    }

    func chordDisplay(_ chord: String) -> String {
        guard let parsed = KeyChord.parse(chord) else { return chord }
        guard HotKeyKey.isCharacterKey(parsed.keyCode), let name = keyName(parsed.keyCode) else { return parsed.display }
        return parsed.modifiers.symbols + name
    }

    func appSearch(_ apps: [Value], query: String) -> [Value] { base.appSearch(apps, query: query) }
    func monthGrid(_ date: Date, offset: Int, firstWeekday: String) -> Value { base.monthGrid(date, offset: offset, firstWeekday: firstWeekday) }
    func uptimeText(_ seconds: Double) -> String { base.uptimeText(seconds) }
    func normalizedURL(_ text: String) -> String? { base.normalizedURL(text) }
    func symbolExists(_ name: String) -> Bool { base.symbolExists(name) }
    func hotkeyWarning(_ chord: String) -> String? { base.hotkeyWarning(chord) }
    func temperatureText(_ celsius: Double) -> String { base.temperatureText(celsius) }
}

enum KeyboardLayoutNames {
    static func keyName(for keyCode: UInt32) -> String? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { translate(keyCode) }
        }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { translate(keyCode) } }
    }

    @MainActor
    static func translate(_ keyCode: UInt32) -> String? {
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
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
            )
            return status == noErr ? String(utf16CodeUnits: chars, count: length) : ""
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !trimmed.isEmpty else { return nil }
        let upper = trimmed.uppercased()
        return upper.count == trimmed.count ? upper : trimmed
    }
}

@MainActor
protocol HotKeyRegistration: AnyObject {
    func unregister()
}

@MainActor
protocol HotKeyRegistering: AnyObject {
    func register(_ chord: KeyChord, pressed: @escaping @MainActor () -> Void, released: (@MainActor () -> Void)?) -> Result<any HotKeyRegistration, HotKeyFailure>
}

@MainActor
final class KeyRepeater {
    struct Timing: Equatable {
        var delay: TimeInterval
        var interval: TimeInterval

        static var system: Timing {
            Timing(delay: max(0.05, NSEvent.keyRepeatDelay), interval: max(0.01, NSEvent.keyRepeatInterval))
        }
    }

    typealias Schedule = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> DispatchWorkItem

    static let dispatch: Schedule = { delay, work in
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return item
    }

    private let timing: @MainActor () -> Timing
    private let schedule: Schedule
    private var running: [String: DispatchWorkItem] = [:]
    private var generations: [String: Int] = [:]

    init(timing: @escaping @MainActor () -> Timing = { .system }, schedule: @escaping Schedule = KeyRepeater.dispatch) {
        self.timing = timing
        self.schedule = schedule
    }

    var active: Set<String> { Set(running.keys) }

    func start(_ key: String, held: @escaping @MainActor () -> Bool = { true }, fire: @escaping @MainActor () -> Void) {
        stop(key)
        let generation = (generations[key] ?? 0) + 1
        generations[key] = generation
        let current = timing()
        step(key, generation: generation, after: current.delay, interval: current.interval, held: held, fire: fire)
    }

    private func step(_ key: String, generation: Int, after delay: TimeInterval, interval: TimeInterval, held: @escaping @MainActor () -> Bool, fire: @escaping @MainActor () -> Void) {
        running[key] = schedule(delay) { [weak self] in
            guard let self, self.generations[key] == generation, self.running[key] != nil else { return }
            guard held() else {
                self.stop(key)
                return
            }
            fire()
            self.step(key, generation: generation, after: interval, interval: interval, held: held, fire: fire)
        }
    }

    func stop(_ key: String) {
        running.removeValue(forKey: key)?.cancel()
        generations[key] = (generations[key] ?? 0) + 1
    }

    func stopAll() {
        for key in Array(running.keys) { stop(key) }
    }
}

struct HotKeyFailure: Error, Equatable {
    var taken: Bool
    var status: Int32
}

@MainActor
final class CarbonHotKeys: HotKeyRegistering {
    func register(_ chord: KeyChord, pressed: @escaping @MainActor () -> Void, released: (@MainActor () -> Void)?) -> Result<any HotKeyRegistration, HotKeyFailure> {
        switch GlobalHotKey.register(chord.hotKey, pressed: pressed, released: released) {
        case .success(let key): return .success(key)
        case .failure(let error): return .failure(HotKeyFailure(taken: error.alreadyTaken, status: error.status))
        }
    }
}

extension GlobalHotKey: HotKeyRegistration {}

@MainActor
final class BindHotKeys {
    private final class Entry {
        let bind: BindIR
        var chord: String?
        var active: Bool
        var handles: [BindingHandle] = []

        init(bind: BindIR) {
            self.bind = bind
            active = bind.when == nil
        }
    }

    private struct Registered {
        let id: String
        let repeats: Bool
        let registration: (any HotKeyRegistration)?
        let ok: Bool
    }

    private let bindings: BindingEngine
    private let registrar: any HotKeyRegistering
    private let trigger: @MainActor (String) -> Void
    private let warn: @MainActor (Diagnostic) -> Void
    private let publish: @MainActor ([Value]) -> Void
    let repeater: KeyRepeater
    private var entries: [Entry] = []
    private var registered: [String: Registered] = [:]
    private var warned: Set<String> = []
    private var applying = false
    private(set) var registrations = 0
    private(set) var unregistrations = 0
    var keyIsDown: @MainActor (UInt32) -> Bool = { CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) }
    var keyStateReadable: @MainActor () -> Bool = { CGPreflightListenEventAccess() }

    var hasFailures: Bool { registered.values.contains { !$0.ok } }
    var suspended = false {
        didSet { if suspended != oldValue { refresh() } }
    }

    func retryFailed() {
        guard hasFailures else { return }
        refresh()
    }

    init(bindings: BindingEngine, registrar: any HotKeyRegistering, trigger: @escaping @MainActor (String) -> Void, warn: @escaping @MainActor (Diagnostic) -> Void, publish: @escaping @MainActor ([Value]) -> Void, repeater: KeyRepeater = KeyRepeater()) {
        self.repeater = repeater
        self.bindings = bindings
        self.registrar = registrar
        self.trigger = trigger
        self.warn = warn
        self.publish = publish
    }

    var chords: [String: String] { registered.filter(\.value.ok).mapValues(\.id) }

    func apply(_ binds: [BindIR]) {
        var old = entries
        var next: [Entry] = []
        applying = true
        for bind in binds {
            if let index = old.firstIndex(where: { $0.bind == bind }) {
                next.append(old.remove(at: index))
                continue
            }
            let entry = Entry(bind: bind)
            entry.handles.append(bindings.bind(bind.chord, scope: LocalScope(), active: true) { [weak self, weak entry] value in
                guard let entry else { return }
                entry.chord = Self.chordText(value)
                self?.refresh()
            })
            if let when = bind.when {
                entry.handles.append(bindings.bind(when, scope: LocalScope(), active: true) { [weak self, weak entry] value in
                    guard let entry else { return }
                    entry.active = value.isTruthy
                    self?.refresh()
                })
            }
            next.append(entry)
        }
        for entry in old { entry.handles.forEach { $0.cancel() } }
        entries = next
        applying = false
        refresh()
    }

    static func chordText(_ value: Value) -> String? {
        guard case .string(let text) = value else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func refresh() {
        guard !applying else { return }
        var desired: [String: (id: String, chord: KeyChord, repeats: Bool)] = [:]
        var order: [String] = []
        for entry in entries where entry.active && !suspended {
            guard let text = entry.chord else { continue }
            guard let chord = KeyChord.parse(text) else {
                warnOnce("bad|" + text, "bind '\(entry.bind.id)': unknown key combination '\(text)'")
                continue
            }
            let canonical = chord.canonical
            if let first = desired[canonical] {
                warnOnce("dup|" + canonical + "|" + entry.bind.id, "bind '\(entry.bind.id)' uses \(canonical), already taken by bind '\(first.id)'")
                continue
            }
            desired[canonical] = (entry.bind.id, chord, entry.bind.repeats)
            order.append(canonical)
        }
        for (canonical, current) in registered where !current.ok || desired[canonical]?.id != current.id || desired[canonical]?.repeats != current.repeats {
            repeater.stop(canonical)
            if let registration = current.registration {
                registration.unregister()
                unregistrations += 1
            }
            registered[canonical] = nil
        }
        for canonical in order where registered[canonical] == nil {
            guard let wanted = desired[canonical] else { continue }
            let id = wanted.id
            let repeats = wanted.repeats
            let keyCode = wanted.chord.keyCode
            let pressed: @MainActor () -> Void = { [weak self] in
                guard let self else { return }
                self.trigger(id)
                if repeats {
                    self.repeater.start(canonical, held: { [weak self] in
                        guard let self else { return false }
                        return !self.keyStateReadable() || self.keyIsDown(keyCode)
                    }) { [weak self] in self?.trigger(id) }
                }
            }
            var released: (@MainActor () -> Void)?
            if repeats {
                released = { [weak self] in self?.repeater.stop(canonical) }
            }
            switch registrar.register(wanted.chord, pressed: pressed, released: released) {
            case .success(let registration):
                registrations += 1
                registered[canonical] = Registered(id: id, repeats: repeats, registration: registration, ok: true)
            case .failure(let failure):
                registered[canonical] = Registered(id: id, repeats: repeats, registration: nil, ok: false)
                warnOnce("fail|" + canonical, failure.taken
                    ? "shortcut \(canonical) is already used by another app"
                    : "shortcut \(canonical) could not be registered (\(failure.status))")
            }
        }
        guard !suspended else { return }
        publish(order.map { canonical in
            .record(Record([("chord", .string(canonical)), ("ok", .bool(registered[canonical]?.ok ?? false))]))
        })
    }

    private func warnOnce(_ key: String, _ message: String) {
        guard warned.insert(key).inserted else { return }
        warn(Diagnostic(.warning, message))
    }

    func removeAll() {
        repeater.stopAll()
        for entry in entries { entry.handles.forEach { $0.cancel() } }
        entries = []
        for current in registered.values { current.registration?.unregister() }
        registered = [:]
    }
}
