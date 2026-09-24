import Testing
import Foundation
@testable import ApolloControl

@Suite("Wann die Shell selbst nach Updates schaut")
struct UpdateScheduleTests {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("fällig ohne letzte Prüfung, nach einem Tag, nie wenn abgeschaltet")
    func due() {
        #expect(UpdateSchedule.isDue(lastCheck: nil, now: Self.now, autoCheck: true, interval: 86400))
        #expect(!UpdateSchedule.isDue(lastCheck: Self.now.addingTimeInterval(-3600), now: Self.now, autoCheck: true, interval: 86400))
        #expect(UpdateSchedule.isDue(lastCheck: Self.now.addingTimeInterval(-86400), now: Self.now, autoCheck: true, interval: 86400))
        #expect(!UpdateSchedule.isDue(lastCheck: nil, now: Self.now, autoCheck: false, interval: 86400))
    }

    @Test("eine Prüfung in der Zukunft (Uhr verstellt) gilt als fällig")
    func futureCheck() {
        #expect(UpdateSchedule.isDue(lastCheck: Self.now.addingTimeInterval(7200), now: Self.now, autoCheck: true, interval: 86400))
    }
}
