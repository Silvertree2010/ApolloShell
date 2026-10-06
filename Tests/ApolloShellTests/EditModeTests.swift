import Testing
import Foundation
import ApolloBase
import ApolloConfig
import ApolloControl
import ApolloRuntime
@testable import ApolloShell

@MainActor
@Suite("Global edit mode: one state for the whole shell", .serialized)
struct EditModeTests {
    func v(_ h: ShellHarness, _ n: String) -> Value? { h.shell.assembly?.vars.value(n) }

    static let config = "include \"builtin:apolloshell-default/shell.kdl\""

    func run(_ h: ShellHarness, _ a: String) async throws { _ = try await h.shell.runActions(a); h.settle() }

    func ev(_ h: ShellHarness, _ n: String, _ f: [(String, Value)] = []) async {
        for task in h.shell.assembly?.runtime.emit("user.\(n)", Record(f)) ?? [] { await task.value }
        h.settle()
    }

    func modules(_ h: ShellHarness) -> [(String, Bool)] {
        guard case .list(let l)? = v(h, "bm") else { return [] }
        return l.compactMap {
            if case .record(let r) = $0, case .string(let id)? = r["id"], case .bool(let on)? = r["on"] { return (id, on) } else { return nil }
        }
    }

    func start() async throws -> ShellHarness {
        let h = try ShellHarness(Self.config)
        try await h.start()
        return h
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

    @Test("the launcher action and the shortcut event start edit mode, done ends it and keeps the modules")
    func beginAndDone() async throws {
        let h = try await start()
        defer { h.shell.shutdown() }
        let before = modules(h)
        #expect(before.count == 9 && before.allSatisfy(\.1))
        await ev(h, "act-edit")
        #expect(v(h, "edit") == .bool(true))
        let bar = try #require(h.runtime.surface("bar", screenKey: ShellHarness.a.key))
        let toggles = Self.all(bar.root).filter { $0.kind == "button" && $0.property("class") == .string("bmx") }
        #expect(toggles.count == 9)
        await h.shell.assembly?.runtime.trigger("on-click", on: try #require(toggles.first).identity, event: Record())?.value
        h.settle()
        #expect(modules(h).first?.1 == false)
        await ev(h, "editdone")
        #expect(v(h, "edit") == .bool(false))
        #expect(modules(h).first?.1 == false)
        let hidden = Self.all(bar.root).contains { $0.property("id") == .string("i-logo") }
        #expect(!hidden)
    }

    @Test("the bar list can be reordered only in edit mode, the drag reorder moves the module")
    func reorder() async throws {
        let h = try await start()
        defer { h.shell.shutdown() }
        let bar = try #require(h.runtime.surface("bar", screenKey: ShellHarness.a.key))
        #expect(!Self.all(bar.root).contains { $0.kind == "reorderable" })
        try await run(h, "set \"edit\" #true")
        let list = try #require(Self.all(bar.root).first { $0.kind == "reorderable" })
        await h.shell.assembly?.runtime.trigger("on-reorder", on: list.identity, event: Record([("from", .number(0)), ("to", .number(2))]))?.value
        h.settle()
        let order = modules(h).map(\.0)
        #expect(order.first == "ws" && (order.firstIndex(of: "logo") ?? 0) > 0, "\(order)")
    }

    @Test("the command center offers Edit Bar")
    func entry() async throws {
        let (home, shell) = try await CommandCenterWiringTests.started()
        defer { shell.shutdown(); try? FileManager.default.removeItem(at: home.root) }
        #expect(CommandCenterWiringTests.titles(shell.commandCenterEntries()).contains("Edit Bar"))
    }

    @Test("choosing Edit Bar in the real menu item starts edit mode")
    func menuClick() async throws {
        let (home, shell) = try await CommandCenterWiringTests.started()
        defer { shell.shutdown(); try? FileManager.default.removeItem(at: home.root) }
        let b = CommandCenterMenu { shell.perform($0) }
        let m = b.make(shell.commandCenterEntries())
        let i = try #require(m.items.first { $0.title == "Edit Bar" })
        _ = i.target?.perform(i.action, with: i)
        for _ in 0..<50 where shell.assembly?.vars.value("edit") != .bool(true) {
            await Task.yield()
            RunLoopPump.run(0.02)
        }
        #expect(shell.assembly?.vars.value("edit") == .bool(true))
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
    @Test("the bar's reorderable exists only inside the edit branch and is always enabled there")
    func accept() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/configs/apolloshell-default")
        let text = try String(contentsOf: dir.appendingPathComponent("bar.kdl"), encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init)
        let index = try #require(lines.firstIndex { $0.contains("reorderable") && $0.contains("class=\"bmods\"") })
        #expect(lines[index].contains("enabled=#true"))
        #expect(lines[index - 1].contains("when \"{var.edit}\""))
    }
}
