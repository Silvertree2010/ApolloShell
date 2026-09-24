import Foundation
import Testing
@testable import ApolloShellCore

@Suite("App-Kennung")
struct AppIdentityTests {
    @Test("Bundle-ID in Support/Info.plist ist dieselbe wie im Code")
    func matchesInfoPlist() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ApolloShellCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Repo
        let data = try Data(contentsOf: root.appending(path: "Support/Info.plist"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["CFBundleIdentifier"] as? String == AppIdentity.bundleID)
    }

    @Test("Log-Subsystem und abgeleitete Kennungen haengen an der Bundle-ID")
    func derived() {
        #expect(AppIdentity.logSubsystem == AppIdentity.bundleID)
        #expect(AppIdentity.scoped("bluetooth") == AppIdentity.bundleID + ".bluetooth")
    }
}
