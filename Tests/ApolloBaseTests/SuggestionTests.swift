import Testing
@testable import ApolloBase

@Suite("Vorschläge bei Tippfehlern")
struct SuggestionTests {
    @Test("nächster Kandidat innerhalb der Distanz")
    func closest() {
        #expect(Suggestion.closest(to: "on-clik", among: ["on-hover", "on-click"]) == "on-click")
        #expect(Suggestion.closest(to: "colr", among: ["column", "color"]) == "color")
    }

    @Test("zu weit entfernt ergibt nil")
    func tooFar() {
        #expect(Suggestion.closest(to: "abc", among: ["xyz"]) == nil)
        #expect(Suggestion.closest(to: "abc", among: []) == nil)
        #expect(Suggestion.closest(to: "abc", among: ["abd"], maxDistance: 0) == nil)
    }

    @Test("Gleichstand: der erste Kandidat gewinnt")
    func tie() {
        #expect(Suggestion.closest(to: "cat", among: ["bat", "hat"]) == "bat")
    }

    @Test("Distanz zählt Zeichen, nicht Bytes")
    func unicode() {
        #expect(Suggestion.closest(to: "gr\u{F6}\u{DF}e", among: ["gr\u{F6}sse"]) == "gr\u{F6}sse")
        #expect(Suggestion.editDistance(Array("\u{1F389}a"), Array("\u{1F388}a")) == 1)
    }
}
