import Testing
import Foundation
import ApolloKDL
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

    @Test("DiskFileSystem liest keine Nicht-Dateien und höchstens 1 MB, die Grössenmeldung bleibt")
    func diskFileSystemReadsBounded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileSystem = DiskFileSystem()
        let fifo = directory.appendingPathComponent("state.kdl")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: ConfigFileSystemError.self) { try fileSystem.read(fifo) }
        let huge = directory.appendingPathComponent("huge.kdl")
        try Data(repeating: 0x61, count: 8 << 20).write(to: huge)
        #expect(try fileSystem.read(huge).utf8.count == DiskFileSystem.maxReadBytes + 1)
        let binary = directory.appendingPathComponent("binary.kdl")
        try Data([0xFF, 0xFE, 0x00]).write(to: binary)
        #expect(throws: ConfigFileSystemError.self) { try fileSystem.read(binary) }
        let shell = directory.appendingPathComponent("shell.kdl")
        try "include \"huge.kdl\"\n".write(to: shell, atomically: true, encoding: .utf8)
        let paths = ConfigPaths(builtinConfigs: directory, userConfig: directory, applicationSupport: directory)
        let result = IncludeExpander.expand(root: directory, origin: .user, fileSystem: fileSystem, paths: paths)
        #expect(result.diagnostics.map(\.message).contains { $0.hasSuffix("is larger than \(KDLLimits.maxBytes) bytes") })
    }
}
