import Testing
import Foundation
import ApolloConfig
import ApolloShellCore
@testable import ApolloControl

final class ChangeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(ShellSettingsFile, ShellSettingsFile)] = []

    func add(_ old: ShellSettingsFile, _ new: ShellSettingsFile) {
        lock.withLock { entries.append((old, new)) }
    }

    var all: [(ShellSettingsFile, ShellSettingsFile)] { lock.withLock { entries } }
}

@Suite("settings.kdl zur Laufzeit")
struct SettingsStoreTests {
    static let file = URL(fileURLWithPath: "/cfg/apolloshell/settings.kdl")

    @Test("ohne Datei gelten die Vorgaben und nichts wird angelegt")
    func missingFile() {
        let fileSystem = MemoryFileSystem()
        let store = SettingsStore(file: Self.file, fileSystem: fileSystem)
        #expect(store.settings == ShellSettingsFile())
        #expect(store.diagnostics.isEmpty)
        #expect(!fileSystem.exists(Self.file))
    }

    @Test("eine Änderung legt die Datei erst dann an")
    func createsOnChange() throws {
        let fileSystem = MemoryFileSystem()
        let store = SettingsStore(file: Self.file, fileSystem: fileSystem)
        try store.apply(.theme("Afterglow"))
        let written = try fileSystem.read(Self.file)
        #expect(ShellSettingsFile.parse(written, file: "s").0.theme == "Afterglow")
        #expect(written.split(separator: "\n").count == 1)
        #expect(store.settings.theme == "Afterglow")
    }

    @Test("Kommentare und Formatierung des Users bleiben stehen")
    func keepsComments() throws {
        let text = "// meine Einstellungen\nconfig   \"user\"  // bleibt\ncrash-reports \"ask\"\n"
        let fileSystem = MemoryFileSystem([Self.file.path: text])
        let store = SettingsStore(file: Self.file, fileSystem: fileSystem)
        try store.apply(.crashReports("never"))
        let written = try fileSystem.read(Self.file)
        #expect(written.hasPrefix("// meine Einstellungen\nconfig   \"user\"  // bleibt\n"))
        #expect(written.split(separator: "\n").count == 3)
        #expect(ShellSettingsFile.parse(written, file: "s").0.crashReports == "never")
        #expect(store.settings.crashReports == "never")
        #expect(store.settings.config == "user")
    }

    @Test("eine kaputte Datei wird nie überschrieben")
    func brokenFileStays() throws {
        let text = "config \"user\n"
        let fileSystem = MemoryFileSystem([Self.file.path: text])
        let store = SettingsStore(file: Self.file, fileSystem: fileSystem)
        #expect(!store.diagnostics.isEmpty)
        #expect(throws: SettingsStoreError.self) { try store.apply(.theme("X")) }
        #expect(try fileSystem.read(Self.file) == text)
    }

    @Test("Beobachter bekommen alt und neu, gleiche Werte melden nichts")
    func observers() throws {
        let fileSystem = MemoryFileSystem()
        let store = SettingsStore(file: Self.file, fileSystem: fileSystem)
        let log = ChangeLog()
        let token = store.observe { log.add($0, $1) }
        try store.apply(.updates(autoCheck: false, autoInstall: true))
        try store.apply(.updates(autoCheck: false, autoInstall: true))
        #expect(log.all.count == 1)
        #expect(log.all.first?.0.autoCheckUpdates == true)
        #expect(log.all.first?.1.autoCheckUpdates == false)
        token.cancel()
        try store.apply(.theme("Y"))
        #expect(log.all.count == 1)
    }

    @Test("fremde Änderung an der Datei wird beim Nachlesen erkannt")
    func externalChange() throws {
        let fileSystem = MemoryFileSystem()
        let store = SettingsStore(file: Self.file, fileSystem: fileSystem)
        let log = ChangeLog()
        let token = store.observe { log.add($0, $1) }
        defer { token.cancel() }
        #expect(store.reload() == false)
        try fileSystem.write("theme \"Z\"\nbogus 1\n", to: Self.file)
        #expect(store.reload() == true)
        #expect(store.settings.theme == "Z")
        #expect(store.diagnostics.map(\.message) == ["unknown settings.kdl node 'bogus'"])
        #expect(log.all.count == 1)
        #expect(store.reload() == false)
    }

    @Test("Tippfehler beim Bearbeiten: der letzte lesbare Stand bleibt aktiv, mit Warnung, und nach der Korrektur gilt der neue")
    func brokenEditKeepsLastGood() throws {
        let fileSystem = MemoryFileSystem([Self.file.path: "config \"mine\"\ntheme \"Afterglow\"\n"])
        let store = SettingsStore(file: Self.file, fileSystem: fileSystem)
        let log = ChangeLog()
        let token = store.observe { log.add($0, $1) }
        defer { token.cancel() }
        try fileSystem.write("config \"mine\"\ntheme \"Afterglow\n", to: Self.file)
        #expect(store.reload() == false)
        #expect(store.settings.config == "mine")
        #expect(store.settings.theme == "Afterglow")
        #expect(store.diagnostics.contains { $0.message.contains("could not be parsed") })
        #expect(log.all.isEmpty)
        try fileSystem.write("config \"mine\"\ntheme \"Nord\"\n", to: Self.file)
        #expect(store.reload() == true)
        #expect(store.settings.theme == "Nord")
        #expect(store.diagnostics.isEmpty)
        #expect(log.all.count == 1)
    }

    @Test("Crash-Report-Modus wird gelesen, Unbekanntes gilt als ask")
    func crashMode() throws {
        let fileSystem = MemoryFileSystem([Self.file.path: "crash-reports \"always\""])
        #expect(SettingsStore(file: Self.file, fileSystem: fileSystem).crashReportMode == CrashReportSettings.Mode.always)
        try fileSystem.write("crash-reports \"sometimes\"", to: Self.file)
        #expect(SettingsStore(file: Self.file, fileSystem: fileSystem).crashReportMode == CrashReportSettings.Mode.ask)
    }

    @Test("Gleichzeitige Änderungen aus zwei Threads gehen nicht verloren")
    func concurrentApply() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings-race-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SettingsStore(file: folder.appendingPathComponent("settings.kdl"))
        await withTaskGroup(of: Void.self) { group in
            for round in 0..<40 {
                group.addTask { try? store.apply(round % 2 == 0 ? .theme("t\(round)") : .config("c\(round)")) }
            }
        }
        let text = try String(contentsOf: folder.appendingPathComponent("settings.kdl"), encoding: .utf8)
        let parsed = ShellSettingsFile.parse(text, file: "settings.kdl").0
        #expect(parsed.theme != nil)
        #expect(parsed.config != nil)
        #expect(parsed == store.settings)
    }
}
