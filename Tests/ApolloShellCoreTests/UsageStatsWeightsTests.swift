import Testing
import Foundation
import ApolloShellCore

@Suite("Nutzungsgewichte aus fertigen Werten")
struct UsageStatsWeightsTests {
    @Test("Gewichte gelten genau zum angegebenen Zeitpunkt und klingen danach ab")
    func weightsDecay() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stats = UsageStats(weights: ["com.apple.Safari": 4], at: now)
        #expect(stats.weight(for: "com.apple.Safari", at: now) == 4)
        #expect(stats.weight(for: "com.apple.Safari", at: now.addingTimeInterval(UsageStats.defaultHalfLife)) == 2)
        #expect(stats.weight(for: "org.mozilla.firefox", at: now) == 0)
    }
}
