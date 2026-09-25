import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloShell

@MainActor
@Suite("Globale Aktionen laufen live", .serialized)
struct GlobalActionsTests {
    @Test("Jede Aktion der Registry hat in der laufenden Shell einen Ausführer")
    func everyRegistryActionIsHandled() async throws {
        let (home, shell) = try await CommandCenterWiringTests.started()
        defer { shell.shutdown(); try? FileManager.default.removeItem(at: home.root) }
        let actions = try #require(shell.assembly?.actions)
        let names = Set(SchemaRegistry.builtin.actions.keys).union(SchemaRegistry.builtin.providers.values.flatMap { $0.actions.map(\.name) })
        let missing = names.filter { !actions.handles($0) }.sorted()
        #expect(missing.isEmpty, "\(missing)")
    }

    @Test("open-url, clipboard.copy, pick-file, config.select und exec wirken")
    func effects() async throws {
        let (home, shell) = try await CommandCenterWiringTests.started()
        defer { shell.shutdown(); try? FileManager.default.removeItem(at: home.root) }
        var opened: [URL] = []
        var copied: [String] = []
        shell.globalEffects.openURL = { opened.append($0); return true }
        shell.globalEffects.copy = { copied.append($0) }
        shell.globalEffects.pick = { _, _ in URL(fileURLWithPath: "/Applications/Finder.app") }
        _ = try await shell.runActions("open-url \"https://open-meteo.com\"")
        _ = try await shell.runActions("clipboard.copy \"hello\"")
        _ = try await shell.runActions("pick-file \"file-manager\"")
        #expect(opened == [URL(string: "https://open-meteo.com")!])
        #expect(copied == ["hello"])
        #expect(shell.assembly?.vars.value("file-manager") == .string("/Applications/Finder.app"))

        let marker = home.root.appendingPathComponent("exec-ran")
        _ = try await shell.runActions("exec \"touch '\(marker.path)'\"")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: marker.path) { RunLoopPump.run(0.02) }
        #expect(FileManager.default.fileExists(atPath: marker.path))

        _ = try await shell.runActions("config.select \"launcher-only\"")
        #expect(shell.settings.settings.config == "launcher-only")
        #expect(!shell.overlay.problems.contains { $0.message.contains("unknown action") })
    }

    @Test("shell.* aus der Registry ist live belegt: features, configs, themes, install-kind, update")
    func shellFields() async throws {
        let (home, shell) = try await CommandCenterWiringTests.started()
        defer { shell.shutdown(); try? FileManager.default.removeItem(at: home.root) }
        let store = try #require(shell.assembly?.store)
        func field(_ path: String...) -> Value { store.value(DependencyPath("shell", path)) }
        guard case .list(let features) = field("features"), case .list(let configs) = field("configs"), case .list = field("themes") else {
            Issue.record("missing lists")
            return
        }
        #expect(features.contains(.string("script-sources")))
        #expect(configs.contains { if case .record(let record) = $0 { record["id"] == .string("apolloshell-default") } else { false } })
        #expect(field("install-kind") == .string("dmg"))
        #expect(field("update", "status") != .null)
    }
}
