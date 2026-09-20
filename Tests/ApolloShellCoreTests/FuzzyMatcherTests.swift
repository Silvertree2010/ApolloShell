import Testing
@testable import ApolloShellCore

@Suite("Fuzzy search")
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

    @Test("case and diacritics do not matter")
    func ignoresCaseAndDiacritics() {
        #expect(matcher.score("FIRE", in: "firefox") != nil)
        #expect(matcher.score("cafe", in: "Café Studio") != nil)
    }

    @Test("whitespace in the query does not get in the way")
    func ignoresWhitespaceInQuery() {
        #expect(matcher.score("visual code", in: "Visual Studio Code") != nil)
    }

    @Test("start of the name beats a match mid-word")
    func prefixBeatsMiddle() throws {
        let prefix = try #require(matcher.score("fi", in: "Firefox"))
        let middle = try #require(matcher.score("fi", in: "Affinity Designer"))
        #expect(prefix > middle)
    }

    @Test("ranking: best match first, the rest falls out")
    func ranksAndFilters() {
        let apps = ["Affinity Designer", "Blender", "Firefox", "Final Cut"]
        let result = matcher.rank(apps, query: "fi", name: { $0 })
        #expect(result.first == "Final Cut" || result.first == "Firefox")
        #expect(!result.contains("Blender"))
        #expect(result.last == "Affinity Designer")
    }

    @Test("empty query leaves the list unchanged")
    func emptyQueryKeepsOrder() {
        let apps = ["Blender", "Affinity", "Zed"]
        #expect(matcher.rank(apps, query: "  ", name: { $0 }) == apps)
    }
}
