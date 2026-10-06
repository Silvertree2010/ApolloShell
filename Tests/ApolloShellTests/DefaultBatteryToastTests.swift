import Testing
import Foundation
import SwiftUI
import ApolloBase
import ApolloConfig
import ApolloRuntime
@testable import ApolloShell

@MainActor
@Suite("Akku-Warnungen der Default-Config")
struct DefaultBatteryToastTests {
    static let toasts = PackageResources.configs.appendingPathComponent("apolloshell-default/notify.kdl")

    @Test("Symbol je Stufe wie 0.1.4.2 (TO-03 bis TO-05)", arguments: [
        ("20", false, "battery.25percent"),
        ("10", false, "battery.0percent"),
        ("5", true, "minus.plus.batteryblock.exclamationmark.fill"),
    ])
    func symbolPerLevel(level: String, critical: Bool, symbol: String) async throws {
        let harness = try ShellHarness(try String(contentsOf: Self.toasts, encoding: .utf8))
        let clock = ToastClock()
        clock.install(harness.shell.toasts)
        try await harness.start()
        for task in harness.runtime.emit("battery.warning", Record([("level", .string(level)), ("title", .string("T")), ("body", .string("B")), ("critical", .bool(critical))])) {
            await task.value
        }
        harness.settle()
        let rows = harness.runtime.surface("default", screenKey: ShellHarness.a.key)?.root ?? []
        guard case .record(let toast)? = rows.first?.scope["toast"] else {
            Issue.record("kein Toast")
            return
        }
        #expect(toast["icon"] == .string(symbol))
        harness.shell.shutdown()
    }
}

@MainActor
@Suite("Toast-Abstand der Default-Config")
struct DefaultToastInsetTests {
    @Test("Mitteilungen hängen oben rechts am Bildschirmrand, die kurzen Hinweise oben in der Mitte")
    func inset() async throws {
        let harness = try ShellHarness(try String(contentsOf: DefaultBatteryToastTests.toasts, encoding: .utf8))
        try await harness.start()
        let t = try #require(harness.runtime.surface("default", screenKey: ShellHarness.a.key))
        #expect(t.property("anchor") == .string("top-right"))
        #expect(t.property("area") == .string("full"))
        let pill = try #require(harness.runtime.surface("pill", screenKey: ShellHarness.a.key))
        #expect(pill.property("anchor") == .string("top"))
        harness.shell.shutdown()
    }
}
