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
        shell.runtime.open("dash", screenKey: nil)
        await shell.settle()
        #expect(shell.vars.set("cal", .number(3), for: nil))
        shell.runtime.close("dash")
        shell.fixture.flush()
        shell.runtime.surfaceDidFinishClosing(id: "dash", screenKey: "A")
        shell.fixture.flush()
        shell.runtime.open("dash", screenKey: nil)
        await shell.settle()
        #expect(shell.vars.value("cal") == .number(0))
    }
}
