import Testing
import Foundation
@testable import ApolloConfig

@Suite("ConfigFileSystem")
struct ConfigFileSystemTests {
    @Test("MemoryFileSystem liest, schreibt und listet")
    func memoryFileSystemBasics() throws {
        let fileSystem = MemoryFileSystem(["/root/shell.kdl": "panel {}"])
        #expect(try fileSystem.read(URL(fileURLWithPath: "/root/shell.kdl")) == "panel {}")
        #expect(fileSystem.exists(URL(fileURLWithPath: "/root/shell.kdl")))
        #expect(fileSystem.isDirectory(URL(fileURLWithPath: "/root")))
        #expect(!fileSystem.exists(URL(fileURLWithPath: "/root/missing.kdl")))
        try fileSystem.write("dock {}", to: URL(fileURLWithPath: "/root/dock.kdl"))
        let entries = try fileSystem.contentsOfDirectory(URL(fileURLWithPath: "/root")).map(\.lastPathComponent).sorted()
        #expect(entries == ["dock.kdl", "shell.kdl"])
        try fileSystem.copyItem(URL(fileURLWithPath: "/root/dock.kdl"), to: URL(fileURLWithPath: "/root/dock-copy.kdl"))
        #expect(try fileSystem.read(URL(fileURLWithPath: "/root/dock-copy.kdl")) == "dock {}")
    }

    @Test("DiskFileSystem schreibt und liest atomar")
    func diskFileSystemRoundtrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileSystem = DiskFileSystem()
        let file = directory.appendingPathComponent("settings.kdl")
        try fileSystem.write("theme \"Afterglow\"\n", to: file)
        #expect(fileSystem.exists(file))
        #expect(try fileSystem.read(file) == "theme \"Afterglow\"\n")
    }
}
