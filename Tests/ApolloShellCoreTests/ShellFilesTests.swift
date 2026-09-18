import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Dateipfade")
struct ShellFilesTests {
    @Test("Der echte Ordner liegt unter Application Support/ApolloShell")
    func liveDirectory() {
        let directory = ShellFiles.live.directory
        #expect(directory.lastPathComponent == "ApolloShell")
        #expect(directory.deletingLastPathComponent().lastPathComponent == "Application Support")
    }

    // Bestehende Installationen lesen genau diese Namen. Aendert sich hier
    // etwas, sind Einstellungen, Pins und Wetterorte nach dem Update weg.
    @Test("Dateinamen bleiben, wie sie veroeffentlicht sind")
    func fileNames() {
        let files = ShellFiles(directory: URL(fileURLWithPath: "/base", isDirectory: true))
        #expect(files.settings.path == "/base/settings.json")
        #expect(files.pinned.path == "/base/pinned.json")
        #expect(files.usage.path == "/base/usage.json")
        #expect(files.weather.path == "/base/weather.json")
        #expect(files.appleDock.path == "/base/apple-dock.json")
        #expect(files.lidAwakeMarker.path == "/base/lid-awake")
        #expect(files.themes.path == "/base/themes")
    }

    @Test("Gleiche Pfade wie die fruehere Herleitung aus usage.json")
    func matchesOldDerivation() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldUsage = support.appendingPathComponent("ApolloShell/usage.json")
        let oldDirectory = oldUsage.deletingLastPathComponent()
        #expect(ShellFiles.live.usage == oldUsage)
        #expect(ShellFiles.live.pinned == oldDirectory.appendingPathComponent("pinned.json"))
        #expect(ShellFiles.live.settings == oldDirectory.appendingPathComponent("settings.json"))
        #expect(ShellFiles.live.weather == support.appendingPathComponent("ApolloShell/weather.json"))
        #expect(ShellFiles.live.lidAwakeMarker == support.appendingPathComponent("ApolloShell/lid-awake"))
    }

    @Test("Schreiben legt fehlende Ordner an, eine unlesbare Datei bleibt als Kopie")
    func writeAndPreserve() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellFilesTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let url = ShellFiles(directory: base.appendingPathComponent("neu", isDirectory: true)).settings

        try ShellFiles.write(Data("kaputt".utf8), to: url)
        #expect(ShellFiles.read(url) == Data("kaputt".utf8))
        #expect(ShellFiles.read(nil) == nil)
        #expect(!ShellFiles.isJSONObject(Data("kaputt".utf8)))
        #expect(ShellFiles.isJSONObject(Data("{}".utf8)))

        ShellFiles.preserveUnreadable(url)
        ShellFiles.preserveUnreadable(url) // zweimal: ersetzt die alte Kopie
        let copy = url.appendingPathExtension("unreadable")
        #expect(ShellFiles.read(copy) == Data("kaputt".utf8))
    }
}
