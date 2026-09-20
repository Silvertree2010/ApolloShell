import Testing
@testable import ApolloShellCore

@Suite("Unscharfe Suche")
struct FuzzyMatcherTests {
    let matcher = FuzzyMatcher()

    @Test("finds letters in order, with gaps too",
          arguments: [("illu", "Adobe Illustrator 2026"),
                      ("ff", "Firefox"),
                      ("vsc", "Visual Studio Code"),
                      ("ps", "Affinity Photo Studio")])
    func matchesSubsequence(query: String, name: String) {
        #expect(matcher.score(query, in: name) != nil)
    }

    @Test("no hit when the order is wrong or letters are missing",
          arguments: [("xf", "Firefox"), ("zz", "Blender"), ("oof", "Firefox")])
    func rejectsNonMatches(query: String, name: String) {
        #expect(matcher.score(query, in: name) == nil)
    }

    @Test("Gross/klein und Akzente sind egal")
    func ignoresCaseAndDiacritics() {
        #expect(matcher.score("FIRE", in: "firefox") != nil)
        #expect(matcher.score("cafe", in: "Café Studio") != nil)
    }

    @Test("Leerzeichen in der Eingabe stoeren nicht")
    func ignoresWhitespaceInQuery() {
        #expect(matcher.score("visual code", in: "Visual Studio Code") != nil)
    }

    @Test("Namensanfang schlaegt Treffer mitten im Wort")
    func prefixBeatsMiddle() throws {
        let prefix = try #require(matcher.score("fi", in: "Firefox"))
        let middle = try #require(matcher.score("fi", in: "Affinity Designer"))
        #expect(prefix > middle)
    }

    @Test("Rangliste: bester Treffer zuerst, Rest faellt raus")
    func ranksAndFilters() {
        let apps = ["Affinity Designer", "Blender", "Firefox", "Final Cut"]
        let result = matcher.rank(apps, query: "fi", name: { $0 })
        #expect(result.first == "Final Cut" || result.first == "Firefox")
        #expect(!result.contains("Blender"))
        #expect(result.last == "Affinity Designer")
    }

    @Test("leere Eingabe laesst die Liste unveraendert")
    func emptyQueryKeepsOrder() {
        let apps = ["Blender", "Affinity", "Zed"]
        #expect(matcher.rank(apps, query: "  ", name: { $0 }) == apps)
    }
}
