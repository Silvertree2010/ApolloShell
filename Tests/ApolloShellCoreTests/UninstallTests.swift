import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Deinstallation")
struct UninstallTests {
    let home = URL(fileURLWithPath: "/Users/x", isDirectory: true)

    @Test("Alle Pfade liegen tief in ~/Library und tragen den Namen der App")
    func scoped() {
        let ps = Uninstall.paths(home: home).map(\.path)
        #expect(!ps.isEmpty)
        for p in ps {
            #expect(p.hasPrefix("/Users/x/Library/"))
            #expect(p.split(separator: "/").count >= 5)
            #expect(p.contains(AppIdentity.bundleID) || p.hasSuffix("/" + ShellFiles.folderName))
        }
    }

    @Test("Einstellungen, Daten und Caches sind dabei")
    func covers() {
        let ps = Uninstall.paths(home: home).map(\.path)
        #expect(ps.contains("/Users/x/Library/Application Support/ApolloShell"))
        #expect(ps.contains("/Users/x/Library/Preferences/\(AppIdentity.bundleID).plist"))
        #expect(ps.contains("/Users/x/Library/Caches/\(AppIdentity.bundleID)"))
    }

    @Test("tccutil setzt nur die eigenen Freigaben zurueck")
    func tcc() {
        #expect(Uninstall.tccArguments() == ["reset", "All", AppIdentity.bundleID])
    }
}
