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
        kdl.runtime.open("settings", screenKey: nil)
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
        let roots = shell.fixture.surface("settings").root + (shell.runtime.surface("settings-confirm", screenKey: "A")?.root ?? [])
        let matches = all(roots).filter { element in
            element.kind == kind && (name.map { classes(element).contains($0) } ?? true) && texts(element).contains(text)
        }
        return try #require(matches.last, "no \(kind) with text \(text)")
    }

    static func row(_ shell: KDLShell, _ title: String) throws -> ElementInstance {
        let rows = all(shell.fixture.surface("settings").root).filter { $0.kind == "row" && !classes($0).contains("button-content") && texts($0).first == title }
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

    @Test("Sidebar: Galerie fügt nach dem Dock ein, Optionen schreiben ins Modul, Vorlage erst nach Rückfrage")
    func sidebarPage() async throws {
        let shell = try await Self.loaded()
        set(shell, "settings-page", .string("sidebar"))
        set(shell, "settings-sidebar-gallery", .bool(true))
        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "settings-gallery-tile", text: "Clock"))
        #expect(list(shell, "sidebar-modules").map { $0["id"] } == ["dashboard-button", "spaces", "dock", "clock-2", "clock", "utilities-button", "status-icons", "power"].map { .string($0) })
        #expect(list(shell, "sidebar-modules")[3]["show-icon"] == .bool(true))
        #expect(shell.vars.value("settings-sidebar-gallery") == .bool(false))

        set(shell, "settings-sidebar-gallery", .bool(true))
        let dock = try Self.find(shell, kind: "button", withClass: "settings-gallery-tile", text: "Dock")
        #expect(dock.property("disabled") == .bool(true))

        set(shell, "settings-sidebar-expanded", .string("clock-2"))
        await fire(shell, "on-change", try Self.toggle(in: Self.row(shell, "Show Date")), Record([("value", .bool(true))]))
        #expect(list(shell, "sidebar-modules")[3]["show-date"] == .bool(true))
        #expect(list(shell, "sidebar-modules")[4]["show-date"] == .bool(false))

        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "settings-button", text: "Reset"))
        #expect(shell.vars.value("settings-sidebar-confirm") == .string("reset"))
        #expect(shell.runtime.surface("settings-confirm", screenKey: "A")?.isOpen == true)
        #expect(list(shell, "sidebar-modules").count == 8)
        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "settings-default-button", text: "Reset"))
        #expect(list(shell, "sidebar-modules").count == 7)
        #expect(shell.vars.value("settings-sidebar-confirm") == .string(""))
        #expect(shell.runtime.surface("settings-confirm", screenKey: "A")?.isOpen == false)

        set(shell, "settings-sidebar-confirm", .string("minimal"))
        shell.runtime.open("settings-confirm", screenKey: nil)
        await shell.settle()
        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "settings-default-button", text: "Load"))
        #expect(list(shell, "sidebar-modules").map { $0["kind"] } == ["spaces", "spacer", "clock", "power"].map { .string($0) })
        set(shell, "settings-sidebar-confirm", .string("everything"))
        shell.runtime.open("settings-confirm", screenKey: nil)
        await shell.settle()
        shell.runtime.close("settings-confirm")
        await shell.settle()
        #expect(shell.vars.value("settings-sidebar-confirm") == .string(""))
        #expect(list(shell, "sidebar-modules").count == 4)
        #expect(shell.fixture.warnings.isEmpty, "\(shell.fixture.warnings.map(\.message))")
    }

    @Test("Control Centre: Karte aus, eigener Knopf aus der Galerie, Titel per Enter, Vorlage")
    func controlCentrePage() async throws {
        let shell = try await Self.loaded()
        set(shell, "settings-page", .string("control-centre"))
        await fire(shell, "on-change", try Self.toggle(in: Self.row(shell, "Sound")), Record([("value", .bool(false))]))
        #expect(list(shell, "utilities-cards").map { $0["enabled"] } == [.bool(true), .bool(false), .bool(true), .bool(false), .bool(false), .bool(false)])

        set(shell, "settings-toggle-gallery", .bool(true))
        #expect(try Self.find(shell, kind: "button", withClass: "settings-gallery-tile", text: "Wi-Fi").property("disabled") == .bool(true))
        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "settings-gallery-tile", text: "Open App"))
        set(shell, "settings-toggle-gallery", .bool(true))
        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "settings-gallery-tile", text: "Hide Apps"))
        set(shell, "settings-toggle-gallery", .bool(true))
        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "settings-gallery-tile", text: "Open App"))
        #expect(list(shell, "utilities-toggles").suffix(3).map { $0["id"] } == [.string("open-app"), .string("hide-apps"), .string("open-app-2")])

        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "settings-toggle-tile", text: "Open App"))
        #expect(shell.vars.value("settings-toggle-selected") == .string("open-app-2"))
        set(shell, "settings-toggle-title", .string("Mail"))
        let inputs = Self.all(shell.fixture.surface("settings").root).filter { $0.kind == "input" && $0.property("placeholder") == .string("Automatic") }
        let title = try #require(inputs.first)
        await fire(shell, "on-submit", title)
        #expect(list(shell, "utilities-toggles").last?["title"] == .string("Mail"))

        set(shell, "settings-utilities-confirm", .string("minimal"))
        shell.runtime.open("settings-confirm", screenKey: nil)
        await shell.settle()
        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "settings-default-button", text: "Load"))
        #expect(list(shell, "utilities-toggles").count == 5)
        #expect(shell.fixture.warnings.isEmpty, "\(shell.fixture.warnings.map(\.message))")
    }

    @Test("Dashboard: letzter sichtbarer Reiter gesperrt, Galerie legt Karte in die erste Zone mit Platz")
    func dashboardPage() async throws {
        let shell = try await Self.loaded()
        set(shell, "settings-page", .string("dashboard"))
        for tab in ["Media", "Performance", "Weather"] {
            await fire(shell, "on-change", try Self.toggle(in: Self.row(shell, tab)), Record([("value", .bool(false))]))
        }
        #expect(list(shell, "dashboard-tabs").map { $0["visible"] } == [.bool(true), .bool(false), .bool(false), .bool(false)])
        #expect(try Self.toggle(in: Self.row(shell, "Dashboard")).property("disabled") == .bool(true))

        #expect(shell.vars.value("weather-places") == .list([]))
        set(shell, "settings-dashboard-gallery", .bool(true))
        #expect(shell.vars.value("settings-dashboard-free-top") == .number(627 - 24 - 275 - 230))
        #expect(shell.vars.value("settings-dashboard-free-side") == .number(0))
        set(shell, "dashboard-cards-bottom", .list([]))
        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "settings-gallery-tile", text: "Clock"))
        #expect(list(shell, "dashboard-cards-bottom").map { $0["kind"] } == [.string("clock")])
        set(shell, "settings-dashboard-gallery", .bool(true))
        #expect(try Self.find(shell, kind: "button", withClass: "settings-gallery-tile", text: "Weather").property("disabled") == .bool(true))

        set(shell, "settings-dashboard-confirm", .string("compact"))
        shell.runtime.open("settings-confirm", screenKey: nil)
        await shell.settle()
        await fire(shell, "on-click", try Self.find(shell, kind: "button", withClass: "settings-default-button", text: "Load"))
        #expect(shell.vars.value("dashboard-cards-side") == .list([]))
        #expect(list(shell, "dashboard-cards-top").map { $0["kind"] } == [.string("weather"), .string("media")])
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
