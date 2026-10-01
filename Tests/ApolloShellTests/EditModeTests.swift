import Testing
import Foundation
import ApolloBase
import ApolloConfig
import ApolloControl
@testable import ApolloShell

@MainActor
@Suite("Global edit mode: one state for the whole shell", .serialized)
struct EditModeTests {
    func v(_ h: ShellHarness, _ n: String) -> Value? { h.shell.assembly?.vars.value(n) }

    static let config = """
    include "builtin:apolloshell-default/shell.kdl"
    on "user.t-begin" { use "edit-begin" }
    on "user.t-cancel" { use "edit-cancel" }
    on "user.t-done" { use "edit-done" }
    on "user.t-bar" { use "edit-add-bar" list="{event.list}" catalog="{event.list == 'sidebar-modules' ? var.sidebar-module-kinds : var.menubar-module-kinds}" kind="{event.kind}" present="{event.list == 'sidebar-modules' ? var.sidebar-modules : var.menubar-start}" at="{event.at}" }
    on "user.t-move" { use "edit-move-bar" value="{event.value}" to="{event.to}" at="{event.at}" }
    on "user.t-cc" { use "edit-add-cc" value="{event.value}" }
    """

    func run(_ h: ShellHarness, _ a: String) async throws { _ = try await h.shell.runActions(a); h.settle() }

    func ev(_ h: ShellHarness, _ n: String, _ f: [(String, Value)] = []) async {
        for task in h.shell.assembly?.runtime.emit("user.\(n)", Record(f)) ?? [] { await task.value }
        h.settle()
    }

    func kinds(_ h: ShellHarness, _ n: String) -> [String] {
        guard case .list(let l)? = v(h, n) else { return [] }
        return l.compactMap { if case .record(let r) = $0, case .string(let k)? = r["kind"] { return k } else { return nil } }
    }

    func start() async throws -> ShellHarness {
        let h = try ShellHarness(Self.config)
        try await h.start()
        return h
    }

    @Test("begin backs up every list and opens dashboard, control centre and toolbar")
    func begin() async throws {
        let h = try await start()
        defer { h.shell.shutdown() }
        await ev(h, "t-begin")
        #expect(v(h, "shell-editing") == .bool(true))
        #expect(v(h, "edit-backup-sidebar") == v(h, "sidebar-modules"))
        #expect(v(h, "edit-backup-cards") == v(h, "utilities-cards"))
        #expect(v(h, "edit-backup-toggles") == v(h, "utilities-toggles"))
        #expect(v(h, "dashboard-changed") == .bool(false))
    }

    @Test("adding to sidebar, menu bar and control centre counts as a change and cancel restores everything")
    func cancelRestores() async throws {
        let h = try await start()
        defer { h.shell.shutdown() }
        let side = kinds(h, "sidebar-modules")
        let toggles = kinds(h, "utilities-toggles")
        await ev(h, "t-begin")
        await ev(h, "t-bar", [("list", .string("sidebar-modules")), ("kind", .string("cpu"))])
        await ev(h, "t-bar", [("list", .string("menubar-start")), ("kind", .string("timer"))])
        await ev(h, "t-cc", [("value", .string("toggle:mute"))])
        await ev(h, "t-cc", [("value", .string("card:timer"))])
        #expect(kinds(h, "sidebar-modules") == side + ["cpu"])
        #expect(kinds(h, "menubar-start").last == "timer")
        #expect(kinds(h, "utilities-toggles") == toggles + (toggles.contains("mute") ? [] : ["mute"]))
        #expect(v(h, "dashboard-changed") == .bool(true))
        await ev(h, "t-cancel")
        #expect(kinds(h, "sidebar-modules") == side)
        #expect(kinds(h, "menubar-start").contains("timer") == false)
        #expect(kinds(h, "utilities-toggles") == toggles)
        #expect(v(h, "shell-editing") == .bool(false))
    }

    @Test("a unique kind that is already present is not added twice and done keeps the changes")
    func uniqueAndDone() async throws {
        let h = try await start()
        defer { h.shell.shutdown() }
        await ev(h, "t-begin")
        let n = kinds(h, "sidebar-modules").count
        await ev(h, "t-bar", [("list", .string("sidebar-modules")), ("kind", .string("dock"))])
        #expect(kinds(h, "sidebar-modules").count == n)
        await ev(h, "t-bar", [("list", .string("sidebar-modules")), ("kind", .string("divider")), ("at", .number(0))])
        #expect(kinds(h, "sidebar-modules").first == "divider")
        await ev(h, "t-done")
        #expect(kinds(h, "sidebar-modules").first == "divider" && v(h, "shell-editing") == .bool(false))
    }

    @Test("removing a card only disables it and the gallery drop enables it again")
    func cards() async throws {
        let h = try await start()
        defer { h.shell.shutdown() }
        await ev(h, "t-begin")
        func on(_ k: String) -> Bool? {
            guard case .list(let l)? = v(h, "utilities-cards") else { return nil }
            for x in l { if case .record(let r) = x, r["kind"] == .string(k), case .bool(let b)? = r["enabled"] { return b } }
            return nil
        }
        try await run(h, "list.update \"utilities-cards\" at=\"{var.utilities-cards | index-where 'kind' ['brightness']}\" { - enabled=#false }")
        #expect(on("brightness") == false)
        await ev(h, "t-cc", [("value", .string("card:brightness"))])
        #expect(on("brightness") == true)
        try await run(h, "list.update \"utilities-cards\" at=\"{var.utilities-cards | index-where 'kind' ['audio']}\" { - enabled=#false }")
        #expect(on("audio") == false)
        await ev(h, "t-cc", [("value", .string("card:audio"))])
        #expect(on("audio") == true)
    }

    @Test("a fast user switch cancels the mode and restores the layout")
    func sessionInactive() async throws {
        let h = try await start()
        defer { h.shell.shutdown() }
        let side = kinds(h, "sidebar-modules")
        await ev(h, "t-begin")
        try await run(h, "list.remove \"sidebar-modules\" at=0")
        for task in h.shell.assembly?.runtime.emit("system.session-inactive", Record()) ?? [] { await task.value }
        h.settle()
        #expect(v(h, "shell-editing") == .bool(false))
        #expect(kinds(h, "sidebar-modules") == side)
    }

    @Test("the command center offers Edit Layout")
    func entry() async throws {
        let (home, shell) = try await CommandCenterWiringTests.started()
        defer { shell.shutdown(); try? FileManager.default.removeItem(at: home.root) }
        #expect(CommandCenterWiringTests.titles(shell.commandCenterEntries()).contains("Edit Layout…"))
    }

    @Test("selecting a block with options opens its popover and done closes it")
    func optionsPopover() async throws {
        let h = try await start()
        defer { h.shell.shutdown() }
        await ev(h, "t-begin")
        try await run(h, "set \"dashboard-selected\" \"sidebar-modules:clock\"; set \"edit-opt\" \"sidebar-modules:clock\"")
        #expect(v(h, "edit-opt-sb-open") == .bool(true))
        #expect(v(h, "edit-opt-mb-open") == .bool(false))
        try await run(h, "set \"dashboard-selected\" \"menubar-end:clock\"; set \"edit-opt\" \"menubar-end:clock\"")
        #expect(v(h, "edit-opt-mb-open") == .bool(true))
        #expect(v(h, "edit-opt-sb-open") == .bool(false))
        try await run(h, "set \"dashboard-selected\" \"sidebar-modules:power\"; set \"edit-opt\" \"sidebar-modules:power\"")
        #expect(v(h, "edit-opt-sb-open") == .bool(false))
        await ev(h, "t-cc", [("value", .string("toggle:hide-apps"))])
        try await run(h, "set \"dashboard-selected\" \"utilities-toggles:hide-apps\"; set \"edit-opt\" \"utilities-toggles:hide-apps\"")
        #expect(v(h, "edit-opt-tg-open") == .bool(true))
        try await run(h, "set \"edit-opt\" #null")
        #expect(v(h, "edit-opt-tg-open") == .bool(false))
    }

    @Test("show all in the gallery starts off, toggles and resets on begin")
    func showAll() async throws {
        let h = try await start()
        defer { h.shell.shutdown() }
        await ev(h, "t-begin")
        #expect(v(h, "edit-show-all") == .bool(false))
        try await run(h, "set \"edit-show-all\" #true")
        #expect(v(h, "edit-show-all") == .bool(true))
        await ev(h, "t-cancel")
        await ev(h, "t-begin")
        #expect(v(h, "edit-show-all") == .bool(false))
    }

    @Test("a menu bar block dropped on another zone moves there and the same zone is left to the reorder")
    func crossZone() async throws {
        let h = try await start()
        defer { h.shell.shutdown() }
        await ev(h, "t-begin")
        let a = kinds(h, "menubar-start")
        let b = kinds(h, "menubar-center")
        await ev(h, "t-move", [("value", .string("move:start:app-menus")), ("to", .string("center")), ("at", .number(0))])
        #expect(kinds(h, "menubar-start") == a.filter { $0 != "app-menus" })
        #expect(kinds(h, "menubar-center") == ["app-menus"] + b)
        await ev(h, "t-move", [("value", .string("move:center:app-menus")), ("to", .string("center")), ("at", .number(0))])
        #expect(kinds(h, "menubar-center") == ["app-menus"] + b)
        await ev(h, "t-cancel")
        #expect(kinds(h, "menubar-start") == a)
    }
}

@MainActor
@Suite("Drag sources offer every operation a drop target answers with")
struct DragMaskTests {
    @Test("a value drop answers with copy, so the source mask must contain it")
    func mask() {
        #expect(ElementMouseView.sourceMask.contains(.copy))
        #expect(ElementMouseView.sourceMask.contains(.move))
    }
}

@Suite("Edit mode bars take values dragged in")
struct EditAcceptTests {
    @Test("every edit reorderable carries accept=value, because the drop only reaches it through that property")
    func accept() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/configs/apolloshell-default")
        let wanted = [("sidebar.kdl", "sidebar-modules"), ("menubar.kdl", "menubar-edit-list"), ("utilities.kdl", "quick-toggles"), ("utilities.kdl", "utilities-edit-list")]
        for (file, cls) in wanted {
            let text = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            let line = try #require(text.split(separator: "\n").first { $0.contains("reorderable") && $0.contains("class=\"\(cls)\"") })
            #expect(line.contains("accept=\"value\""))
        }
    }
}
