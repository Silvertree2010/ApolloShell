import Testing
import Foundation
import ApolloBase
import ApolloConfig

enum CheckHarness {
    static let executable = URL(fileURLWithPath: "/Applications/ApolloShell.app/Contents/Helpers/apollo")
    static let builtinRoot = "/Applications/ApolloShell.app/Contents/Resources/configs"
    static let environment = ["HOME": "/Users/tester"]

    static func run(_ arguments: [String], files: [String: String] = [:], environment: [String: String] = CheckHarness.environment) -> (output: String, exitCode: Int32) {
        CheckCommand.run(arguments: arguments, environment: environment, fileSystem: MemoryFileSystem(files), executableURL: executable)
    }

    static func runOnDisk(_ arguments: [String], environment: [String: String] = CheckHarness.environment) -> (output: String, exitCode: Int32) {
        CheckCommand.run(arguments: arguments, environment: environment, fileSystem: DiskFileSystem(), executableURL: executable)
    }

    static func temporaryDirectory(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func goldenFolder(_ name: String) -> URL {
        URL(fileURLWithPath: DiagnosticGolden.file(name, "shell.kdl")).deletingLastPathComponent()
    }

    static func goldenText(_ name: String) throws -> String {
        try DiskFileSystem().read(goldenFolder(name).appendingPathComponent("expected.txt"))
    }

    static func normalized(_ output: String, name: String) -> String {
        output.replacingOccurrences(of: goldenFolder(name).deletingLastPathComponent().path, with: DiagnosticGolden.fixturesPlaceholder)
    }
}

@Suite("apollo check")
struct CheckCommandTests {
    @Test("Ausgabe und Exit-Code gleich dem Golden File der Pipeline", arguments: ["pipeline", "use-zyklus"])
    func matchesGoldenFiles(name: String) throws {
        let folder = CheckHarness.goldenFolder(name)
        let result = CheckHarness.runOnDisk([folder.path])
        #expect(result.exitCode == 1)
        #expect(CheckHarness.normalized(result.output, name: name) == (try CheckHarness.goldenText(name)))
    }

    @Test("gueltige Config ergibt Exit 0 und keine Ausgabe")
    func validConfig() {
        let result = CheckHarness.run(["/work/bar"], files: ["/work/bar/shell.kdl": "panel \"bar\" {\n    text \"hi\"\n}\n"])
        #expect(result.exitCode == 0)
        #expect(result.output.isEmpty)
    }

    @Test("nur Warnungen ergeben Exit 0 mit Ausgabe")
    func warningsOnly() {
        let result = CheckHarness.run(["/work/bar"], files: ["/work/bar/shell.kdl": "panel \"bar\" override=#true {\n}\n"])
        #expect(result.exitCode == 0)
        #expect(result.output.hasPrefix("/work/bar/shell.kdl:1:1: warning: "))
    }

    @Test("mehr als 200 Diagnosen mit dem Fehler ganz hinten ergeben Exit 1")
    func errorBehindManyWarnings() {
        var shell = ""
        for index in 0..<250 {
            shell += "panel \"p\(index)\" override=#true {\n}\n"
        }
        shell += "pannel \"last\" {\n}\n"
        let result = CheckHarness.run(["/work/many"], files: ["/work/many/shell.kdl": shell])
        #expect(result.exitCode == 1)
        #expect(result.output.hasPrefix("/work/many/shell.kdl:501:1: error: unknown node 'pannel'"))
        #expect(result.output.hasSuffix("note: and 51 more"))
    }

    @Test("Ordner ohne shell.kdl ist ein Fehler")
    func folderWithoutShellFile() {
        let result = CheckHarness.run(["/work/empty"], files: ["/work/empty/notes.txt": "x"])
        #expect(result.exitCode == 1)
        #expect(result.output == "error: '/work/empty' has no shell.kdl")
    }

    @Test("Ordner, den es nicht gibt, ist ein Fehler")
    func missingFolder() {
        let result = CheckHarness.run(["/work/nowhere"])
        #expect(result.exitCode == 1)
        #expect(result.output == "error: '/work/nowhere' does not exist")
    }

    @Test("Datei statt Ordner ist falsche Benutzung")
    func fileInsteadOfFolder() {
        let result = CheckHarness.run(["/work/bar/shell.kdl"], files: ["/work/bar/shell.kdl": ""])
        #expect(result.exitCode == 2)
        #expect(result.output.hasPrefix("error: '/work/bar/shell.kdl' is not a folder"))
    }

    @Test("nicht lesbarer Ordner ist ein Fehler ohne Absturz")
    func unreadableFolder() throws {
        let folder = try CheckHarness.temporaryDirectory("locked")
        try "panel \"bar\" {\n}\n".write(to: folder.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let result = CheckHarness.runOnDisk([folder.path])
        #expect(result.exitCode == 1)
        #expect(result.output == "error: cannot read folder '\(folder.resolvingSymlinksInPath().path)'")
    }

    @Test("Pfad mit Leerzeichen und Umlauten")
    func pathWithSpacesAndUmlauts() throws {
        let folder = try CheckHarness.temporaryDirectory("Meine Größe äöü")
        try "panel \"bar\" {\n    buton\n}\n".write(to: folder.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        let result = CheckHarness.runOnDisk([folder.path])
        let file = folder.resolvingSymlinksInPath().appendingPathComponent("shell.kdl").path
        #expect(result.exitCode == 1)
        #expect(result.output.hasPrefix("\(file):2:5: error: unknown node 'buton'\n    2 |     buton\n"))
        let valid = try CheckHarness.temporaryDirectory("Zweite Größe")
        try "panel \"bar\" {\n}\n".write(to: valid.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        #expect(CheckHarness.runOnDisk([valid.path]).exitCode == 0)
    }

    @Test("Ausgabe ohne Farben und mit Home als Tilde")
    func plainOutputWithTilde() {
        let result = CheckHarness.run(["/Users/tester/dev/bar"], files: ["/Users/tester/dev/bar/shell.kdl": "buton\n"])
        #expect(result.exitCode == 1)
        #expect(result.output.hasPrefix("~/dev/bar/shell.kdl:1:1: error: unknown node 'buton'"))
        #expect(!result.output.contains("\u{1B}"))
    }

    @Test("falsche Benutzung ergibt Exit 2", arguments: [["a", "b"], ["--verbose"], ["-x", "a"]])
    func usageErrors(arguments: [String]) {
        let result = CheckHarness.run(arguments)
        #expect(result.exitCode == 2)
        #expect(result.output.contains("usage: apollo check [<folder>]"))
    }

    @Test("Hilfe ergibt Exit 0")
    func help() {
        let result = CheckHarness.run(["--help"])
        #expect(result.exitCode == 0)
        #expect(result.output.hasPrefix("usage: apollo check [<folder>]"))
    }

    @Test("ohne Ordner die eigene Config nach Regel 3")
    func activeUserConfig() {
        let result = CheckHarness.run([], files: ["/Users/tester/.config/apolloshell/shell.kdl": "buton\n"])
        #expect(result.exitCode == 1)
        #expect(result.output.hasPrefix("~/.config/apolloshell/shell.kdl:1:1: error: unknown node 'buton'"))
    }

    @Test("ohne Ordner zaehlt XDG_CONFIG_HOME")
    func activeConfigHonoursXDG() {
        let environment = ["HOME": "/Users/tester", "XDG_CONFIG_HOME": "/xdg"]
        let result = CheckHarness.run([], files: ["/xdg/apolloshell/shell.kdl": "buton\n"], environment: environment)
        #expect(result.output.hasPrefix("/xdg/apolloshell/shell.kdl:1:1: error: unknown node 'buton'"))
    }

    @Test("ohne Ordner und ohne eigene Config die eingebaute neben dem Programm")
    func activeBuiltinBesideExecutable() {
        let files = ["\(CheckHarness.builtinRoot)/apolloshell-default/shell.kdl": "panel \"bar\" {\n}\n"]
        #expect(CheckHarness.run([], files: files).exitCode == 0)
        let missing = CheckHarness.run([])
        #expect(missing.exitCode == 1)
        #expect(missing.output == "error: built-in config 'apolloshell-default' is missing at '\(CheckHarness.builtinRoot)/apolloshell-default'")
    }

    @Test("APOLLO_BUILTIN_CONFIGS ersetzt den Ordner der eingebauten Configs")
    func builtinOverride() {
        let environment = ["HOME": "/Users/tester", "APOLLO_BUILTIN_CONFIGS": "/dev/configs"]
        let result = CheckHarness.run([], files: ["/dev/configs/apolloshell-default/shell.kdl": "buton\n"], environment: environment)
        #expect(result.exitCode == 1)
        #expect(result.output.hasPrefix("/dev/configs/apolloshell-default/shell.kdl:1:1: error: unknown node 'buton'"))
    }

    @Test("settings.kdl waehlt die Config, Warnungen daraus erscheinen")
    func settingsChoosesConfig() {
        let files = [
            "/Users/tester/.config/apolloshell/settings.kdl": "config \"work\"\nsurprise 1\n",
            "/Users/tester/.config/apolloshell/configs/work/shell.kdl": "panel \"bar\" {\n}\n",
            "/Users/tester/.config/apolloshell/shell.kdl": "buton\n",
        ]
        let result = CheckHarness.run([], files: files)
        #expect(result.exitCode == 0)
        #expect(result.output.hasPrefix("~/.config/apolloshell/settings.kdl:2:1: warning: "))
    }

    @Test("settings.kdl nennt eine fehlende Config: Fehler und Rueckfall")
    func settingsNamesMissingConfig() {
        let files = [
            "/Users/tester/.config/apolloshell/settings.kdl": "config \"gone\"\n",
            "\(CheckHarness.builtinRoot)/apolloshell-default/shell.kdl": "panel \"bar\" {\n}\n",
        ]
        let result = CheckHarness.run([], files: files)
        #expect(result.exitCode == 1)
        #expect(result.output == "error: settings.kdl names config 'gone' which does not exist, falling back to apolloshell-default")
    }

    @Test("Symlink auf das Programm fuehrt zu den Resources der App")
    func symlinkedExecutable() throws {
        let app = try CheckHarness.temporaryDirectory("Fake.app")
        let helpers = app.appendingPathComponent("Contents/Helpers")
        let configs = app.appendingPathComponent("Contents/Resources/configs/apolloshell-default")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configs, withIntermediateDirectories: true)
        try "buton\n".write(to: configs.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        try "".write(to: helpers.appendingPathComponent("apollo"), atomically: true, encoding: .utf8)
        let link = app.deletingLastPathComponent().appendingPathComponent("apollo-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: helpers.appendingPathComponent("apollo"))
        let home = app.deletingLastPathComponent().appendingPathComponent("home")
        let result = CheckCommand.run(arguments: [], environment: ["HOME": home.path], fileSystem: DiskFileSystem(), executableURL: link)
        #expect(result.exitCode == 1)
        #expect(result.output.contains("error: unknown node 'buton'"), "\(result.output)")
    }
}
