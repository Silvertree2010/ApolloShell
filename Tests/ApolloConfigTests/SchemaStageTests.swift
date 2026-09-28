import Testing
import Foundation
import ApolloBase
import ApolloKDL
@testable import ApolloConfig

@Suite("SchemaStage")
struct SchemaStageTests {
    static func pipeline(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) -> SchemaStageResult {
        let fs = MemoryFileSystem(["/config/shell.kdl": text])
        let included = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: UseStageTests.paths)
        #expect(included.diagnostics.isEmpty, sourceLocation: sourceLocation)
        let featured = RequireStage.run(included.nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(featured.diagnostics.isEmpty, sourceLocation: sourceLocation)
        let used = UseStage.run(featured.nodes, registry: .builtin)
        #expect(used.diagnostics.isEmpty, sourceLocation: sourceLocation)
        let disabled = DisableStage.run(used.nodes, registry: .builtin)
        #expect(disabled.diagnostics.isEmpty, sourceLocation: sourceLocation)
        return SchemaStage.run(disabled.nodes, defines: used.defines, registry: .builtin)
    }

    static func errors(_ result: SchemaStageResult) -> [Diagnostic] {
        result.diagnostics.filter { $0.severity == .error }
    }

    @Test("eine gueltige Config hat keine Diagnosen")
    func validConfigHasNoDiagnostics() {
        let result = Self.pipeline("""
        panel "sidebar" anchor="left" {
            text "Hello"
            button {
                on-click {
                    toggle "sidebar"
                }
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
        #expect(result.nodes.map(\.name) == ["panel"])
    }

    @Test("unbekannter Knoten meldet einen Vorschlag")
    func unknownNodeSuggestsClosestName() {
        let result = Self.pipeline("""
        pannel "sidebar" {
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("unknown node 'pannel'"))
        #expect(errors[0].help?.contains("panel") == true)
    }

    @Test("unbekannte Property meldet einen Vorschlag")
    func unknownPropertySuggestsClosestName() {
        let result = Self.pipeline("""
        panel "sidebar" ancor="left" {
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("unknown property 'ancor'"))
        #expect(errors[0].help?.contains("anchor") == true)
    }

    @Test("unbekannter Filter meldet einen Vorschlag")
    func unknownFilterSuggestsClosestName() {
        let result = Self.pipeline("""
        panel "sidebar" {
            text "{perf.cpu | rond}"
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("unknown filter 'rond'"))
        #expect(errors[0].help?.contains("round") == true)
    }

    @Test("unbekanntes Provider-Feld meldet einen Vorschlag")
    func unknownProviderFieldSuggestsClosestName() {
        let result = Self.pipeline("""
        panel "sidebar" {
            text "{perf.cpuu}"
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("unknown field 'cpuu' on 'perf'"))
        #expect(errors[0].help?.contains("cpu") == true)
    }

    @Test("falscher Typ eines Literals ist ein Fehler")
    func wrongLiteralTypeFails() {
        let result = Self.pipeline("""
        panel "sidebar" offset-x="left" {
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("expects number"))
    }

    @Test("fehlende Pflicht-Property ist ein Fehler")
    func missingRequiredPropertyFails() {
        let result = Self.pipeline("""
        panel "sidebar" {
            slider {
            }
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("missing property 'value'"))
    }

    @Test("falscher Kontext ist ein Fehler")
    func wrongContextFails() {
        let result = Self.pipeline("""
        text "top level"
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("unknown node 'text'"))
    }

    @Test("Ausdruck, wo keiner erlaubt ist, ist ein Fehler")
    func expressionWhereNoneAllowedFails() {
        let result = Self.pipeline("""
        popup "launcher" hover-margin="{1}" {
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("no expression allowed here"))
    }

    @Test("script ist reserviert und meldet einen festen Fehler")
    func scriptNodeIsReserved() {
        let result = Self.pipeline("""
        script "foo.lua"
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message == "Lua scripting comes in a later version")
    }

    @Test("Filter lua ist reserviert und meldet einen festen Fehler")
    func luaFilterIsReserved() {
        let result = Self.pipeline("""
        panel "sidebar" {
            text "{perf.cpu | lua}"
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message == "Lua scripting comes in a later version")
    }

    @Test("experimental markierte Property meldet eine Notiz")
    func experimentalPropertyIsANote() {
        let result = Self.pipeline("""
        panel "sidebar" fuse-group="a" {
        }
        """)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .note)
        #expect(result.diagnostics[0].message.contains("experimental"))
    }

    @Test("each-Variable ist innerhalb des each als Ausdruck gueltig")
    func eachVariableIsValidInsideEach() {
        let result = Self.pipeline("""
        panel "sidebar" {
            each item in="{apps.dock}" {
                text "{item.name}"
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("Wurzel ausserhalb eines each ist unbekannt")
    func unknownRootOutsideEachIsAnError() {
        let result = Self.pipeline("""
        panel "sidebar" {
            text "{item.name}"
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("unknown root 'item'"))
    }

    @Test("event ist nur in Handlern gueltig")
    func eventOnlyValidInHandlers() {
        let result = Self.pipeline("""
        panel "sidebar" {
            text "{event.modifiers}"
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("'event' is not valid here"))
    }

    @Test("event ist innerhalb eines Handlers gueltig")
    func eventValidInsideHandler() {
        let result = Self.pipeline("""
        panel "sidebar" {
            button {
                on-click {
                    set "x" "{event.modifiers}"
                }
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("innere each-Variable hat Vorrang vor der aeusseren mit gleichem Namen")
    func innerEachVariableShadowsOuterOne() {
        let result = Self.pipeline("""
        panel "sidebar" {
            each item in="{apps.dock}" {
                each item in="{item.children}" {
                    text "{item.name}"
                }
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("Slot-Inhalt sieht die Namen der Aufrufstelle, nicht die each-Variablen des Rumpfs")
    func slotContentSeesCallSiteNamesNotRumpEachVariables() {
        let result = Self.pipeline("""
        define "wrapper" {
            each row in="{apps.dock}" {
                slot
            }
        }
        panel "sidebar" {
            each item in="{apps.dock}" {
                use "wrapper" {
                    text "{item.name}"
                }
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("row als Rumpf-Variable ist im eingesetzten Slot-Inhalt nicht sichtbar")
    func rumpEachVariableIsNotVisibleInSlotContent() {
        let result = Self.pipeline("""
        define "wrapper" {
            each row in="{apps.dock}" {
                slot
            }
        }
        panel "sidebar" {
            use "wrapper" {
                text "{row.name}"
            }
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].message.contains("unknown root 'row'"))
    }

    @Suite("Typtabelle")
    struct TypeTable {
        struct Case {
            var type: ValueType
            var valid: KDLValue
            var invalid: KDLValue
        }

        static let cases: [Case] = [
            Case(type: .string, valid: KDLValue(.string("x")), invalid: KDLValue(.number(1, raw: "1"))),
            Case(type: .number, valid: KDLValue(.number(1, raw: "1")), invalid: KDLValue(.string("x"))),
            Case(type: .bool, valid: KDLValue(.bool(true)), invalid: KDLValue(.string("x"))),
            Case(type: .duration, valid: KDLValue(.string("500ms")), invalid: KDLValue(.string("later"))),
            Case(type: .enumeration(["a", "b"]), valid: KDLValue(.string("a")), invalid: KDLValue(.string("c"))),
            Case(type: .oneOf([.bool, .enumeration(["auto"])]), valid: KDLValue(.string("auto")), invalid: KDLValue(.string("weird"))),
        ]

        @Test("gueltige und ungueltige Literale je ValueType", arguments: cases)
        func literalMatchesPerType(_ testCase: Case) {
            #expect(TypeChecker.literalMatches(testCase.valid, testCase.type))
            #expect(!TypeChecker.literalMatches(testCase.invalid, testCase.type))
        }
    }

    @Test("Ausdrucksfehler tragen die Spalte im String")
    func expressionErrorCarriesColumnInString() {
        let result = Self.pipeline("""
        panel "sidebar" offset-x="{1 +}" {
        }
        """)
        let errors = Self.errors(result)
        #expect(errors.count == 1)
        #expect(errors[0].span?.start.line == 1)
        #expect(errors[0].span?.start.column == 31)
    }

    @Test("Golden File deckt mehrere Diagnosearten gleichzeitig ab")
    func goldenFileCoversMultipleDiagnosticKinds() {
        let root = URL(fileURLWithPath: DiagnosticGolden.file("schema-mehrere-arten", "shell.kdl")).deletingLastPathComponent()
        let sources = DiagnosticGolden.sources(for: "schema-mehrere-arten")
        guard let text = sources[root.appendingPathComponent("shell.kdl").path] else {
            Issue.record("fixture missing")
            return
        }
        let result = Self.pipeline(text)
        var collector = DiagnosticCollector()
        for diagnostic in result.diagnostics {
            collector.add(diagnostic, stage: "schema")
        }
        DiagnosticGolden.verify("schema-mehrere-arten", diagnostics: collector.finalize().diagnostics)
    }
}
