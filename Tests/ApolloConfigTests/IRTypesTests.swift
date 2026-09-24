import Foundation
import Testing
import ApolloBase
import ApolloConfig

private actor IRMailbox {
    private var received: [ConfigIR] = []

    func deliver(_ ir: ConfigIR) {
        received.append(ir)
    }

    func latest() -> ConfigIR? {
        received.last
    }
}

@Suite("IR-Typen")
struct IRTypesTests {
    @Test("Beispiel-IR lässt sich bauen und trägt alle Arten von Kindern")
    func sampleConfigHasEveryChildKind() {
        let config = IRTestBuilder.sampleConfig()
        let bar = config.surface("bar")
        #expect(bar?.kind == "panel")
        #expect(bar?.children.map(\.key) == ["clock", "1", "2", "3"])
        guard case .each(let each) = bar?.children[1], case .element(let button) = each.body.first else {
            Issue.record("each fehlt")
            return
        }
        #expect(each.indexVariable == "i")
        #expect(button.key == "0")
        #expect(button.idTemplate?.isConstant == true)
        #expect(button.menu?.items.count == 3)
        #expect(config.defines["dashboard-weather"]?.parameters.first?.type == .bool)
        #expect(config.blocks["poll"]?.first?.compiled["interval"] != nil)
        #expect(config.surface("missing") == nil)
    }

    @Test("Abhängigkeiten im Builder schliessen Schleifenvariablen aus")
    func builderDependenciesExcludeLocals() {
        let bound = IRTestBuilder.value("{i + 1}. {app.name}", locals: ["app", "i"])
        #expect(bound.isConstant)
        let clock = IRTestBuilder.value("{clock.now | date 'HH:mm'}")
        #expect(clock.dependencies.contains(DependencyPath("clock", ["now"])))
        #expect(!clock.isConstant)
        let template = IRTestBuilder.value("app-{app.bundle-id}", locals: [])
        #expect(template.dependencies == [DependencyPath("app", ["bundle-id"])])
    }

    @Test("Gleiche Konstruktion ergibt gleiche IR, eine Änderung nicht")
    func equalityFollowsContent() {
        let first = IRTestBuilder.sampleConfig()
        let second = IRTestBuilder.sampleConfig()
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        var changed = second
        changed.surfaces[0].properties["edge"] = IRTestBuilder.literal(.string("bottom"), line: 9)
        #expect(first != changed)
        var moved = second
        moved.surfaces[0].span = IRTestBuilder.span(line: 99)
        #expect(first != moved)
    }

    @Test("repeat trägt Aktionen als Kinder und unterscheidet sich von call")
    func repeatBlockCarriesActions() {
        let body: [ActionIR] = [IRTestBuilder.action("wait", [IRTestBuilder.literal(.string("1s"))])]
        let repeated = ActionIR.repeatBlock(count: IRTestBuilder.literal(.number(3)), body: body)
        guard case .repeatBlock(let count, let inner) = repeated else {
            Issue.record("repeat fehlt")
            return
        }
        #expect(count.isConstant)
        #expect(inner == body)
        #expect(repeated != .repeatBlock(count: IRTestBuilder.literal(.number(4)), body: body))
        #expect(repeated != IRTestBuilder.action("repeat", [IRTestBuilder.literal(.number(3))]))
    }

    @Test("Vorgaben der Initialisierer sind leer")
    func initializerDefaultsAreEmpty() {
        let element = ElementIR(kind: "spacer", key: "0", span: .synthetic())
        #expect(element.arguments.isEmpty && element.properties.isEmpty && element.handlers.isEmpty)
        #expect(element.keyHandlers.isEmpty && element.accessibilityActions.isEmpty && element.slots.isEmpty && element.children.isEmpty)
        #expect(element.menu == nil && element.idTemplate == nil)
        let config = ConfigIR(id: "empty", root: URL(fileURLWithPath: "/tmp/empty"))
        #expect(config.surfaces.isEmpty && config.vars.isEmpty && config.blocks.isEmpty && config.requiredVersion == nil)
        let bind = BindIR(id: "b", chord: IRTestBuilder.literal(.string("cmd+b")), actions: [], span: .synthetic())
        #expect(bind.repeats == false && bind.when == nil)
        #expect(SurfaceChange() == SurfaceChange(added: [], removed: [], changed: [], unchanged: []))
    }

    @Test("Slot-Platzhalter im define-Rumpf traegt seinen Namen und Schluessel")
    func slotPlaceholder() {
        let unnamed = ChildIR.slot(name: nil)
        let header = ChildIR.slot(name: "header")
        #expect(unnamed.key == "slot:")
        #expect(header.key == "slot:header")
        let define = DefineIR(name: "card", body: [.element(ElementIR(kind: "column", key: "0", children: [header, unnamed], span: .synthetic()))], span: .synthetic())
        guard case .element(let column) = define.body.first, case .slot(let name) = column.children.first else {
            Issue.record("slot fehlt")
            return
        }
        #expect(name == "header")
    }

    @Test("Identität hängt Komponenten an und beschreibt sich als Pfad")
    func identityAppends() {
        let surface = Identity(["bar"])
        let entry = surface.appending("1").appending("k:string:com.apple.Safari")
        #expect(entry.components == ["bar", "1", "k:string:com.apple.Safari"])
        #expect(entry.description == "bar/1/k:string:com.apple.Safari")
        #expect(surface.components == ["bar"])
        #expect(Set([entry, surface.appending("1").appending("k:string:com.apple.Safari")]).count == 1)
    }

    @Test("IR geht über Actor-Grenzen und Tasks")
    func crossesActorBoundaries() async {
        let mailbox = IRMailbox()
        let built = await Task.detached { IRTestBuilder.sampleConfig() }.value
        await mailbox.deliver(built)
        let received = await mailbox.latest()
        #expect(received == IRTestBuilder.sampleConfig())
        let surfaceIDs = await MainActor.run { received?.surfaces.map(\.id) ?? [] }
        #expect(surfaceIDs == ["bar"])
    }
}
