import Testing
import AppKit
import ApolloBase
import ApolloConfig
import ApolloRuntime
@testable import ApolloShell

@MainActor
final class FakeRegistration: HotKeyRegistration {
    let chord: String
    weak var owner: FakeRegistrar?
    init(chord: String, owner: FakeRegistrar) {
        self.chord = chord
        self.owner = owner
    }
    func unregister() { owner?.active[chord] = nil }
}

@MainActor
final class FakeRegistrar: HotKeyRegistering {
    var active: [String: @MainActor () -> Void] = [:]
    var releases: [String: @MainActor () -> Void] = [:]
    var taken: Set<String> = []
    var registered: [String] = []

    func register(_ chord: KeyChord, pressed action: @escaping @MainActor () -> Void, released: (@MainActor () -> Void)?) -> Result<any HotKeyRegistration, HotKeyFailure> {
        if taken.contains(chord.canonical) { return .failure(HotKeyFailure(taken: true, status: -9878)) }
        registered.append(chord.canonical)
        active[chord.canonical] = action
        releases[chord.canonical] = released
        return .success(FakeRegistration(chord: chord.canonical, owner: self))
    }

    func press(_ chord: String) { active[chord]?() }
    func release(_ chord: String) { releases[chord]?() }
}

@MainActor
final class KeysFixture {
    let fixture: HostFixture
    let registrar = FakeRegistrar()
    let keys: BindHotKeys
    var warnings: [String] = []
    var published: [Value] = []
    var triggered: [String] = []

    init(_ shell: String, repeater: KeyRepeater = KeyRepeater()) throws {
        fixture = try HostFixture(shell)
        var sink: KeysFixture?
        keys = BindHotKeys(bindings: fixture.assembly.bindings, registrar: registrar, trigger: { sink?.triggered.append($0) },
                           warn: { sink?.warnings.append($0.message) }, publish: { sink?.published = $0 }, repeater: repeater)
        sink = self
        keys.apply(fixture.ir?.binds ?? [])
        fixture.flush()
    }
}

@MainActor
@Suite("Tastenkürzel des Hosts")
struct HostKeyTests {
    static let shell = """
    var launcher-key "alt+space"
    var hyper-on #true
    popup "menu" { row {} }
    bind "ctrl+alt+d" { toggle "menu" }
    bind "{var.launcher-key}" id="launcher" { toggle "menu" }
    bind "hyper+h" when="{var.hyper-on}" { toggle "menu" }
    """

    @Test("statisch und als Ausdruck angemeldet, Auslösen ruft das bind")
    func register() throws {
        let keys = try KeysFixture(Self.shell)
        #expect(Set(keys.registrar.active.keys) == ["ctrl+alt+d", "alt+space", "hyper+h"])
        keys.registrar.press("alt+space")
        #expect(keys.triggered == ["launcher"])
        #expect(keys.published.count == 3)
    }

    @Test("Ausdruck ändert sich: nur dieses Kürzel ab- und angemeldet; when schaltet")
    func changes() throws {
        let keys = try KeysFixture(Self.shell)
        let before = keys.registrar.registered.count
        _ = keys.fixture.assembly.vars.set("launcher-key", .string("cmd+space"))
        keys.fixture.flush()
        #expect(keys.registrar.active["alt+space"] == nil)
        #expect(keys.registrar.active["cmd+space"] != nil)
        #expect(keys.registrar.registered.count == before + 1)
        _ = keys.fixture.assembly.vars.set("hyper-on", .bool(false))
        keys.fixture.flush()
        #expect(keys.registrar.active["hyper+h"] == nil)
        _ = keys.fixture.assembly.vars.set("launcher-key", .string(""))
        keys.fixture.flush()
        #expect(keys.registrar.active["cmd+space"] == nil)
        #expect(keys.keys.unregistrations == 3)
    }

    @Test("Reload ohne Änderung meldet nichts neu an")
    func reloadUnchanged() throws {
        let keys = try KeysFixture(Self.shell)
        let count = keys.registrar.registered.count
        try keys.fixture.reload(Self.shell)
        keys.keys.apply(keys.fixture.ir?.binds ?? [])
        keys.fixture.flush()
        #expect(keys.registrar.registered.count == count)
        #expect(keys.keys.unregistrations == 0)
    }

    @Test("gleiche Laufzeit-Kombination: erstes gewinnt und warnt; belegt: ok falsch und warnt")
    func conflicts() throws {
        let keys = try KeysFixture(Self.shell)
        _ = keys.fixture.assembly.vars.set("launcher-key", .string("ctrl+alt+d"))
        keys.fixture.flush()
        #expect(keys.warnings.contains { $0.contains("already taken by bind 'ctrl+alt+d'") })
        keys.registrar.press("ctrl+alt+d")
        #expect(keys.triggered == ["ctrl+alt+d"])
        let taken = try KeysFixture("popup \"menu\" { row {} }")
        taken.registrar.taken = ["alt+space"]
        try taken.fixture.reload("popup \"menu\" { row {} }\nbind \"alt+space\" { toggle \"menu\" }")
        taken.keys.apply(taken.fixture.ir?.binds ?? [])
        #expect(taken.published == [.record(Record([("chord", .string("alt+space")), ("ok", .bool(false))]))])
        #expect(taken.warnings.contains { $0.contains("already used") })
    }

    @Test("Filter chord zeigt Zeichentasten nach aktueller Belegung")
    func chordFilter() {
        let german = LayoutFilterServices(keyName: { $0 == 0x10 ? "Z" : ($0 == 0x06 ? "Y" : nil) })
        #expect(german.chordDisplay("ctrl+y") == "⌃Z")
        #expect(german.chordDisplay("alt+space") == "⌥Space")
        #expect(german.chordDisplay("cmd+z") == "⌘Y")
        #expect(german.chordDisplay("nonsense+") == "nonsense+")
        let none = LayoutFilterServices(keyName: { _ in nil })
        #expect(none.chordDisplay("shift+a") == "⇧A")
    }

    @Test("key in einer Oberfläche: Tastenname aus dem Ereignis, Kanon wie bind")
    func keyNames() {
        #expect(KeyNameTable.name(for: 0x7E) == "up")
        #expect(KeyNameTable.name(for: 0x35) == "escape")
        #expect(KeyNameTable.canonical("cmd+ctrl+k") == "ctrl+cmd+k")
    }
}

@MainActor
@Suite("Overlay, Reload-Bündelung, Start")
struct HostOverlayStartTests {
    @Test("Fehler zeigen die Liste, Warnungen eine Plakette für 8 s")
    func overlay() {
        let model = ErrorOverlayModel()
        var scheduled: [(TimeInterval, @MainActor () -> Void)] = []
        model.schedule = { scheduled.append(($0, $1)) }
        model.show([Diagnostic(.warning, "w1"), Diagnostic(.warning, "w2")])
        #expect(model.state == .badge(2))
        #expect(scheduled.first?.0 == 8)
        scheduled.first?.1()
        #expect(model.state == .hidden)
        #expect(model.warningCount == 2)
        model.show([Diagnostic(.error, "broken", span: SourceSpan(file: "/c/shell.kdl", start: SourcePosition(offset: 0, line: 3, column: 5), end: SourcePosition(offset: 0, line: 3, column: 9)))])
        guard case .errors(let list) = model.state else {
            Issue.record("no errors state")
            return
        }
        #expect(ErrorOverlayModel.location(list[0]) == "shell.kdl:3:5")
        model.dismiss()
        #expect(model.state == .hidden)
        model.show([])
        #expect(model.state == .hidden)
    }

    @Test("Änderungen innerhalb von 150 ms ergeben einen Reload")
    func debounce() {
        var scheduled: [@MainActor () -> Void] = []
        let debouncer = ReloadDebouncer(schedule: { delay, work in
            #expect(delay == 0.15)
            scheduled.append(work)
        })
        var fired = 0
        debouncer.fire = { fired += 1 }
        debouncer.poke()
        debouncer.poke()
        debouncer.poke()
        scheduled.forEach { $0() }
        #expect(fired == 1)
    }

    @Test("Start: kaputte User-Config fällt auf die Default-Config zurück und zeigt das Overlay")
    func startFallback() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("start-\(UUID().uuidString)")
        let config = home.appendingPathComponent("apolloshell")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try "panel \"x\" {".write(to: config.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        let options = LiveShell.Options(config: nil, resources: PackageResources.root.appendingPathComponent("Resources"),
                                        fixture: PackageResources.root.appendingPathComponent("Resources/render/fixture.kdl"))
        let shell = LiveShell(options: options, host: WindowHost(factory: FakeFactory()), environment: ["XDG_CONFIG_HOME": home.path], home: home)
        shell.interactive = false
        shell.registrar = FakeRegistrar()
        #expect(shell.activeLocation().id == "user")
        try await shell.start()
        #expect(shell.steps == ["settings", "config", "styles", "surfaces", "services", "started"])
        #expect(shell.location?.id == "render-dock")
        guard case .errors = shell.overlay.state else {
            Issue.record("overlay shows no errors: \(shell.overlay.state)")
            return
        }
        #expect(shell.host.controllers.keys.contains { $0.hasPrefix("dock@") })
        shell.shutdown()
    }
}
