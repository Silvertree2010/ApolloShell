import Testing
import Foundation
import ApolloBase
import ApolloKDL
@testable import ApolloConfig

@Suite("UseStage")
struct UseStageTests {
    static let paths = ConfigPaths(
        builtinConfigs: URL(fileURLWithPath: "/builtin"),
        userConfig: URL(fileURLWithPath: "/config"),
        applicationSupport: URL(fileURLWithPath: "/support")
    )

    static func pipeline(_ files: [String: String], root: String = "/config", origin: FileOrigin = .user, sourceLocation: SourceLocation = #_sourceLocation) -> UseStageResult {
        let fs = MemoryFileSystem(files)
        let included = IncludeExpander.expand(root: URL(fileURLWithPath: root), origin: origin, fileSystem: fs, paths: paths)
        #expect(included.diagnostics.isEmpty, sourceLocation: sourceLocation)
        let featured = RequireStage.run(included.nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(featured.diagnostics.isEmpty, sourceLocation: sourceLocation)
        let lets = LetStage.run(featured.nodes, registry: .builtin)
        #expect(lets.diagnostics.isEmpty, sourceLocation: sourceLocation)
        return UseStage.run(lets.nodes, registry: .builtin)
    }

    static func run(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) -> UseStageResult {
        pipeline(["/config/shell.kdl": text], sourceLocation: sourceLocation)
    }

    static func find(_ name: String, in nodes: [ExpandedNode]) -> ExpandedNode? {
        for node in nodes {
            if node.kdl.name == name { return node }
            if let found = find(name, in: node.children) { return found }
        }
        return nil
    }

    static func names(_ nodes: [ExpandedNode]) -> [String] {
        nodes.map(\.kdl.name)
    }

    static func errors(_ result: UseStageResult) -> [Diagnostic] {
        result.diagnostics.filter { $0.severity == .error }
    }

    static func firstArgument(_ node: ExpandedNode) -> String? {
        guard let first = node.kdl.arguments.first, case .string(let text) = first.scalar else { return nil }
        return text
    }

    @Test("Statisches use setzt den Rumpf an seine Stelle")
    func staticUseExpandsInPlace() {
        let result = Self.run("""
        define "card" {
            param "title"
            text "{title}"
        }
        panel "p" {
            before
            use "card" title="Hi"
            after
        }
        """)
        #expect(result.diagnostics.isEmpty)
        #expect(Self.names(result.nodes) == ["panel"])
        #expect(Self.names(result.nodes[0].children) == ["before", "text", "after"])
    }

    @Test("Argumente und Vorgaben landen als Bindungen im Rahmen des Rumpfs")
    func argumentsAndDefaultsBecomeBindings() throws {
        let result = Self.run("""
        define "icon-button" {
            param "icon"
            param "fallback" default=#null
            param "tooltip" default=""
            button tooltip="{tooltip}" {
                icon "{icon}" fallback="{fallback}"
            }
        }
        panel "p" {
            use "icon-button" icon="bar-power" tooltip="Session"
        }
        """)
        #expect(result.diagnostics.isEmpty)
        let icon = try #require(Self.find("icon", in: result.nodes))
        let frame = try #require(icon.useFrame)
        #expect(frame.defineName == "icon-button")
        #expect(frame.bindings["icon"].map(Self.bindingText) == "argument:bar-power")
        #expect(frame.bindings["tooltip"].map(Self.bindingText) == "argument:Session")
        #expect(frame.bindings["fallback"].map(Self.bindingText) == "default:null")
        #expect(frame.parent == nil)
    }

    static func bindingText(_ binding: ParameterBinding) -> String {
        switch binding {
        case .argument(let value): return "argument:" + scalarText(value)
        case .defaultValue(let value): return "default:" + scalarText(value)
        case .runtime: return "runtime"
        }
    }

    static func scalarText(_ value: KDLValue) -> String {
        switch value.scalar {
        case .string(let text): return text
        case .number(_, let raw): return raw
        case .bool(let flag): return flag ? "true" : "false"
        case .null: return "null"
        }
    }

    @Test("Fehlender Pflichtparameter ist ein Fehler am use")
    func missingRequiredParameter() {
        let result = Self.run("""
        define "card" {
            param "title"
            text "{title}"
        }
        panel "p" {
            use "card"
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors.first?.message == "missing parameter 'title' for 'card'")
        #expect(errors.first?.span?.start.line == 6)
    }

    @Test("Unbekannter Parameter ist ein Fehler mit Vorschlag")
    func unknownParameterWithSuggestion() {
        let result = Self.run("""
        define "card" {
            param "tooltip" default=""
            text "{tooltip}"
        }
        panel "p" {
            use "card" toltip="x"
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors.first?.message == "unknown parameter 'toltip' for 'card'")
        #expect(errors.first?.help == "did you mean 'tooltip'?")
    }

    @Test("Unbekannter Name bei statischem use ist ein Fehler mit Vorschlag")
    func unknownDefineWithSuggestion() {
        let result = Self.run("""
        define "sidebar-clock" {
            text "12:00"
        }
        panel "p" {
            use "sidebar-clok"
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors.first?.message == "unknown define 'sidebar-clok'")
        #expect(errors.first?.help == "did you mean 'sidebar-clock'?")
    }

    @Test("Kinder landen im unbenannten Slot, Handler beim innersten Baustein")
    func handlerInSlotLandsInInnermostElement() throws {
        let result = Self.run("""
        define "sidebar-icon" {
            button class="outer" {
                row {
                    slot
                }
            }
        }
        panel "p" {
            use "sidebar-icon" {
                on-click { toggle "session" }
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
        let button = try #require(Self.find("button", in: result.nodes))
        #expect(Self.names(button.children) == ["row"])
        #expect(Self.names(button.children[0].children) == ["on-click"])
        #expect(button.children[0].children[0].useFrame == nil)
    }

    @Test("Benannte Slots mit fill, Kinder ausserhalb von fill gehen in den unbenannten Slot")
    func namedSlotsWithFill() throws {
        let result = Self.run("""
        define "card" {
            column {
                slot "header"
                slot
                slot "footer"
            }
        }
        panel "p" {
            use "card" {
                body-a
                fill "header" { title }
                body-b
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
        let column = try #require(Self.find("column", in: result.nodes))
        #expect(Self.names(column.children) == ["title", "body-a", "body-b"])
    }

    @Test("Kinder ohne slot im Rumpf sind ein Fehler")
    func childrenWithoutSlot() {
        let result = Self.run("""
        define "plain" {
            text "x"
        }
        panel "p" {
            use "plain" {
                text "y"
            }
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors.first?.message == "'plain' has no slot, so 'use' cannot have children")
        #expect(errors.first?.span?.start.line == 6)
    }

    @Test("fill auf einen unbekannten Slot ist ein Fehler mit Vorschlag")
    func fillUnknownSlot() {
        let result = Self.run("""
        define "card" {
            slot "header"
        }
        panel "p" {
            use "card" {
                fill "heder" { text "x" }
            }
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors.first?.message == "'card' has no slot 'heder'")
        #expect(errors.first?.help == "did you mean 'header'?")
    }

    @Test("Doppeltes fill fuer denselben Slot ist ein Fehler")
    func duplicateFill() {
        let result = Self.run("""
        define "card" {
            slot "header"
        }
        panel "p" {
            use "card" {
                fill "header" { text "a" }
                fill "header" { text "b" }
            }
        }
        """)
        #expect(Self.errors(result).map(\.message) == ["duplicate fill 'header'"])
    }

    @Test("define in einem Block ist ein Fehler")
    func defineInBlock() {
        let result = Self.run("""
        panel "p" {
            define "inner" { text "x" }
        }
        """)
        #expect(Self.errors(result).map(\.message) == ["'define' is only allowed at the top level"])
    }

    @Test("define in einem Block ueber include ist ein Fehler mit Kette")
    func defineInBlockViaInclude() throws {
        let result = Self.pipeline([
            "/config/shell.kdl": "panel \"p\" {\n    include \"parts.kdl\"\n}",
            "/config/parts.kdl": "define \"inner\" {\n    text \"x\"\n}",
        ])
        let error = try #require(Self.errors(result).first)
        #expect(Self.errors(result).count == 1)
        #expect(error.message == "'define' is only allowed at the top level")
        #expect(error.span?.file == "/config/parts.kdl")
        #expect(error.notes.map(\.message) == ["included from /config/shell.kdl:2:5"])
    }

    @Test("param mit festem Wurzelnamen oder Provider ist ein Fehler")
    func reservedParameterName() {
        let result = Self.run("""
        define "card" {
            param "surface" default=""
            param "battery" default=""
            text "x"
        }
        """)
        #expect(Self.errors(result).map(\.message) == ["'surface' is reserved", "'battery' is reserved"])
    }

    @Test("param mit dem Namen eines kuenftigen Providers ergibt eine Notiz")
    func futureProviderParameterName() {
        let result = Self.run("""
        define "card" {
            param "wallpaper" default=""
            text "{wallpaper}"
        }
        """)
        #expect(result.diagnostics.map(\.message) == ["'wallpaper' hides provider 'wallpaper'"])
        #expect(result.diagnostics.first?.severity == .note)
    }

    @Test("Parameter verdeckt ein let gleichen Namens")
    func parameterHidesLet() throws {
        let result = Self.run("""
        let icon="from-let"
        define "card" {
            param "icon"
            text "{icon}"
        }
        panel "p" {
            use "card" icon="from-use"
        }
        """)
        #expect(result.diagnostics.isEmpty)
        let text = try #require(Self.find("text", in: result.nodes))
        let resolved = try #require(text.useFrame?.resolve("icon"))
        #expect(Self.scalarText(resolved.value) == "from-use")
        #expect(resolved.scope == nil)
    }

    @Test("Argument eines inneren use wird im Rahmen des aeusseren aufgeloest")
    func nestedArgumentResolvesInOuterFrame() throws {
        let result = Self.run("""
        define "label" {
            param "caption"
            text "{caption}"
        }
        define "card" {
            param "title"
            column {
                use "label" caption="{title}!"
            }
        }
        panel "p" {
            use "card" title="Hi"
        }
        """)
        #expect(result.diagnostics.isEmpty)
        let text = try #require(Self.find("text", in: result.nodes))
        let inner = try #require(text.useFrame)
        #expect(inner.defineName == "label")
        let caption = try #require(inner.resolve("caption"))
        #expect(Self.scalarText(caption.value) == "{title}!")
        let outer = try #require(caption.scope)
        #expect(outer.defineName == "card")
        #expect(outer.resolve("title").map { Self.scalarText($0.value) } == "Hi")
        #expect(inner.resolve("title") == nil)
        let column = try #require(Self.find("column", in: result.nodes))
        #expect(column.useFrame === outer)
    }

    @Test("slot in den Kindern eines inneren use gehoert zum aeusseren define")
    func slotPassedThroughInnerUse() throws {
        let result = Self.run("""
        define "frame" {
            box {
                slot
            }
        }
        define "card" {
            use "frame" {
                slot
            }
        }
        panel "p" {
            use "card" {
                content
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
        let box = try #require(Self.find("box", in: result.nodes))
        #expect(Self.names(box.children) == ["content"])
        #expect(box.children[0].useFrame == nil)
    }

    @Test("Laufzeit-use bleibt als Vorlage stehen, unbekannter Name ist beim Laden kein Fehler")
    func runtimeUseStaysAsTemplate() throws {
        let result = Self.run("""
        define "sidebar-clock" {
            param "module"
            text "x"
        }
        panel "p" {
            each module in="{var.modules}" {
                use "sidebar-{module.kind}" module="{module}" {
                    fill "extra" { text "e" }
                }
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
        let use = try #require(Self.find("use", in: result.nodes))
        #expect(Self.firstArgument(use) == "sidebar-{module.kind}")
        #expect(Self.names(use.children) == ["fill"])
        #expect(result.defines.map(\.name) == ["sidebar-clock"])
    }

    @Test("override ersetzt ein define, use nimmt das letzte")
    func overrideReplacesDefine() throws {
        let result = Self.pipeline([
            "/config/shell.kdl": "include \"base.kdl\"\ndefine \"clock\" override=#true {\n    text \"new\"\n}",
            "/config/base.kdl": "define \"clock\" {\n    text \"old\"\n}\npanel \"p\" {\n    use \"clock\"\n}",
        ])
        #expect(result.diagnostics.isEmpty)
        let text = try #require(Self.find("text", in: result.nodes))
        #expect(Self.firstArgument(text) == "new")
    }

    @Test("Statischer use-Zyklus A B A ist ein Fehler mit ganzer Kette")
    func staticCycle() throws {
        let result = Self.run("""
        define "a" {
            use "b"
        }
        define "b" {
            use "a"
        }
        panel "p" {
            use "a"
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.map(\.message) == ["use cycle: a -> b -> a"])
        #expect(errors.first?.span?.start.line == 5)
        #expect(errors.first?.notes.map(\.message) == [
            "in use of 'b' at /config/shell.kdl:2:5",
            "in use of 'a' at /config/shell.kdl:8:5",
        ])
    }

    @Test("Ein define, das sich selbst statisch verwendet, ist ein Zyklus")
    func selfCycle() {
        let result = Self.run("""
        define "a" {
            column { use "a" }
        }
        """)
        #expect(Self.errors(result).map(\.message) == ["use cycle: a -> a"])
    }

    @Test("Golden File fuer den Zyklus A B A ueber include")
    func cycleGolden() {
        let root = URL(fileURLWithPath: DiagnosticGolden.file("use-zyklus", "shell.kdl")).deletingLastPathComponent()
        let included = IncludeExpander.expand(root: root, origin: .user, fileSystem: DiskFileSystem(), paths: Self.paths)
        #expect(included.diagnostics.isEmpty, "\(included.diagnostics)")
        let featured = RequireStage.run(included.nodes, shellVersion: "0.2.0", registry: .builtin)
        let lets = LetStage.run(featured.nodes, registry: .builtin)
        let result = UseStage.run(lets.nodes, registry: .builtin)
        var collector = DiagnosticCollector()
        for diagnostic in result.diagnostics {
            collector.add(diagnostic, stage: "use")
        }
        DiagnosticGolden.verify("use-zyklus", diagnostics: collector.finalize().diagnostics)
    }

    @Test("Spannen im Rumpf zeigen auf das define, die Kette nennt include und use")
    func spansPointToDefineChainNamesUse() throws {
        let result = Self.pipeline([
            "/config/shell.kdl": "include \"parts.kdl\"\npanel \"p\" {\n    use \"card\" title=\"Hi\"\n}",
            "/config/parts.kdl": "define \"card\" {\n    param \"title\"\n    text \"{title}\"\n}",
        ])
        #expect(result.diagnostics.isEmpty)
        let text = try #require(Self.find("text", in: result.nodes))
        #expect(text.kdl.span.file == "/config/parts.kdl")
        #expect(text.kdl.span.start.line == 3)
        let annotated = DiagnosticCollector.withExpansionChain(Diagnostic(.error, "probe", span: text.kdl.span), node: text)
        #expect(annotated.notes.map(\.message) == [
            "included from /config/shell.kdl:1:1",
            "in use of 'card' at /config/shell.kdl:3:5",
        ])
    }

    @Test("Standalone-Rumpf jedes define steht im Ergebnis, Parameter zur Laufzeit, Slots als Platzhalter")
    func definesCarryStandaloneBody() throws {
        let result = Self.run("""
        define "label" {
            param "caption"
            text "{caption}"
        }
        define "card" {
            param "title"
            param "size" type="number" default=2
            column {
                use "label" caption="{title}"
                slot "header"
                slot
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
        let card = try #require(result.defines.first { $0.name == "card" })
        #expect(card.parameters.map(\.name) == ["title", "size"])
        #expect(card.parameters.map(\.isRequired) == [true, false])
        #expect(card.parameters[1].type == .number)
        #expect(card.hasUnnamedSlot)
        #expect(card.namedSlots == ["header"])
        #expect(Self.names(card.body) == ["column"])
        #expect(Self.names(card.body[0].children) == ["text", "slot", "slot"])
        let frame = try #require(card.body[0].useFrame)
        #expect(frame.useSpan == nil)
        #expect(frame.bindings["title"].map(Self.bindingText) == "runtime")
        #expect(frame.resolve("title") == nil)
    }

    @Test("Paket-define ohne Praefix ergibt eine Warnung")
    func packageDefineWithoutPrefix() {
        let result = Self.pipeline(
            [
                "/config/packages/weather-cards/shell.kdl": "define \"hourly\" {\n    text \"x\"\n}\ndefine \"weather-cards/daily\" {\n    text \"y\"\n}",
            ],
            root: "/config/packages/weather-cards",
            origin: .pkg("weather-cards")
        )
        #expect(result.diagnostics.map(\.message) == ["define 'hourly' in package 'weather-cards' should be named 'weather-cards/hourly'"])
        #expect(result.diagnostics.first?.severity == .warning)
    }

    @Test("Literales Argument mit falschem Typ ist ein Fehler")
    func literalArgumentWithWrongType() {
        let result = Self.run("""
        define "gauge" {
            param "value" type="number"
            text "{value}"
        }
        panel "p" {
            use "gauge" value="high"
            use "gauge" value="{var.level}"
            use "gauge" value=3
        }
        """)
        #expect(Self.errors(result).map(\.message) == ["parameter 'value' of 'gauge' expects number"])
    }

    @Test("slot, fill und param ausserhalb ihres Platzes sind Fehler")
    func misplacedLanguageNodes() {
        let result = Self.run("""
        define "card" {
            column {
                param "late"
            }
        }
        panel "p" {
            slot
            fill "x" { text "y" }
        }
        """)
        #expect(Set(Self.errors(result).map(\.message)) == [
            "'param' is only allowed directly inside 'define'",
            "'slot' is only allowed inside 'define'",
            "'fill' is only allowed directly inside 'use'",
        ])
    }

    @Test("Doppelter Parameter und ungueltiger Typ sind Fehler")
    func duplicateParameterAndInvalidType() {
        let result = Self.run("""
        define "card" {
            param "title"
            param "title"
            param "size" type="huge"
        }
        """)
        #expect(Self.errors(result).map(\.message) == [
            "duplicate parameter 'title'",
            "'type=' must be one of string, number, bool, list, record, any",
        ])
    }

    @Test("Fehler im Rumpf werden einmal gemeldet, nicht je Verwendung")
    func bodyErrorsReportedOnce() {
        let result = Self.run("""
        define "card" {
            use "missing"
        }
        panel "p" {
            use "card"
            use "card"
            use "card"
        }
        """)
        #expect(Self.errors(result).map(\.message) == ["unknown define 'missing'"])
    }

    @Test("Ein Slot, der zweimal vorkommt, setzt die Kinder zweimal ein")
    func slotTwiceCopiesChildren() throws {
        let result = Self.run("""
        define "twice" {
            slot
            slot
        }
        panel "p" {
            use "twice" { item }
        }
        """)
        #expect(result.diagnostics.isEmpty)
        #expect(Self.names(result.nodes[0].children) == ["item", "item"])
    }

    static func fanOutConfig(levels: Int, wrapped: Bool) -> String {
        var text = "define \"d0\" {\n    text \"x\"\n}\n"
        for level in 1...levels {
            let call = "use \"d\(level - 1)\"; use \"d\(level - 1)\""
            text += "define \"d\(level)\" {\n    " + (wrapped ? "column { \(call) }" : call) + "\n}\n"
        }
        text += "panel \"p\" {\n    use \"d\(levels)\"\n}\n"
        return text
    }

    @Test("Fan-out 2 ueber 32 Ebenen scheitert am Budget, nicht an Speicher oder Zeit", arguments: [false, true])
    func exponentialFanOutHitsBudget(wrapped: Bool) {
        let clock = ContinuousClock()
        var result: UseStageResult?
        let elapsed = clock.measure {
            result = Self.run(Self.fanOutConfig(levels: 32, wrapped: wrapped))
        }
        let errors = result.map(Self.errors) ?? []
        #expect(errors.map(\.message) == ["config expands to more than \(ConfigLimits.maxExpansionBudget) nodes"])
        #expect((result?.nodeCount ?? .max) <= ConfigLimits.maxExpansionBudget + 1)
        #expect(elapsed < .seconds(10))
        #expect(errors.first?.notes.contains { $0.message.hasPrefix("in use of 'd") } == true)
    }

    @Test("Fan-out 2 ueber 32 Ebenen mit leerem Baustein scheitert am Budget")
    func exponentialFanOutOfEmptyDefineHitsBudget() {
        var text = "define \"d0\" {}\n"
        for level in 1...32 {
            text += "define \"d\(level)\" {\n    use \"d\(level - 1)\"; use \"d\(level - 1)\"\n}\n"
        }
        text += "panel \"p\" {\n    use \"d32\"\n}\n"
        let clock = ContinuousClock()
        var result: UseStageResult?
        let elapsed = clock.measure {
            result = Self.run(text)
        }
        #expect(result.map(Self.errors)?.map(\.message) == ["config expands to more than \(ConfigLimits.maxExpansionBudget) nodes"])
        #expect(elapsed < .seconds(10))
    }

    @Test("Leere Slots zaehlen ebenfalls gegen das Budget")
    func emptySlotInsertionsCountAgainstBudget() {
        let slots = Array(repeating: "    slot", count: 2000).joined(separator: "\n")
        let uses = Array(repeating: "    use \"many\"", count: 60).joined(separator: "\n")
        let result = Self.run("define \"many\" {\n\(slots)\n}\npanel \"p\" {\n\(uses)\n}")
        #expect(Self.errors(result).map(\.message) == ["config expands to more than \(ConfigLimits.maxExpansionBudget) nodes"])
    }

    @Test("Lineare Vervielfachung zaehlt gegen dasselbe Budget")
    func linearFanOutHitsBudget() {
        let body = Array(repeating: "    text \"x\"", count: 1000).joined(separator: "\n")
        let uses = Array(repeating: "    use \"block\"", count: 101).joined(separator: "\n")
        let result = Self.run("define \"block\" {\n\(body)\n}\npanel \"p\" {\n\(uses)\n}")
        #expect(Self.errors(result).map(\.message) == ["config expands to more than \(ConfigLimits.maxExpansionBudget) nodes"])
    }

    @Test("Knapp unter dem Budget laedt ohne Diagnose")
    func justBelowBudgetLoads() {
        let body = Array(repeating: "    text \"x\"", count: 1000).joined(separator: "\n")
        let uses = Array(repeating: "    use \"block\"", count: 98).joined(separator: "\n")
        let result = Self.run("define \"block\" {\n\(body)\n}\npanel \"p\" {\n\(uses)\n}")
        #expect(result.diagnostics.isEmpty)
        #expect(result.nodes[0].children.count == 98_000)
    }

    @Test("Eine Kette von 80 statischen use endet mit Diagnose statt Stapelueberlauf")
    func longUseChainHitsDepthLimit() {
        var text = ""
        for index in 0..<80 {
            text += "define \"d\(index)\" {\n    use \"d\(index + 1)\"\n}\n"
        }
        text += "define \"d80\" {\n    text \"end\"\n}\npanel \"p\" {\n    use \"d0\"\n}\n"
        let result = Self.run(text)
        #expect(Self.errors(result).map(\.message) == ["use is nested deeper than \(ConfigLimits.maxExpandedDepth) levels"])
    }

    static func nested(_ depth: Int, around inner: String) -> String {
        String(repeating: "column { ", count: depth) + inner + String(repeating: " }", count: depth)
    }

    @Test("Schachtelungstiefe 64 gilt fuer den Baum nach use")
    func expandedTreeDepthLimit() {
        let result = Self.run("define \"deep\" {\n    \(Self.nested(40, around: "text \"x\""))\n}\npanel \"p\" {\n    \(Self.nested(30, around: "use \"deep\""))\n}")
        #expect(Self.errors(result).map(\.message) == ["config is nested deeper than \(ConfigLimits.maxExpandedDepth) levels after use"])
    }

    @Test("Schachtelungstiefe 64 gilt auch fuer Kinder, die ein slot tiefer setzt")
    func slotShiftDepthLimit() {
        let result = Self.run("define \"wrap\" {\n    \(Self.nested(30, around: "slot"))\n}\npanel \"p\" {\n    use \"wrap\" { use \"wrap\" { use \"wrap\" { text \"x\" } } }\n}")
        #expect(Self.errors(result).map(\.message) == ["config is nested deeper than \(ConfigLimits.maxExpandedDepth) levels after use"])
    }

    @Test("Tiefe knapp unter 64 nach use laedt")
    func depthJustBelowLimitLoads() {
        let result = Self.run("define \"deep\" {\n    \(Self.nested(30, around: "text \"x\""))\n}\npanel \"p\" {\n    \(Self.nested(30, around: "use \"deep\""))\n}")
        #expect(result.diagnostics.isEmpty)
    }
}
