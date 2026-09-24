import Testing
import Foundation
@testable import ApolloControl

@Suite("Install Command Line Tool")
struct CommandLineToolInstallerTests {
    static func helper(in folder: TempFolder) throws -> URL {
        let helper = folder.path("ApolloShell.app/Contents/Helpers/apollo")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("bin".utf8).write(to: helper)
        return helper
    }

    @Test("legt ~/.local/bin/apollo als Link an und erkennt ihn danach")
    func installs() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let home = folder.path("home")
        let helper = try Self.helper(in: folder)
        let installer = CommandLineToolInstaller(home: home, helper: helper)
        #expect(!installer.isInstalled)
        try installer.install()
        #expect(installer.isInstalled)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".local/bin/apollo").path) == helper.path)
    }

    @Test("ersetzt einen alten Link, aber nie eine echte Datei")
    func replacesLinksOnly() throws {
        let folder = TempFolder()
        defer { folder.remove() }
        let home = folder.path("home")
        let helper = try Self.helper(in: folder)
        let link = home.appendingPathComponent(".local/bin/apollo")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/old/apollo")
        let installer = CommandLineToolInstaller(home: home, helper: helper)
        try installer.install()
        #expect(installer.isInstalled)
        try FileManager.default.removeItem(at: link)
        try Data("mine".utf8).write(to: link)
        #expect(throws: ShellControlError.self) { try installer.install() }
        #expect(try String(contentsOf: link, encoding: .utf8) == "mine")
    }

    @Test("sagt, welche Zeile in die Shell-Config gehört, wenn ~/.local/bin fehlt")
    func pathHint() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(CommandLineToolInstaller.pathHint(path: "/usr/bin:/Users/x/.local/bin", shell: "/bin/zsh", home: home) == nil)
        #expect(CommandLineToolInstaller.pathHint(path: "/usr/bin:~/.local/bin", shell: "/bin/zsh", home: home) == nil)
        #expect(CommandLineToolInstaller.pathHint(path: "/usr/bin", shell: "/opt/homebrew/bin/fish", home: home) == "fish_add_path ~/.local/bin")
        #expect(CommandLineToolInstaller.pathHint(path: "/usr/bin", shell: "/bin/zsh", home: home) == "Add to ~/.zshrc: export PATH=\"$HOME/.local/bin:$PATH\"")
        #expect(CommandLineToolInstaller.pathHint(path: "/usr/bin", shell: "/bin/bash", home: home) == "Add to ~/.bash_profile: export PATH=\"$HOME/.local/bin:$PATH\"")
    }
}
