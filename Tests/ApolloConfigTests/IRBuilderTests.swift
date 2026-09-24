import Testing
import Foundation
import ApolloBase
import ApolloKDL
@testable import ApolloConfig

func fields(_ pairs: KeyValuePairs<String, Value>) -> Record {
    Record(pairs.map { ($0.key, $0.value) })
}

enum IRHarness {
    static let root = URL(fileURLWithPath: "/config")
    static let location = ConfigLocation(id: "test", root: root, isBuiltin: false)

    static func build(_ files: [String: String]) -> (ir: ConfigIR, diagnostics: [Diagnostic]) {
        let fs = MemoryFileSystem(files)
        let included = IncludeExpander.expand(root: root, origin: .user, fileSystem: fs, paths: UseStageTests.paths)
        let requires = included.nodes.filter { $0.kdl.name == "require" }
        let featured = FeatureStage.run(included.nodes, shellVersion: "0.2.0", registry: .builtin)
        let lets = LetStage.run(featured.nodes, registry: .builtin)
        let used = UseStage.run(lets.nodes, registry: .builtin)
        let disabled = DisableStage.run(used.nodes, registry: .builtin)
        let checked = SchemaStage.run(disabled.nodes, defines: used.defines, registry: .builtin)
        let built = IRBuilder.build(
            disabled.nodes,
            defines: used.defines,
            requires: requires,
            location: location,
            files: included.files,
            registry: .builtin,
            fileSystem: fs,
            paths: UseStageTests.paths
        )
        let diagnostics = included.diagnostics + featured.diagnostics + lets.diagnostics + used.diagnostics + disabled.diagnostics + checked.diagnostics + built.diagnostics
        return (built.ir, diagnostics)
    }

    static func build(_ text: String) -> (ir: ConfigIR, diagnostics: [Diagnostic]) {
        build(["/config/shell.kdl": text])
    }

    static func clean(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) -> ConfigIR {
        let result = build(text)
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))", sourceLocation: sourceLocation)
        return result.ir
    }

    static func element(_ child: ChildIR?) -> ElementIR? {
        guard case .element(let element)? = child else { return nil }
        return element
    }

    static func render(_ value: CompiledValue?, locals: [String: Value] = [:], globals: [String: Value] = [:]) -> Value {
        guard let value else { return .null }
        let evaluator = EvaluationHarness.evaluator(sink: WarningSink())
        return evaluator.render(value.template, in: TestScope(locals: locals, globals: globals))
    }

    static func literalText(_ value: CompiledValue?) -> String? {
        guard let value else { return nil }
        switch value.template {
        case .literal(let text): return text
        case .whole(.literal(.string(let text))): return text
        default: return nil
        }
    }
}

@Suite("IR-Bau: Elemente und Sprachknoten")
struct IRBuilderTests {
    @Test("Element mit Argumenten, Properties und Schluesseln")
    func elementsAndKeys() throws {
        let ir = IRHarness.clean("""
        panel "bar" anchor="top" {
            text "Hello"
            row id="clock" class="clock" {
                text "{clock.now | date 'HH:mm'}"
            }
            each module in="{var.modules}" {
                button id="mod-{module.id}" {
                    text "{module.id}"
                }
            }
        }
        var modules type="list"
        """)
        let bar = try #require(ir.surface("bar"))
        #expect(bar.kind == "panel")
        #expect(IRHarness.literalText(bar.properties["anchor"]) == "top")
        #expect(bar.children.map(\.key) == ["0", "clock", "2"])
        let text = try #require(IRHarness.element(bar.children.first))
        #expect(text.kind == "text")
        #expect(IRHarness.literalText(text.arguments.first) == "Hello")
        let row = try #require(IRHarness.element(bar.children[1]))
        #expect(IRHarness.literalText(row.idTemplate) == "clock")
        #expect(row.children.map(\.key) == ["0"])
        guard case .each(let each) = bar.children[2] else {
            Issue.record("each expected")
            return
        }
        let button = try #require(IRHarness.element(each.body.first))
        #expect(button.key == "0")
        #expect(button.idTemplate?.isConstant == true)
        let module: Value = .record(fields(["id": .string("wifi")]))
        #expect(IRHarness.render(button.idTemplate, locals: ["module": module]) == .string("mod-wifi"))
    }

    @Test("each mit und ohne key und index")
    func eachVariants() throws {
        let ir = IRHarness.clean("""
        panel "bar" {
            each app in="{apps.running}" key="{app.bundle-id}" index="i" {
                text "{i + 1}. {app.name}"
            }
            each app in="{apps.running}" {
                text "{app.name}"
            }
        }
        """)
        let bar = try #require(ir.surface("bar"))
        guard case .each(let keyed) = bar.children[0], case .each(let plain) = bar.children[1] else {
            Issue.record("two each expected")
            return
        }
        #expect(keyed.key == "0" && plain.key == "1")
        #expect(keyed.variable == "app" && keyed.indexVariable == "i")
        #expect(keyed.list.dependencies == [DependencyPath("apps", ["running"])])
        #expect(keyed.itemKey?.dependencies.isEmpty == true)
        #expect(plain.indexVariable == nil && plain.itemKey == nil)
        let text = try #require(IRHarness.element(keyed.body.first))
        let app: Value = .record(fields(["name": .string("Mail")]))
        #expect(IRHarness.render(text.arguments.first, locals: ["app": app, "i": .number(0)]) == .string("1. Mail"))
    }

    @Test("when mit und ohne else")
    func whenElse() throws {
        let ir = IRHarness.clean("""
        panel "bar" {
            when "{battery.present}" {
                text "{battery.percent | percent}"
            }
            else {
                text "No battery"
            }
            when "{var.show}" {
                text "shown"
            }
        }
        var show #false
        """)
        let bar = try #require(ir.surface("bar"))
        #expect(bar.children.count == 2)
        guard case .when(let first) = bar.children[0], case .when(let second) = bar.children[1] else {
            Issue.record("when expected")
            return
        }
        #expect(first.key == "0" && second.key == "1")
        #expect(first.then.count == 1 && first.otherwise.count == 1)
        #expect(IRHarness.literalText(IRHarness.element(first.otherwise.first)?.arguments.first) == "No battery")
        #expect(second.otherwise.isEmpty)
    }

    @Test("switch mit mehreren Werten je case und default")
    func switchCases() throws {
        let ir = IRHarness.clean("""
        panel "bar" {
            switch "{var.tab}" {
                case "media" { text "Media" }
                case "performance" "weather" { text "Other" }
                default { text "Overview" }
            }
        }
        var tab "media"
        """)
        let bar = try #require(ir.surface("bar"))
        guard case .switchOn(let choice) = bar.children.first else {
            Issue.record("switch expected")
            return
        }
        #expect(choice.cases.map { $0.values.compactMap(IRHarness.literalText) } == [["media"], ["performance", "weather"]])
        #expect(choice.otherwise.count == 1)
    }

    @Test("default nicht am Ende, doppelt, case ausserhalb, fremdes Kind im switch")
    func switchErrors() {
        let result = IRHarness.build("""
        panel "bar" {
            switch "{var.tab}" {
                default { text "A" }
                case "b" { text "B" }
                default { text "C" }
                text "stray"
            }
            case "x" { text "X" }
        }
        var tab "a"
        """)
        let messages = result.diagnostics.filter { $0.severity == .error }.map(\.message)
        #expect(messages == [
            "'default' must be the last branch of 'switch'",
            "'switch' has more than one 'default'",
            "'switch' can only contain 'case' and 'default'",
            "'case' is only allowed inside 'switch'",
        ])
    }

    @Test("Laufzeit-use mit Argumenten und Slots, define in der IR")
    func runtimeUse() throws {
        let ir = IRHarness.clean("""
        define "card" {
            param "module"
            param "compact" type="bool" default=#false
            column {
                slot "header"
                slot
            }
        }
        define "sidebar-clock" {
            param "module"
            text "{module.title}"
        }
        panel "bar" {
            each module in="{var.modules}" {
                use "sidebar-{module.kind}" module="{module}" {
                    fill "header" { text "Head" }
                    text "Body"
                }
            }
        }
        var modules type="list"
        """)
        let bar = try #require(ir.surface("bar"))
        guard case .each(let each) = bar.children.first, case .dynamicUse(let use) = each.body.first else {
            Issue.record("dynamic use expected")
            return
        }
        let module: Value = .record(fields(["kind": .string("clock")]))
        #expect(IRHarness.render(use.name, locals: ["module": module]) == .string("sidebar-clock"))
        #expect(Set(use.arguments.keys) == ["module"])
        #expect(IRHarness.render(use.arguments["module"], locals: ["module": module]) == module)
        #expect(Set(use.slots.keys) == ["", "header"])
        #expect(IRHarness.literalText(IRHarness.element(use.slots[""]?.first)?.arguments.first) == "Body")
        let card = try #require(ir.defines["card"])
        #expect(card.parameters.map(\.name) == ["module", "compact"])
        #expect(card.parameters[1].type == .bool)
        #expect(card.parameters[1].defaultValue != nil)
        let column = try #require(IRHarness.element(card.body.first))
        #expect(column.children == [.slot(name: "header"), .slot(name: nil)])
        let clock = try #require(ir.defines["sidebar-clock"])
        let title = try #require(IRHarness.element(clock.body.first)?.arguments.first)
        #expect(title.dependencies.isEmpty)
        #expect(IRHarness.render(title, locals: ["module": .record(fields(["title": .string("T")]))]) == .string("T"))
    }

    @Test("Handler, Aktionen, Tasten, VoiceOver-Aktionen und Menues")
    func handlersActionsMenus() throws {
        let ir = IRHarness.clean("""
        panel "bar" {
            on-open { set "tab" "media" }
            key "escape" { close "bar" }
            button {
                on-click debounce="200ms" {
                    repeat 2 { toggle-var "seconds" }
                    when "{var.seconds}" { toggle "calendar" }
                    else { toggle "bar" }
                    each app in="{apps.running}" index="i" { apps.quit "{app}" }
                    switch "{var.tab}" {
                        case "a" "b" { toggle "bar" }
                        default { toggle "calendar" }
                    }
                    set "profile" {
                        - name="{var.tab}" tags="{[1, 2]}"
                        - "plain"
                        - {
                            - "a"
                            - "{var.tab}"
                        }
                    }
                }
                accessibility-action "Move Up" { list.move "items" from=1 to=0 }
                menu side="right" {
                    item "Quit" shortcut="cmd+q" { toggle "bar" }
                    separator
                    section "Windows"
                    submenu "More" { item "Details" { toggle "bar" } }
                    source "app-windows" app="{var.tab}"
                    each app in="{apps.running}" key="{app.bundle-id}" { item "{app.name}" { apps.quit "{app}" } }
                    when "{var.seconds}" { separator }
                    else { section "None" }
                }
            }
        }
        popup "calendar" { }
        var tab "a"
        var seconds #false
        var profile type="record"
        var items type="list"
        """)
        let bar = try #require(ir.surface("bar"))
        #expect(bar.handlers.map(\.name) == ["on-open"])
        #expect(bar.keyHandlers.map(\.chord) == ["escape"])
        let button = try #require(IRHarness.element(bar.children.first))
        #expect(bar.children.count == 1)
        let click = try #require(button.handlers.first)
        #expect(click.name == "on-click")
        #expect(IRHarness.literalText(click.properties["debounce"]) == "200ms")
        #expect(click.actions.count == 5)
        guard case .repeatBlock(let count, let body) = click.actions[0] else {
            Issue.record("repeat expected")
            return
        }
        #expect(IRHarness.render(count) == .number(2) && body.count == 1)
        guard case .when(_, let then, let otherwise) = click.actions[1], then.count == 1, otherwise.count == 1 else {
            Issue.record("when expected")
            return
        }
        guard case .each(let variable, let index, _, let eachBody) = click.actions[2] else {
            Issue.record("each expected")
            return
        }
        #expect(variable == "app" && index == "i" && eachBody.count == 1)
        guard case .switchOn(_, let cases, let fallback) = click.actions[3] else {
            Issue.record("switch expected")
            return
        }
        #expect(cases.map(\.values.count) == [2] && fallback.count == 1)
        guard case .call(let set) = click.actions[4] else {
            Issue.record("set expected")
            return
        }
        #expect(set.name == "set" && set.children.count == 3)
        let evaluator = EvaluationHarness.evaluator(sink: WarningSink())
        let scope = TestScope(globals: ["var": .record(fields(["tab": .string("x")]))])
        let entries = set.children.map { $0.evaluate(with: evaluator, scope: scope) }
        #expect(entries == [
            .record(fields(["name": .string("x"), "tags": .list([.number(1), .number(2)])])),
            .string("plain"),
            .list([.string("a"), .string("x")]),
        ])
        #expect(button.accessibilityActions.count == 1)
        #expect(IRHarness.literalText(button.accessibilityActions.first?.title) == "Move Up")
        let menu = try #require(button.menu)
        #expect(IRHarness.literalText(menu.properties["side"]) == "right")
        #expect(menu.items.count == 7)
        if case .item(let title, let properties, let actions) = menu.items[0] {
            #expect(IRHarness.literalText(title) == "Quit" && IRHarness.literalText(properties["shortcut"]) == "cmd+q" && actions.count == 1)
        } else {
            Issue.record("item expected")
        }
        #expect(menu.items[1] == .separator)
        if case .source(let kind, let properties) = menu.items[4] {
            #expect(kind == "app-windows" && properties["app"] != nil)
        } else {
            Issue.record("source expected")
        }
        if case .each(let variable, _, _, let key, let items) = menu.items[5] {
            #expect(variable == "app" && key != nil && items.count == 1)
        } else {
            Issue.record("menu each expected")
        }
        if case .when(_, let then, let otherwise) = menu.items[6] {
            #expect(then == [.separator] && otherwise.count == 1)
        } else {
            Issue.record("menu when expected")
        }
    }

    @Test("benannter Slot eines eingebauten Bausteins")
    func builtinNamedSlot() throws {
        let ir = IRHarness.clean("""
        osd "volume" {
            slider value="{audio.volume}" {
                fill "thumb" { text "{audio.volume | percent}" }
                on-change { audio.set-volume "{event.value}" }
            }
        }
        """)
        let slider = try #require(IRHarness.element(ir.surface("volume")?.children.first))
        #expect(slider.slots["thumb"]?.count == 1)
        #expect(slider.children.isEmpty)
        #expect(slider.handlers.map(\.name) == ["on-change"])
    }

    @Test("each ueber 50 000 konstante Eintraege ergibt eine EachIR")
    func largeConstantEach() throws {
        let entries = (0..<50_000).map { "    - \($0)" }.joined(separator: "\n")
        let ir = IRHarness.clean("""
        let numbers {
        \(entries)
        }
        panel "bar" {
            each n in="{numbers}" {
                text "{n}"
            }
        }
        """)
        let bar = try #require(ir.surface("bar"))
        #expect(bar.children.count == 1)
        guard case .each(let each) = bar.children.first else {
            Issue.record("each expected")
            return
        }
        #expect(each.body.count == 1)
        guard case .list(let items) = IRHarness.render(each.list) else {
            Issue.record("list expected")
            return
        }
        #expect(items.count == 50_000)
    }
}

@Suite("IR-Bau: Parameter und Namensfang")
struct IRParameterTests {
    @Test("Namensfang: Argument aus aeusserem each landet in einem Rumpf mit innerem each gleichen Namens")
    func argumentIsNotCapturedByInnerEach() throws {
        let ir = IRHarness.clean("""
        define "row" {
            param "label"
            each item in="{apps.running}" {
                text "{label} / {item.name}"
            }
        }
        panel "bar" {
            each item in="{var.entries}" {
                use "row" label="{item.name}"
            }
        }
        var entries type="list"
        """)
        let bar = try #require(ir.surface("bar"))
        guard case .each(let outer) = bar.children.first, case .each(let inner) = outer.body.first else {
            Issue.record("nested each expected")
            return
        }
        #expect(outer.variable == "item")
        try #require(inner.variable != "item")
        let text = try #require(IRHarness.element(inner.body.first))
        let outerItem: Value = .record(fields(["name": .string("outer")]))
        let innerItem: Value = .record(fields(["name": .string("inner")]))
        let rendered = IRHarness.render(text.arguments.first, locals: ["item": outerItem, inner.variable: innerItem])
        #expect(rendered == .string("outer / inner"))
        #expect(text.arguments.first?.dependencies.isEmpty == true)
    }

    @Test("Slot-Inhalt sieht die Namen der Aufrufstelle, nicht die each-Variablen des Rumpfs")
    func slotContentSeesCallSiteNames() throws {
        let ir = IRHarness.clean("""
        define "list" {
            each item in="{apps.running}" {
                row {
                    text "{item.name}"
                    slot
                }
            }
        }
        panel "bar" {
            each item in="{var.entries}" {
                use "list" {
                    text "{item.name}"
                }
            }
        }
        var entries type="list"
        """)
        let bar = try #require(ir.surface("bar"))
        guard case .each(let outer) = bar.children.first, case .each(let inner) = outer.body.first else {
            Issue.record("nested each expected")
            return
        }
        try #require(inner.variable != "item")
        let row = try #require(IRHarness.element(inner.body.first))
        let locals: [String: Value] = [
            "item": .record(fields(["name": .string("outer")])),
            inner.variable: .record(fields(["name": .string("inner")])),
        ]
        let texts = row.children.compactMap { IRHarness.render(IRHarness.element($0)?.arguments.first, locals: locals) }
        #expect(texts == [.string("inner"), .string("outer")])
    }

    @Test("Argument als Vorlage mitten in einem Ausdruck und als ganzer Wert")
    func argumentTemplatesAreSubstituted() throws {
        let ir = IRHarness.clean("""
        define "labeled" {
            param "title"
            param "icon" default="bar-power"
            param "count" default=3
            text "{title | upper}!" tooltip="{title}" label="{icon}" class="n{count + 1}"
        }
        panel "bar" {
            use "labeled" title="Hi {var.user}"
            use "labeled" title="Plain"
        }
        var user "ann"
        """)
        let bar = try #require(ir.surface("bar"))
        let first = try #require(IRHarness.element(bar.children.first))
        let globals: [String: Value] = ["var": .record(fields(["user": .string("ann")]))]
        #expect(IRHarness.render(first.arguments.first, globals: globals) == .string("HI ANN!"))
        #expect(first.arguments.first?.dependencies == [DependencyPath("var", ["user"])])
        #expect(IRHarness.render(first.properties["tooltip"], globals: globals) == .string("Hi ann"))
        #expect(IRHarness.literalText(first.properties["label"]) == "bar-power")
        #expect(IRHarness.render(first.properties["class"]) == .string("n4"))
        let second = try #require(IRHarness.element(bar.children.last))
        #expect(IRHarness.literalText(second.properties["tooltip"]) == "Plain")
    }

    @Test("Parameter wird durch verschachtelte use durchgereicht")
    func parameterPassesThroughNestedUse() throws {
        let ir = IRHarness.clean("""
        define "inner" {
            param "module"
            text "{module.name}"
        }
        define "outer" {
            param "module"
            column {
                use "inner" module="{module}"
            }
        }
        panel "bar" {
            each module in="{var.modules}" {
                use "outer" module="{module}"
            }
        }
        var modules type="list"
        """)
        guard case .each(let each)? = ir.surface("bar")?.children.first else {
            Issue.record("each expected")
            return
        }
        let text = try #require(IRHarness.element(IRHarness.element(each.body.first)?.children.first))
        #expect(IRHarness.render(text.arguments.first, locals: ["module": .record(fields(["name": .string("wifi")]))]) == .string("wifi"))
    }

    @Test("Ausdruck in param default wird gegen die Registry geprueft")
    func parameterDefaultIsChecked() {
        let result = IRHarness.build("""
        define "card" {
            param "title" default="{apps.dokc}"
            text "{title}"
        }
        """)
        #expect(result.diagnostics.map(\.message) == ["unknown field 'dokc' on 'apps'"])
    }
}

@Suite("IR-Bau: oberste Knoten und Kennungen")
struct IRTopLevelTests {
    @Test("bind, on, var, style, require und Bloecke")
    func topLevelNodes() throws {
        let result = IRHarness.build([
            "/config/shell.kdl": """
            require "0.2.0"
            require feature="core"
            let gap=8
            style "style.css"
            var gap-size "{gap}"
            var tab "media" persist=#true
            bind "option+space" when="{var.tab == 'media'}" repeat=#true { toggle "bar" }
            bind "cmd+k" id="palette" { toggle "bar" }
            on "config.loaded" when="{var.tab == 'media'}" { toggle "bar" }
            weather source="{var.tab}"
            poll "vpn" command="scutil" interval="5s"
            wm enabled=#true {
                gaps inner=4 outer=8
                rule "float" app="Finder"
                rule "float" app="Mail"
            }
            panel "bar" { }
            """,
            "/config/style.css": "",
        ])
        let ir = result.ir
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(ir.id == "test" && ir.root == IRHarness.root)
        #expect(ir.files == [URL(fileURLWithPath: "/config/shell.kdl")])
        #expect(ir.requiredVersion == "0.2.0" && ir.requiredFeatures == ["core"])
        #expect(ir.styleSheets.map(\.url) == [URL(fileURLWithPath: "/config/style.css")])
        #expect(ir.vars.map(\.name) == ["gap-size", "tab"])
        let evaluator = EvaluationHarness.evaluator(sink: WarningSink())
        #expect(ir.vars[0].defaultValue.evaluate(with: evaluator, scope: TestScope()) == .number(8))
        #expect(ir.vars[1].persist)
        #expect(ir.binds.map(\.id) == ["alt+space", "palette"])
        #expect(ir.binds[0].repeats && ir.binds[0].when != nil)
        #expect(ir.events.map(\.event) == ["config.loaded"])
        #expect(ir.events.first?.when != nil)
        #expect(Set(ir.blocks.keys) == ["weather", "poll", "wm"])
        #expect(ir.blocks["weather"]?.first?.compiled["source"]?.dependencies == [DependencyPath("var", ["tab"])])
        let poll = try #require(ir.blocks["poll"]?.first)
        #expect(IRHarness.literalText(poll.compiled["#0"]) == "vpn")
        #expect(IRHarness.literalText(poll.compiled["interval"]) == "5s")
        let wm = try #require(ir.blocks["wm"]?.first)
        #expect(Set(wm.compiled.keys) == ["enabled", "gaps.inner", "gaps.outer", "rule.#0", "rule.app", "rule[1].#0", "rule[1].app"])
        #expect(IRHarness.literalText(wm.compiled["rule[1].app"]) == "Mail")
        #expect(wm.nodes.map(\.name) == ["wm"])
    }

    @Test("poll und listen mit Namen auf -error sind ein Ladefehler")
    func pollAndListenRejectErrorSuffix() {
        let result = IRHarness.build("""
        poll "vpn-error" command="scutil"
        listen "watch-error" command="watch"
        """)
        #expect(result.diagnostics.filter { $0.severity == .error }.map(\.message) == [
            "'poll' name 'vpn-error' cannot end with '-error', that suffix is reserved for the load error field",
            "'listen' name 'watch-error' cannot end with '-error', that suffix is reserved for the load error field",
        ])
    }

    @Test("command-center: die letzte Liste ersetzt die fruehere")
    func commandCenterItemsReplaceTheList() throws {
        let ir = IRHarness.clean("""
        command-center {
            items {
                builtin "reload-config"
                builtin "quit"
            }
        }
        command-center visible=#false {
            items {
                builtin "configs"
            }
        }
        """)
        let blocks = try #require(ir.blocks["command-center"])
        #expect(blocks.count == 2)
        #expect(blocks[0].nodes.first?.children?.isEmpty ?? true)
        #expect(blocks[0].compiled.isEmpty)
        #expect(IRHarness.literalText(blocks[1].compiled["items.builtin.#0"]) == "configs")
        #expect(blocks[1].compiled["visible"] != nil)
    }

    @Test("doppelte id in einer Oberflaeche nennt beide Orte, getrennte Zweige nicht")
    func duplicateIDs() {
        let result = IRHarness.build("""
        panel "bar" {
            text "A" id="clock"
            when "{var.flag}" {
                text "B" id="spare"
            }
            else {
                text "C" id="spare"
            }
            column {
                text "D" id="clock"
            }
        }
        panel "other" {
            text "E" id="clock"
            text "F" id="123"
        }
        var flag #false
        """)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.map(\.message) == ["duplicate id 'clock' in surface 'bar'", "an id cannot consist only of digits"])
        #expect(errors.first?.span?.start.line == 10)
        #expect(errors.first?.notes.map(\.span?.start.line) == [2])
    }

    @Test("gleiche Config zweimal ergibt dieselbe IR")
    func deterministic() {
        let text = """
        define "row" {
            param "label"
            each item in="{apps.running}" { text "{label} {item.name}" }
        }
        panel "bar" {
            each item in="{var.entries}" key="{item.id}" { use "row" label="{item.name}" }
            use "row" label="x"
        }
        var entries type="list"
        bind "alt+space" { toggle "bar" }
        wm enabled=#true { gaps inner=4 }
        """
        #expect(IRHarness.build(text).ir == IRHarness.build(text).ir)
    }

    @Test("Kinder einer Aktion muessen Eintraege mit '-' sein")
    func actionChildrenMustBeEntries() {
        let result = IRHarness.build("""
        panel "bar" {
            button {
                on-click {
                    list.insert "cards" {
                        name "x"
                    }
                }
            }
        }
        var cards type="list"
        """)
        #expect(result.diagnostics.map(\.message) == ["children of 'list.insert' must be '-' entries"])
    }

    @Test("jedes '-' ist genau ein Kind der Aktion, auch ein einzelnes")
    func everyDashIsOneChild() throws {
        let ir = IRHarness.clean("""
        panel "bar" {
            button {
                on-click {
                    set "cards" {
                        - "only"
                    }
                    list.insert "cards" {
                        - id="a"
                        - id="b"
                    }
                    set "tab" "x"
                }
            }
        }
        var cards type="list"
        var tab "a"
        """)
        let button = try #require(IRHarness.element(ir.surface("bar")?.children.first))
        let actions = try #require(button.handlers.first?.actions)
        let calls: [ActionCallIR] = actions.compactMap {
            guard case .call(let call) = $0 else { return nil }
            return call
        }
        #expect(calls.map(\.children.count) == [1, 2, 0])
        let evaluator = EvaluationHarness.evaluator(sink: WarningSink())
        let scope = TestScope()
        #expect(calls[0].children.map { $0.evaluate(with: evaluator, scope: scope) } == [.string("only")])
        #expect(calls[1].children.map { $0.evaluate(with: evaluator, scope: scope) } == [
            .record(fields(["id": .string("a")])),
            .record(fields(["id": .string("b")])),
        ])
    }
}
