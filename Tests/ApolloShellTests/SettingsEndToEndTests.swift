import Testing
import Foundation
import ApolloBase
import ApolloConfig
import ApolloControl
import ApolloRuntime
@testable import ApolloShell

@MainActor
@Suite("Einstellungen, Einführung und Kommandozentrale Ende-zu-Ende", .serialized)
struct SettingsEndToEndTests {
    typealias Home = LegacyImportStartTests.Home

    static func freshHome() throws -> Home {
        let home = Home(root: FileManager.default.temporaryDirectory.appendingPathComponent("settings-e2e-\(UUID().uuidString)"))
        try FileManager.default.createDirectory(at: home.root, withIntermediateDirectories: true)
        return home
    }

    static func start(_ home: Home) async throws -> LiveShell {
        let shell = try LegacyImportStartTests.shell(home)
        shell.openFolder = { _ in }
        shell.loginShellPath = { _ in "/usr/bin:/bin" }
        try await shell.start()
        await settle(shell)
        return shell
    }

    static func settle(_ shell: LiveShell) async {
        for _ in 0..<5 {
            await Task.yield()
            RunLoopPump.run(0.01)
        }
    }

    static func surface(_ shell: LiveShell, _ id: String) -> SurfaceInstance? {
        guard let runtime = shell.assembly?.runtime else { return nil }
        return shell.host.screens.keys.sorted().compactMap { runtime.surface(id, screenKey: $0) }.first { $0.isOpen }
            ?? shell.host.screens.keys.sorted().compactMap { runtime.surface(id, screenKey: $0) }.first
    }

    static func isOpen(_ shell: LiveShell, _ id: String) -> Bool {
        surface(shell, id)?.isOpen == true
    }

    static func all(_ roots: [ElementInstance]) -> [ElementInstance] {
        var out: [ElementInstance] = []
        var stack = Array(roots.reversed())
        while let element = stack.popLast() {
            out.append(element)
            stack.append(contentsOf: element.children.reversed())
            for slot in element.slotChildren.values { stack.append(contentsOf: slot.reversed()) }
        }
        return out
    }

    static func button(_ shell: LiveShell, _ surfaceID: String, withClass name: String) throws -> ElementInstance {
        let roots = try #require(surface(shell, surfaceID)).root
        let matches = all(roots).filter { element in
            guard element.kind == "button", case .string(let value) = element.property("class") else { return false }
            return value.split(separator: " ").contains(Substring(name))
        }
        return try #require(matches.first, "no button .\(name) in \(surfaceID)")
    }

    static func click(_ shell: LiveShell, _ surfaceID: String, _ name: String) async throws {
        let element = try button(shell, surfaceID, withClass: name)
        await shell.assembly?.runtime.trigger("on-click", on: element.identity, event: Record())?.value
        await settle(shell)
    }

    static func value(_ shell: LiveShell, _ name: String) -> Value? {
        shell.assembly?.vars.value(name)
    }

    @Test("Einführung: vor, zurück, Fertig speichert und erscheint nach Neustart nicht wieder")
    func onboardingDone() async throws {
        let home = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let shell = try await Self.start(home)
        #expect(Self.isOpen(shell, "ob"))
        try await Self.click(shell, "ob", "ob-next")
        #expect(Self.value(shell, "obs") == .number(1))
        try await Self.click(shell, "ob", "ob-back")
        #expect(Self.value(shell, "obs") == .number(0))
        for _ in 0..<3 { try await Self.click(shell, "ob", "ob-next") }
        #expect(Self.value(shell, "obs") == .number(3))
        try await Self.click(shell, "ob", "ob-next")
        #expect(!Self.isOpen(shell, "ob"))
        #expect(Self.value(shell, "onboarding-done") == .bool(true))
        shell.shutdown()

        let again = try await Self.start(home)
        defer { again.shutdown() }
        #expect(Self.value(again, "onboarding-done") == .bool(true))
        #expect(!Self.isOpen(again, "ob"))
    }

    @Test("Einführung: Überspringen und Fensterknopf speichern ebenfalls")
    func onboardingSkipAndClose() async throws {
        let home = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let shell = try await Self.start(home)
        try await Self.click(shell, "ob", "ob-skip")
        #expect(!Self.isOpen(shell, "ob"))
        shell.shutdown()
        let again = try await Self.start(home)
        #expect(!Self.isOpen(again, "ob"))
        again.shutdown()

        let other = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: other.root) }
        let first = try await Self.start(other)
        first.assembly?.runtime.close("ob")
        await Self.settle(first)
        first.shutdown()
        let second = try await Self.start(other)
        defer { second.shutdown() }
        #expect(!Self.isOpen(second, "ob"))
    }

    @Test("Gespeicherte Einstellungen stehen nach Neustart wieder da")
    func persistedAfterRestart() async throws {
        let home = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let shell = try await Self.start(home)
        let vars = try #require(shell.assembly?.vars)
        let changes: [(String, Value)] = [
            ("desktop-clock", .bool(false)), ("ws", .string("num")), ("h24", .bool(false)), ("tmin", .number(15)), ("dt", .string("perf")),
            ("hotkey-launcher", .string("")), ("hotkey-dashboard", .string("cmd+shift+d")), ("hotkey-utilities", .string("f19")), ("hotkey-settings", .string("")),
            ("file-manager", .string("com.apple.finder")),
        ]
        for (name, value) in changes {
            #expect(vars.set(name, value), "\(name)")
        }
        await Self.settle(shell)
        shell.shutdown()
        let again = try await Self.start(home)
        defer { again.shutdown() }
        for (name, value) in changes {
            #expect(Self.value(again, name) == value, "\(name)")
        }
        let registrar = try #require(again.registrar as? FakeRegistrar)
        let dashboard = try #require(KeyChord.parse("cmd+shift+d")).canonical
        let utilities = try #require(KeyChord.parse("f19")).canonical
        #expect(registrar.active[dashboard] != nil)
        #expect(registrar.active[utilities] != nil)
        #expect(registrar.active[try #require(KeyChord.parse("alt+space")).canonical] == nil)
        #expect(registrar.active[try #require(KeyChord.parse("ctrl+alt+comma")).canonical] == nil)
        registrar.press(dashboard)
        for _ in 0..<20 where !Self.isOpen(again, "dash") { await Self.settle(again) }
        #expect(Self.isOpen(again, "dash"))
    }

    @Test("Leistenmodule überstehen den Neustart, ausgeschaltete bleiben aus")
    func listsAfterRestart() async throws {
        let home = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let shell = try await Self.start(home)
        let vars = try #require(shell.assembly?.vars)
        guard case .list(var modules) = vars.value("bm"), case .record(var first)? = modules.first else {
            Issue.record("bm is no list")
            return
        }
        first["on"] = .bool(false)
        modules[0] = .record(first)
        modules.swapAt(1, 2)
        #expect(vars.set("bm", .list(modules)))
        await Self.settle(shell)
        shell.shutdown()
        let again = try await Self.start(home)
        defer { again.shutdown() }
        #expect(again.assembly?.vars.value("bm") == .list(modules))
    }

    static func checked(_ entries: [MenuEntry], _ menu: String) -> [String] {
        (entries.first { $0.title == menu }?.children ?? []).filter(\.checked).map(\.title)
    }

    @Test("Kommandozentrale: Theme und Config wählen, Häkchen stimmen nach Reload und Neustart")
    func commandCenterChecks() async throws {
        let home = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let folder = home.config.appendingPathComponent("themes/nacht")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ":root {\n  --apollo-theme-format: 1;\n  --apollo-theme-name: \"Nacht\";\n}\n".write(to: folder.appendingPathComponent("theme.css"), atomically: true, encoding: .utf8)
        let shell = try await Self.start(home)
        #expect(Self.checked(shell.commandCenterEntries(), "Theme") == ["None"])
        #expect(Self.checked(shell.commandCenterEntries(), "Config") == ["apolloshell-default"])
        shell.perform(.selectTheme("nacht"))
        await shell.reload()?.value
        #expect(Self.checked(shell.commandCenterEntries(), "Theme") == ["nacht"])
        shell.perform(.selectConfig("launcher-only"))
        await shell.reload()?.value
        #expect(shell.location?.id == "launcher-only")
        #expect(Self.checked(shell.commandCenterEntries(), "Config") == ["launcher-only"])
        shell.shutdown()
        let again = try await Self.start(home)
        #expect(again.location?.id == "launcher-only")
        #expect(Self.checked(again.commandCenterEntries(), "Theme") == ["nacht"])
        #expect(Self.checked(again.commandCenterEntries(), "Config") == ["launcher-only"])
        again.perform(.selectTheme(nil))
        again.perform(.selectConfig("apolloshell-default"))
        await again.reload()?.value
        #expect(Self.checked(again.commandCenterEntries(), "Theme") == ["None"])
        #expect(Self.checked(again.commandCenterEntries(), "Config") == ["apolloshell-default"])
        again.shutdown()
    }

    @Test("Tastenkürzel-Seite: Aufnehmen schreibt die richtigen var und registriert, Zurücksetzen holt die Vorgaben")
    func shortcutsPage() async throws {
        let home = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let shell = try await Self.start(home)
        defer { shell.shutdown() }
        let runtime = try #require(shell.assembly?.runtime)
        runtime.open("prefs", screenKey: nil)
        _ = shell.assembly?.vars.set("pg", .string("keys"))
        await Self.settle(shell)
        let recorders = Self.all(try #require(Self.surface(shell, "prefs")).root).filter { $0.kind == "key-recorder" }
        #expect(recorders.count == 5)
        let names = ["hotkey-launcher", "hotkey-dashboard", "hotkey-utilities", "hotkey-session", "hotkey-settings"]
        let defaults = names.map { Self.value(shell, $0) }
        let chords = ["cmd+alt+1", "cmd+alt+2", "cmd+alt+3", "cmd+alt+4", "cmd+alt+5"]
        for (recorder, chord) in zip(recorders, chords) {
            await runtime.trigger("on-change", on: recorder.identity, event: Record([("chord", .string(chord))]))?.value
        }
        await Self.settle(shell)
        #expect(names.map { Self.value(shell, $0) } == chords.map { .string($0) })
        let after = Self.all(try #require(Self.surface(shell, "prefs")).root).filter { $0.kind == "key-recorder" }
        #expect(after.map { $0.property("value") } == chords.map { .string($0) })
        let registrar = try #require(shell.registrar as? FakeRegistrar)
        for chord in chords { #expect(registrar.active[try #require(KeyChord.parse(chord)).canonical] != nil, "\(chord)") }
        try await Self.click(shell, "prefs", "hk-reset")
        #expect(names.map { Self.value(shell, $0) } == defaults)
    }

    @Test("Jede Einstellungsseite und jeder Einführungsschritt ohne Warnung")
    func sweepWithoutWarnings() async throws {
        let home = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let shell = try await Self.start(home)
        defer { shell.shutdown() }
        let vars = try #require(shell.assembly?.vars)
        let runtime = try #require(shell.assembly?.runtime)
        let before = shell.overlay.problems.map(\.message) + (shell.assembly?.warnings.map(\.message) ?? [])
        #expect(before.isEmpty, "\(before)")
        for step in 0...3 {
            _ = vars.set("obs", .number(Double(step)))
            await Self.settle(shell)
        }
        runtime.open("prefs", screenKey: nil)
        for page in ["look", "bar", "wx", "keys", "desk", "about"] {
            _ = vars.set("pg", .string(page))
            await Self.settle(shell)
        }
        for tab in ["dash", "media", "perf", "wx"] {
            _ = vars.set("dt", .string(tab))
            runtime.open("dash", screenKey: nil)
            await Self.settle(shell)
        }
        _ = vars.set("edit", .bool(true))
        await Self.settle(shell)
        _ = vars.set("edit", .bool(false))
        for name in ["net", "bt", "bat", "vol", "win"] {
            _ = vars.set("pv", .string(name))
            _ = vars.set("po", .bool(true))
            await Self.settle(shell)
        }
        let after = shell.overlay.problems.map(\.message) + (shell.assembly?.warnings.map(\.message) ?? [])
        #expect(after.isEmpty, "\(after)")
    }
}
