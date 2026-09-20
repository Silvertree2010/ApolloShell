import Foundation
import Testing
@testable import ApolloShellCore

@Suite("The app id")
struct AppIdentityTests {
    @Test("The bundle ID in Support/Info.plist is the same as in the code")
    func matchesInfoPlist() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ApolloShellCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Repo
        let data = try Data(contentsOf: root.appending(path: "Support/Info.plist"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["CFBundleIdentifier"] as? String == AppIdentity.bundleID)
    }

    @Test("The log subsystem and the derived ids hang on the bundle ID")
    func derived() {
        #expect(AppIdentity.logSubsystem == AppIdentity.bundleID)
        #expect(AppIdentity.scoped("bluetooth") == AppIdentity.bundleID + ".bluetooth")
    }
}
