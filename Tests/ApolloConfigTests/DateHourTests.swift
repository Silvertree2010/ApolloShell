import Testing
import Foundation
@testable import ApolloConfig

@Suite("date-Filter: j als Stunde des Systems")
struct DateHourTests {
    static let zone = TimeZone(identifier: "Asia/Tokyo")!
    static let moment = Date(timeIntervalSince1970: 1790235660)

    @Test("j folgt der Sprache: englisch zwölf, deutsch vierundzwanzig Stunden")
    func followsLocale() {
        #expect(DateText.format(Self.moment, pattern: "jj:mm", locale: Locale(identifier: "en_US"), timeZone: Self.zone) == "04:41")
        #expect(DateText.format(Self.moment, pattern: "jj:mm", locale: Locale(identifier: "de_CH"), timeZone: Self.zone) == "16:41")
    }

    @Test("j in Anführungszeichen bleibt Text")
    func quoted() {
        #expect(DateText.resolved("'j' jj", locale: Locale(identifier: "de_CH")) == "'j' HH")
    }
}
