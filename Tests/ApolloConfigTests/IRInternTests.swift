import Testing
import ApolloBase
@testable import ApolloConfig

@Suite("Geteilte Templates in der IR")
struct IRInternTests {
    @Test("gleiche Ausdruecke aus verschiedenen use-Rahmen behalten ihre eigenen Abhaengigkeiten")
    func framesStayApart() throws {
        let ir = IRHarness.clean("""
        define "d" {
            param "p"
            text "{p} x" class="t"
        }
        panel "bar" {
            use "d" p="{var.a}"
            use "d" p="{var.b}"
            text "{var.a} x" class="t"
        }
        var a default="1"
        var b default="2"
        """)
        let bar = try #require(ir.surface("bar"))
        let texts = bar.children.compactMap(IRHarness.element)
        #expect(texts.count == 3)
        let deps = texts.map { $0.arguments.first?.dependencies ?? [] }
        #expect(deps[0] == [DependencyPath("var", ["a"])])
        #expect(deps[1] == [DependencyPath("var", ["b"])])
        #expect(deps[2] == deps[0])
        #expect(texts[0].arguments.first?.template == texts[2].arguments.first?.template)
        #expect(texts[0].arguments.first?.template != texts[1].arguments.first?.template)
        #expect(Set(texts.map { $0.properties["class"]?.template }) == [.whole(.literal(.string("t")))])
        #expect(texts.allSatisfy { $0.properties["class"]?.dependencies.isEmpty == true })
    }
}
