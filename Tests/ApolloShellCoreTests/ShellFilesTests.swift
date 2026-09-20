import Foundation
import Testing
@testable import ApolloShellCore

@Suite("File paths")
struct ShellFilesTests {
    @Test("the real directory lives under Application Support/ApolloShell")
    func liveDirectory() {
        let directory = ShellFiles.live.directory
        #expect(directory.lastPathComponent == "ApolloShell")
        #expect(directory.deletingLastPathComponent().lastPathComponent == "Application Support")
    }

    // Existing installations read exactly these names. If anything changes
    // here, settings, pins, and weather locations are gone after the update.
    @Test("file names stay as they were published")
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

    @Test("same paths as the former derivation from usage.json")
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

    @Test("writing creates missing directories, an unreadable file survives as a copy")
    func writeAndPreserve() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellFilesTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let url = ShellFiles(directory: base.appendingPathComponent("new", isDirectory: true)).settings

        try ShellFiles.write(Data("broken".utf8), to: url)
        #expect(ShellFiles.read(url) == Data("broken".utf8))
        #expect(ShellFiles.read(nil) == nil)
        #expect(!ShellFiles.isJSONObject(Data("broken".utf8)))
        #expect(ShellFiles.isJSONObject(Data("{}".utf8)))

        ShellFiles.preserveUnreadable(url)
        ShellFiles.preserveUnreadable(url) // twice: replaces the old copy
        let copy = url.appendingPathExtension("unreadable")
        #expect(ShellFiles.read(copy) == Data("broken".utf8))
    }
}
