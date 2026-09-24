import Foundation
import Testing
@testable import ApolloShell
import ApolloShellCore

@MainActor
@Suite("Marketplace-Host der App")
struct MarketplaceHostTests {
    @Test("MarketplaceURL aus den Defaults ersetzt die Produktions-URL (MP-22)")
    func developerURL() throws {
        let name = "marketplace-host-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(SystemMarketplaceHost.baseURL(defaults) == MarketplaceClient.productionURL)
        defaults.set("http://127.0.0.1:8788", forKey: "MarketplaceURL")
        #expect(SystemMarketplaceHost.baseURL(defaults) == URL(string: "http://127.0.0.1:8788"))
    }
}
