import Testing
import Foundation
import ApolloBase
import ApolloConfig
import ApolloControl
@testable import ApolloShell

@MainActor
@Suite("Kommandozentrale: Einträge der Config und Befehle", .serialized)
struct CommandCenterWiringTests {
    static func started() async throws -> (LegacyImportStartTests.Home, LiveShell) {
        let home = LegacyImportStartTests.Home(root: FileManager.default.temporaryDirectory.appendingPathComponent("command-center-\(UUID().uuidString)"))
        try FileManager.default.createDirectory(at: home.root, withIntermediateDirectories: true)
        let shell = try LegacyImportStartTests.shell(home)
        shell.openFolder = { _ in }
        shell.loginShellPath = { _ in "/usr/bin:/bin" }
        try await shell.start()
        return (home, shell)
    }

    static func titles(_ entries: [MenuEntry]) -> [String] {
        entries.flatMap { [$0.title] + titles($0.children ?? []) }
    }

    @Test("Eigene Einträge aus command-center erscheinen und führen ihre Aktionen aus")
    func configItems() async throws {
        let (home, shell) = try await Self.started()
        defer { shell.shutdown(); try? FileManager.default.removeItem(at: home.root) }
        let entries = shell.commandCenterEntries()
        #expect(Self.titles(entries).contains("Settings…"))
        guard case .custom(let handler)? = entries.first(where: { $0.title == "Settings…" })?.command else {
            Issue.record("Settings… has no handler")
            return
        }
        func settingsOpen() -> Bool {
            shell.host.screens.keys.contains { shell.assembly?.runtime.surface("settings", screenKey: $0)?.isOpen == true }
        }
        #expect(!settingsOpen())
        shell.perform(.custom(handler))
        for _ in 0..<50 where !settingsOpen() {
            await Task.yield()
            RunLoopPump.run(0.02)
        }
        #expect(settingsOpen())
    }

    @Test("Einstellungen der Kommandozentrale wirken und stehen im Menü")
    func settingsCommands() async throws {
        let (home, shell) = try await Self.started()
        defer { shell.shutdown(); try? FileManager.default.removeItem(at: home.root) }
        shell.perform(.setAutoCheck(false))
        shell.perform(.crashReports(.never))
        #expect(shell.settings.settings.autoCheckUpdates == false)
        #expect(shell.settings.crashReportMode == .never)
        let updates = shell.commandCenterEntries().first { $0.title == "Updates" }?.children ?? []
        #expect(updates.first { $0.title == "Check Automatically" }?.checked == false)
        let crash = shell.commandCenterEntries().first { $0.title == "Crash Reports" }?.children ?? []
        #expect(crash.first { $0.title == "Never Send" }?.checked == true)
    }

    @Test("Kopie als eigene Config wird angelegt und aktiv")
    func copyToOwnConfig() async throws {
        let (home, shell) = try await Self.started()
        defer { shell.shutdown(); try? FileManager.default.removeItem(at: home.root) }
        shell.perform(.copyToOwnConfig)
        #expect(shell.catalog.list().contains { $0.id == "apolloshell-default-copy" })
        #expect(shell.settings.settings.config == "apolloshell-default-copy")
        await shell.reload()?.value
        #expect(shell.location?.id == "apolloshell-default-copy")
    }

    @Test("Kommandozeilenwerkzeug: Link in ~/.local/bin, danach nicht mehr im Menü")
    func installCommandLineTool() async throws {
        let (home, shell) = try await Self.started()
        defer { shell.shutdown(); try? FileManager.default.removeItem(at: home.root) }
        #expect(Self.titles(shell.commandCenterEntries()).contains("Install Command Line Tool…"))
        shell.perform(.installCommandLineTool)
        #expect(shell.commandLineTool.isInstalled)
        #expect(!Self.titles(shell.commandCenterEntries()).contains("Install Command Line Tool…"))
    }
}
