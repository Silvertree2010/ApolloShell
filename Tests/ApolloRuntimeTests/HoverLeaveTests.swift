import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("Randzone verlassen")
struct HoverLeaveTests {
    typealias IR = RuntimeIR
    typealias T = TreeIR

    @Test("on-hover-leave läuft statt Schliessen, ohne Handler schliesst die Fläche")
    func hoverLeave() async {
        let fixture = ShellFixture()
        let h = HandlerIR(name: "on-hover-leave", actions: [IR.log("leave")], span: IR.span(5))
        fixture.apply([
            T.surface("popup", "a", handlers: [h], children: [T.text("0", IR.string("x"))]),
            T.surface("popup", "b", children: [T.text("0", IR.string("y"))]),
        ])
        fixture.runtime.open("a", screenKey: nil)
        fixture.runtime.open("b", screenKey: nil)
        fixture.runtime.hoverLeave("a")
        fixture.runtime.hoverLeave("b")
        await settle()
        #expect(fixture.surface("a").isOpen)
        #expect(!fixture.surface("b").isOpen)
        #expect(fixture.log.entries == ["leave"])
    }
}
