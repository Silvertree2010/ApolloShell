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
    static let toasts = PackageResources.configs.appendingPathComponent("apolloshell-default/toasts.kdl")

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
    @Test("Karte sitzt 12 pt von Rand und Boden wie 0.1.4.2")
    func inset() async throws {
        let harness = try ShellHarness(try String(contentsOf: DefaultBatteryToastTests.toasts, encoding: .utf8))
        try await harness.start()
        let t = try #require(harness.runtime.surface("default", screenKey: ShellHarness.a.key))
        guard case .number(let ox)? = Optional(t.property("offset-x")), case .number(let oy)? = Optional(t.property("offset-y")) else {
            Issue.record("offset fehlt")
            return
        }
        let p = SurfacePlacement(anchor: .bottomRight, area: .full, margin: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8), offsetX: CGFloat(ox), offsetY: CGFloat(oy))
        let f = p.frame(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), visible: CGRect(x: 0, y: 0, width: 1440, height: 900), fitting: CGSize(width: 422, height: 72))
        #expect(1440 - f.maxX + 8 == 12)
        #expect(f.minY + 8 == 12)
        harness.shell.shutdown()
    }
}
