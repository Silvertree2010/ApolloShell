import Testing
import Foundation
import ApolloShellCore
@testable import ApolloControl

@Suite("Maschinen-Zustand in Application Support")
struct MachineStateTests {
    static let handled = Date(timeIntervalSinceReferenceDate: 780_000_000)
    static let checked = Date(timeIntervalSinceReferenceDate: 781_000_000)

    static func legacyJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        struct Legacy: Encodable {
            var crashReports: CrashReportSettings
            var updates: UpdateSettings
            var launcherOnly = false
        }
        return try encoder.encode(Legacy(crashReports: CrashReportSettings(mode: .always, handledUntil: handled), updates: UpdateSettings(lastCheck: checked)))
    }

    @Test("ohne eigene Datei gilt der Stand aus settings.json von 0.1.4.2")
    func seedsFromLegacy() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let legacy = try Self.legacyJSON()
        try legacy.write(to: folder.path("settings.json"))
        let state = MachineState(folder: folder.url)
        #expect(state.crashReportsHandledUntil == Self.handled)
        #expect(state.lastUpdateCheck == Self.checked)
        #expect(!FileManager.default.fileExists(atPath: folder.path("control-state.json").path))
    }

    @Test("Schreiben geht in die eigene Datei, settings.json bleibt unangetastet")
    func writesOwnFile() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let legacy = try Self.legacyJSON()
        try legacy.write(to: folder.path("settings.json"))
        let state = MachineState(folder: folder.url)
        let later = Self.checked.addingTimeInterval(60)
        state.lastUpdateCheck = later
        #expect(try Data(contentsOf: folder.path("settings.json")) == legacy)
        let reread = MachineState(folder: folder.url)
        #expect(reread.lastUpdateCheck == later)
        #expect(reread.crashReportsHandledUntil == Self.handled)
    }

    @Test("kaputte oder fehlende Dateien ergeben leeren Zustand")
    func brokenFiles() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        #expect(MachineState(folder: folder.url).lastUpdateCheck == nil)
        try Data("{".utf8).write(to: folder.path("control-state.json"))
        let state = MachineState(folder: folder.url)
        #expect(state.crashReportsHandledUntil == nil)
    }

    @Test("eine settings.json, die keine Datei ist, blockiert nicht und ergibt leeren Zustand")
    func legacyFifoDoesNotBlock() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        #expect(mkfifo(folder.path("settings.json").path, 0o600) == 0)
        final class Box: @unchecked Sendable { var state: MachineState? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let url = folder.url
        Thread {
            box.state = MachineState(folder: url)
            done.signal()
        }.start()
        #expect(done.wait(timeout: .now() + 5) == .success)
        #expect(box.state?.lastUpdateCheck == nil)
    }

    @Test("eine übergroße settings.json wird nicht gelesen")
    func oversizedLegacyIsIgnored() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        var legacy = try Self.legacyJSON()
        legacy.append(Data(repeating: 0x20, count: MachineState.maxBytes))
        try legacy.write(to: folder.path("settings.json"))
        #expect(MachineState(folder: folder.url).lastUpdateCheck == nil)
        try Self.legacyJSON().write(to: folder.path("settings.json"))
        #expect(MachineState(folder: folder.url).lastUpdateCheck == Self.checked)
    }
}
