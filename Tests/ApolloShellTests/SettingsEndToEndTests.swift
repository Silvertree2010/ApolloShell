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
        #expect(Self.isOpen(shell, "onboarding"))
        try await Self.click(shell, "onboarding", "onboarding-next")
        #expect(Self.value(shell, "onboarding-step") == .number(1))
        try await Self.click(shell, "onboarding", "onboarding-back")
        #expect(Self.value(shell, "onboarding-step") == .number(0))
        for _ in 0..<3 { try await Self.click(shell, "onboarding", "onboarding-next") }
        #expect(Self.value(shell, "onboarding-step") == .number(3))
        try await Self.click(shell, "onboarding", "onboarding-next")
        #expect(!Self.isOpen(shell, "onboarding"))
        #expect(Self.value(shell, "onboarding-done") == .bool(true))
        shell.shutdown()

        let again = try await Self.start(home)
        defer { again.shutdown() }
        #expect(Self.value(again, "onboarding-done") == .bool(true))
        #expect(!Self.isOpen(again, "onboarding"))
    }

    @Test("Einführung: Überspringen und Fensterknopf speichern ebenfalls")
    func onboardingSkipAndClose() async throws {
        let home = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let shell = try await Self.start(home)
        try await Self.click(shell, "onboarding", "onboarding-skip")
        #expect(!Self.isOpen(shell, "onboarding"))
        shell.shutdown()
        let again = try await Self.start(home)
        #expect(!Self.isOpen(again, "onboarding"))
        again.assembly?.runtime.open("onboarding", screenKey: nil)
        await Self.settle(again)
        again.shutdown()

        let other = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: other.root) }
        let first = try await Self.start(other)
        first.assembly?.runtime.close("onboarding")
        await Self.settle(first)
        first.shutdown()
        let second = try await Self.start(other)
        defer { second.shutdown() }
        #expect(!Self.isOpen(second, "onboarding"))
    }

    @Test("Gespeicherte Einstellungen stehen nach Neustart wieder da")
    func persistedAfterRestart() async throws {
        let home = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let shell = try await Self.start(home)
        let vars = try #require(shell.assembly?.vars)
        let changes: [(String, Value)] = [
            ("hide-apple-dock", .bool(true)), ("keep-awake-lid", .bool(true)), ("desktop-clock", .bool(false)),
            ("toast-charging", .bool(false)), ("toast-battery", .bool(false)), ("toast-audio-output", .bool(false)), ("toast-audio-input", .bool(false)),
            ("hotkey-launcher", .string("")), ("hotkey-dashboard", .string("cmd+shift+d")), ("hotkey-utilities", .string("f19")), ("hotkey-settings", .string("")),
            ("weather-source", .string("wttr")), ("file-manager", .string("com.apple.finder")),
            ("sidebar-screens", .string("main")), ("sidebar-background", .string("glass")),
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
        await Self.settle(again)
        #expect(Self.isOpen(again, "dashboard"))
    }

    static func disabledResets(_ shell: LiveShell) async throws -> [Bool] {
        shell.assembly?.runtime.open("settings", screenKey: nil)
        var result: [Bool] = []
        for page in ["sidebar", "control-centre", "dashboard"] {
            _ = shell.assembly?.vars.set("settings-page", .string(page))
            await settle(shell)
            let roots = try #require(surface(shell, "settings")).root
            let resets = all(roots).filter { element in
                element.kind == "button" && all([element]).contains { $0.kind == "text" && $0.arguments.first?.value == .string("Reset") }
            }
            result.append(try #require(resets.last).property("disabled") == .bool(true))
        }
        return result
    }

    @Test("Listen der Einstellungsseiten überstehen den Neustart unverändert, Zurücksetzen bleibt gesperrt")
    func listsAfterRestart() async throws {
        let home = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let shell = try await Self.start(home)
        let vars = try #require(shell.assembly?.vars)
        let names = ["sidebar-modules", "utilities-cards", "utilities-toggles", "dashboard-tabs", "dashboard-cards-top", "dashboard-cards-bottom", "dashboard-cards-side"]
        let original = names.map { vars.value($0) }
        #expect(try await Self.disabledResets(shell) == [true, true, true])
        for name in names { #expect(vars.set(name, .list([]))) }
        await Self.settle(shell)
        #expect(try await Self.disabledResets(shell) == [false, false, false])
        for (name, value) in zip(names, original) { #expect(vars.set(name, value)) }
        await Self.settle(shell)
        #expect(try await Self.disabledResets(shell) == [true, true, true])
        shell.shutdown()
        let again = try await Self.start(home)
        defer { again.shutdown() }
        for (name, value) in zip(names, original) {
            #expect(again.assembly?.vars.value(name) == value, "\(name)")
        }
        #expect(try await Self.disabledResets(again) == [true, true, true])
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

    @Test("Tastenkürzel-Seite: Aufnehmen, Default und Hyper Key schreiben die richtigen var und registrieren")
    func shortcutsPage() async throws {
        let home = try Self.freshHome()
        defer { try? FileManager.default.removeItem(at: home.root) }
        let shell = try await Self.start(home)
        defer { shell.shutdown() }
        let runtime = try #require(shell.assembly?.runtime)
        runtime.open("settings", screenKey: nil)
        _ = shell.assembly?.vars.set("settings-page", .string("shortcuts"))
        await Self.settle(shell)
        let recorders = Self.all(try #require(Self.surface(shell, "settings")).root).filter { $0.kind == "key-recorder" }
        #expect(recorders.count == 4)
        let chords = ["cmd+alt+1", "cmd+alt+2", "cmd+alt+3", "cmd+alt+4"]
        for (recorder, chord) in zip(recorders, chords) {
            await runtime.trigger("on-change", on: recorder.identity, event: Record([("chord", .string(chord))]))?.value
        }
        await Self.settle(shell)
        #expect(["hotkey-launcher", "hotkey-dashboard", "hotkey-utilities", "hotkey-settings"].map { Self.value(shell, $0) } == chords.map { .string($0) })
        let after = Self.all(try #require(Self.surface(shell, "settings")).root).filter { $0.kind == "key-recorder" }
        #expect(after.map { $0.property("value") } == chords.map { .string($0) })
        let registrar = try #require(shell.registrar as? FakeRegistrar)
        for chord in chords { #expect(registrar.active[try #require(KeyChord.parse(chord)).canonical] != nil, "\(chord)") }
        let buttons = Self.all(try #require(Self.surface(shell, "settings")).root).filter { element in
            element.kind == "button" && Self.all([element]).contains { $0.kind == "text" && ($0.arguments.first?.value == .string("Hyper Key")) }
        }
        await runtime.trigger("on-click", on: try #require(buttons.last).identity, event: Record())?.value
        await Self.settle(shell)
        #expect(["hotkey-launcher", "hotkey-dashboard", "hotkey-utilities", "hotkey-settings"].map { Self.value(shell, $0) } == ["f20", "hyper+d", "hyper+u", "hyper+comma"].map { .string($0) })
    }

    static func ids(_ shell: LiveShell, _ name: String) -> [Value] {
        guard case .list(let items)? = value(shell, name) else { return [] }
        return items.compactMap { if case .record(let record) = $0 { record["id"] } else { nil } }
    }

    @Test("Jede Einstellungsseite, jede Option, jede Rückfrage und jeder Einführungsschritt ohne Warnung")
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
            _ = vars.set("onboarding-step", .number(Double(step)))
            await Self.settle(shell)
        }
        runtime.open("settings", screenKey: nil)
        for page in ["general", "shortcuts", "sidebar", "control-centre", "launcher", "dashboard", "desktop", "toasts", "providers", "system-settings", "about"] {
            _ = vars.set("settings-page", .string(page))
            await Self.settle(shell)
        }
        _ = vars.set("settings-page", .string("sidebar"))
        _ = vars.set("settings-sidebar-gallery", .bool(true))
        for id in Self.ids(shell, "sidebar-modules") {
            _ = vars.set("settings-sidebar-expanded", id)
            await Self.settle(shell)
        }
        _ = vars.set("settings-page", .string("control-centre"))
        _ = vars.set("settings-toggle-gallery", .bool(true))
        for id in Self.ids(shell, "utilities-toggles") {
            _ = vars.set("settings-toggle-selected", id)
            await Self.settle(shell)
        }
        _ = vars.set("settings-page", .string("dashboard"))
        _ = vars.set("settings-dashboard-gallery", .bool(true))
        for zone in ["top", "bottom", "side"] {
            for id in Self.ids(shell, "dashboard-cards-" + zone) {
                _ = vars.set("settings-dashboard-expanded", id)
                await Self.settle(shell)
            }
        }
        let areas: [(page: String, confirm: String, presets: [String], lists: [String], expand: String)] = [
            ("sidebar", "settings-sidebar-confirm", ["minimal", "dock-only", "everything", "reset"], ["sidebar-modules"], "settings-sidebar-expanded"),
            ("control-centre", "settings-utilities-confirm", ["minimal", "audio", "everything", "reset"], ["utilities-toggles"], "settings-toggle-selected"),
            ("dashboard", "settings-dashboard-confirm", ["compact", "calendar-weather", "caelestia", "reset"], ["dashboard-cards-top", "dashboard-cards-bottom", "dashboard-cards-side"], "settings-dashboard-expanded"),
        ]
        for area in areas {
            _ = vars.set("settings-page", .string(area.page))
            for preset in area.presets {
                let previous = area.lists.map { vars.value($0) }
                _ = vars.set(area.confirm, .string(preset))
                runtime.open("settings-confirm", screenKey: nil)
                await Self.settle(shell)
                try await Self.click(shell, "settings-confirm", "settings-default-button")
                #expect(!Self.isOpen(shell, "settings-confirm"))
                if preset != "reset" { #expect(area.lists.map { vars.value($0) } != previous, "\(area.page) \(preset)") }
                for list in area.lists {
                    for id in Self.ids(shell, list) {
                        _ = vars.set(area.expand, id)
                        await Self.settle(shell)
                    }
                }
            }
        }
        let after = shell.overlay.problems.map(\.message) + (shell.assembly?.warnings.map(\.message) ?? [])
        #expect(after.isEmpty, "\(after)")
    }
}
