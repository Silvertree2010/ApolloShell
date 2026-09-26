import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("Kalenderkarte der Default-Config")
struct DefaultDashboardCalendarTests {
    @Test("Dashboard öffnen zeigt wieder den aktuellen Monat wie 0.1.4.2")
    func reopeningShowsCurrentMonth() async throws {
        let shell = try await DefaultSettingsPagesTests.loaded()
        shell.runtime.open("dashboard", screenKey: nil)
        await shell.settle()
        #expect(shell.vars.set("calendar-offset", .number(3), for: nil))
        shell.runtime.close("dashboard")
        shell.fixture.flush()
        shell.runtime.surfaceDidFinishClosing(id: "dashboard", screenKey: "A")
        shell.fixture.flush()
        shell.runtime.open("dashboard", screenKey: nil)
        await shell.settle()
        #expect(shell.vars.value("calendar-offset") == .number(0))
    }
}
