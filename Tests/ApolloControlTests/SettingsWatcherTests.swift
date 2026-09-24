import Testing
import Foundation
import ApolloConfig
@testable import ApolloControl

@Suite("settings.kdl beobachten", .serialized)
struct SettingsWatcherTests {
    @Test("Schreiben von aussen wird ohne Nachfrage übernommen")
    func picksUpExternalWrite() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let file = folder.path("settings.kdl")
        let store = SettingsStore(file: file)
        let watcher = SettingsFileWatcher(store: store)
        watcher.start()
        defer { watcher.stop() }
        try Data("theme \"Nord\"\n".utf8).write(to: file, options: .atomic)
        #expect(waitUntil { store.settings.theme == "Nord" })
        try Data("theme \"Dusk\"\n".utf8).write(to: file, options: .atomic)
        #expect(waitUntil { store.settings.theme == "Dusk" })
    }

    @Test("der Ordner darf erst später entstehen")
    func folderCreatedLater() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let file = folder.url.appendingPathComponent("cfg/apolloshell/settings.kdl")
        let store = SettingsStore(file: file)
        let watcher = SettingsFileWatcher(store: store)
        watcher.start()
        defer { watcher.stop() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        usleep(100_000)
        try Data("config \"user\"\n".utf8).write(to: file, options: .atomic)
        #expect(waitUntil { store.settings.config == "user" })
    }

    @Test("Schreiben in die bestehende Datei wird erkannt")
    func inPlaceWrite() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let file = folder.path("settings.kdl")
        try Data("theme \"A\"\n".utf8).write(to: file)
        let store = SettingsStore(file: file)
        let watcher = SettingsFileWatcher(store: store)
        watcher.start()
        defer { watcher.stop() }
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("theme \"B\"\n".utf8))
        try handle.close()
        #expect(waitUntil { store.settings.theme == "B" })
    }
}
