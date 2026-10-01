import Testing
import ApolloBase
@testable import ApolloConfig

@Suite("Erreichbare defines")
struct DefineReachTests {
    static let config = """
    define "frame" {
        column { slot }
    }
    define "sidebar-clock" {
        param "module"
        use "frame" { text "{module.title}" }
    }
    define "x-card" {
        text "card"
    }
    define "card" {
        text "plain"
    }
    define "loose" {
        button {
            on-click { use "a-{var.n}" }
        }
    }
    panel "bar" {
        use "frame" { text "static" }
        each module in="{var.modules}" {
            use "sidebar-{module.kind}" module="{module}"
            use "{module.kind}-card"
        }
    }
    var modules type="list"
    var n default="b"
    """

    @Test("nur defines, die ein Laufzeit-use treffen kann, bleiben in der IR")
    func keepsReachable() {
        let ir = IRHarness.build(Self.config).ir
        #expect(Set(ir.defines.keys) == ["sidebar-clock", "x-card"])
        #expect(Set(IRHarness.build(["/config/shell.kdl": Self.config], allDefines: true).ir.defines.keys) == ["frame", "sidebar-clock", "x-card", "card", "loose"])
    }

    @Test("Diagnosen bleiben gleich, auch aus verworfenen define-Koerpern")
    func sameDiagnostics() {
        let a = IRHarness.build(Self.config).diagnostics.map(\.message)
        let b = IRHarness.build(["/config/shell.kdl": Self.config], allDefines: true).diagnostics.map(\.message)
        #expect(a == b)
        #expect(a.contains { $0.contains("not allowed in actions") })
    }

    @Test("ein ganz dynamischer Name haelt alle defines")
    func wholeKeepsAll() {
        let ir = IRHarness.build("""
        define "one" { text "1" }
        define "two" { text "2" }
        panel "bar" {
            use "{var.name}"
        }
        var name default="one"
        """).ir
        #expect(Set(ir.defines.keys) == ["one", "two"])
    }

    @Test("Muster aus Praefix und Suffix")
    func affixes() {
        var r = DefineReach()
        r.add("sidebar-{m.kind}", span: .synthetic())
        r.add("{m.kind}-card", span: .synthetic())
        r.add("exact-{{x}}", span: .synthetic())
        #expect(r.keeps("sidebar-clock"))
        #expect(r.keeps("sidebar-"))
        #expect(!r.keeps("sidebar"))
        #expect(r.keeps("weather-card"))
        #expect(!r.keeps("card"))
        #expect(r.keeps("exact-{x}"))
        #expect(!r.keeps("exact-x"))
        #expect(!DefineReach().keeps("any"))
        #expect(DefineReach.everything.keeps("any"))
    }
}
