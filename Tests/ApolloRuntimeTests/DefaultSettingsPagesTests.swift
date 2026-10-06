import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("Einstellungsseiten der Default-Config durch die Runtime")
struct DefaultSettingsPagesTests {
    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/configs/apolloshell-default")

    static func files() throws -> [String: String] {
        var files: [String: String] = [:]
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where ["kdl", "css"].contains(url.pathExtension) {
            let relative = String(url.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count))
            files["/config" + relative] = try String(contentsOf: url, encoding: .utf8)
        }
        return files
    }

    static func loaded() async throws -> KDLShell {
        var files = try files()
        let removed = files.removeValue(forKey: "/config/shell.kdl")
        let shell = try #require(removed)
        let kdl = KDLShell()
        let result = try await kdl.load(shell, extra: files, id: "apolloshell-default")
        #expect(kdl.apply(result))
        kdl.runtime.open("prefs", screenKey: nil)
        await kdl.settle()
        return kdl
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

    static func texts(_ element: ElementInstance) -> [String] {
        all([element]).compactMap { $0.kind == "text" ? $0.arguments.first.map { KDLShell.describe($0.value) } : nil }
    }

    static func classes(_ element: ElementInstance) -> [String] {
        guard case .string(let value) = element.property("class") else { return [] }
        return value.split(separator: " ").map(String.init)
    }

    static func find(_ shell: KDLShell, kind: String, withClass name: String? = nil, text: String) throws -> ElementInstance {
        let roots = shell.fixture.surface("prefs").root
        let matches = all(roots).filter { element in
            element.kind == kind && (name.map { classes(element).contains($0) } ?? true) && texts(element).contains(text)
        }
        return try #require(matches.last, "no \(kind) with text \(text)")
    }

    static func row(_ shell: KDLShell, _ title: String) throws -> ElementInstance {
        let rows = all(shell.fixture.surface("prefs").root).filter { $0.kind == "row" && (classes($0).contains("srow") || classes($0).contains("mrow")) && texts($0).first == title }
        return try #require(rows.first, "no row \(title)")
    }

    static func toggle(in row: ElementInstance) throws -> ElementInstance {
        let toggles = all([row]).filter { $0.kind == "toggle" }
        return try #require(toggles.first)
    }

    func set(_ shell: KDLShell, _ name: String, _ value: Value) {
        #expect(shell.vars.set(name, value, for: nil))
        shell.fixture.flush()
    }

    func fire(_ shell: KDLShell, _ handler: String, _ element: ElementInstance, _ event: Record = Record()) async {
        shell.runtime.trigger(handler, on: element.identity, event: event)
        await shell.settle()
    }

    func list(_ shell: KDLShell, _ name: String) -> [Record] {
        guard case .list(let items) = shell.vars.value(name) else { return [] }
        return items.compactMap { if case .record(let record) = $0 { record } else { nil } }
    }

    @Test("Leiste: Modul per Schalter ein, Desktops als Zahlen, Vorgaben zurück")
    func barPage() async throws {
        let shell = try await Self.loaded()
        set(shell, "pg", .string("bar"))
        #expect(list(shell, "bm").first { $0["id"] == .string("dock") }?["on"] == .bool(false))
        await fire(shell, "on-change", try Self.toggle(in: Self.row(shell, "Dock")), Record([("value", .bool(true))]))
        #expect(list(shell, "bm").first { $0["id"] == .string("dock") }?["on"] == .bool(true))
        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "sgb", text: "Numbers"))
        #expect(shell.vars.value("ws") == .string("num"))
        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "pill2", text: "Restore Defaults"))
        #expect(list(shell, "bm").first { $0["id"] == .string("dock") }?["on"] == .bool(false))
        #expect(shell.fixture.warnings.isEmpty, "\(shell.fixture.warnings.map(\.message))")
    }

    @Test("Schreibtisch: Uhr aus, Einstellung bleibt in der var")
    func desktopPage() async throws {
        let shell = try await Self.loaded()
        set(shell, "pg", .string("desk"))
        await fire(shell, "on-change", try Self.toggle(in: Self.row(shell, "Desktop Clock")), Record([("value", .bool(false))]))
        #expect(shell.vars.value("desktop-clock") == .bool(false))
        #expect(shell.fixture.warnings.isEmpty, "\(shell.fixture.warnings.map(\.message))")
    }

    @Test("Tastenkürzel: jede Aufnahme schreibt ihre var, Zurücksetzen holt die Vorgaben")
    func shortcutsPage() async throws {
        let shell = try await Self.loaded()
        set(shell, "pg", .string("keys"))
        let recorders = Self.all(shell.fixture.surface("prefs").root).filter { $0.kind == "key-recorder" }
        #expect(recorders.count == 5)
        await fire(shell, "on-change", try #require(recorders.first), Record([("chord", .string("cmd+alt+l"))]))
        #expect(shell.vars.value("hotkey-launcher") == .string("cmd+alt+l"))
        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "hk-reset", text: "Restore Defaults"))
        #expect(shell.vars.value("hotkey-launcher") == .string("alt+space"))
        #expect(shell.fixture.warnings.isEmpty, "\(shell.fixture.warnings.map(\.message))")
    }

    @Test("Aktionsformen der Seiten: Vorlagen-Namen in list.move-to, list.swap und list.update")
    func templatedListActions() async throws {
        let shell = KDLShell()
        let result = try await shell.load("""
        var dashboard-cards-top type="list" {
            - id="weather" kind="weather"
            - id="user" kind="user"
        }
        var dashboard-cards-side type="list" {
            - id="media" kind="media"
        }
        window "settings" {
            button id="move" {
                on-click { list.move-to "dashboard-cards-{'top'}" "dashboard-cards-{'side'}" from="{1}" to="{1}" }
            }
            button id="swap" {
                on-click { list.swap "dashboard-cards-{'top'}" "{0}" "dashboard-cards-{'side'}" "{0}" }
            }
            button id="update" {
                on-click { list.update "dashboard-cards-{'side'}" key="{'weather'}" { - show-range="{1 > 0}" } }
            }
        }
        """)
        shell.apply(result)
        for id in ["move", "swap", "update"] {
            let buttons = Self.all(shell.fixture.surface("settings").root).filter { $0.property("id") == .string(id) }
            let button = try #require(buttons.first)
            await fire(shell, "on-click", button)
        }
        #expect(list(shell, "dashboard-cards-top").map { $0["id"] } == [.string("media")])
        #expect(list(shell, "dashboard-cards-side").map { $0["id"] } == [.string("weather"), .string("user")])
        #expect(list(shell, "dashboard-cards-side").first?["show-range"] == .bool(true))
        #expect(shell.fixture.warnings.isEmpty, "\(shell.fixture.warnings.map(\.message))")
    }
}
