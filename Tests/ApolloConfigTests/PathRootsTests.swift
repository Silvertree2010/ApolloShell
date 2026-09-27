import Testing
import ApolloBase
@testable import ApolloConfig

@Suite("Wurzelnamen eines Templates")
struct PathRootsTests {
    @Test("gleichen den Wurzeln der Abhängigkeiten ohne lokale Namen", arguments: [
        "{a.b.c + x[i].y}",
        "text {item.name} and {(list | at 0).z} {n ? p.q : r} {[u, v][w]}",
        "{f | default g.h | join sep}",
        "plain",
        "{self.hover ? 'a' : 'b'} {-k} {m ?? n.o}",
    ])
    func matchesDependencyRoots(_ text: String) throws {
        let template = try ExpressionParser.parseTemplate(text, span: .synthetic("t")).get()
        #expect(template.pathRoots == Set(template.dependencies(locals: []).map(\.root)))
    }

    @Test("relative fügt clock nur den Abhängigkeiten hinzu, nicht den Wurzelnamen")
    func relativeClock() throws {
        let template = try ExpressionParser.parseTemplate("{when | relative}", span: .synthetic("t")).get()
        #expect(template.pathRoots == ["when"])
        #expect(Set(template.dependencies(locals: []).map(\.root)) == ["when", "clock"])
    }
}
