import Testing
import Foundation
import ApolloBase
import ApolloKDL
@testable import ApolloConfig

@Suite("SchemaStage Namen, Bereiche und Spalten")
struct SchemaStageScopeTests {
    static func all(_ text: String) -> [Diagnostic] {
        let fs = MemoryFileSystem(["/config/shell.kdl": text])
        let included = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: UseStageTests.paths)
        let featured = RequireStage.run(included.nodes, shellVersion: "0.2.0", registry: .builtin)
        let used = UseStage.run(featured.nodes, registry: .builtin)
        let disabled = DisableStage.run(used.nodes, registry: .builtin)
        let checked = SchemaStage.run(disabled.nodes, defines: used.defines, registry: .builtin)
        return included.diagnostics + featured.diagnostics + used.diagnostics + disabled.diagnostics + checked.diagnostics
    }

    static func errors(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) -> [Diagnostic] {
        SchemaStageTests.errors(SchemaStageTests.pipeline(text, sourceLocation: sourceLocation))
    }

    @Test("Schleifenvariable und Index sind in key sichtbar")
    func eachVariableAndIndexAreVisibleInKey() {
        let result = SchemaStageTests.pipeline("""
        panel "sidebar" {
            each item in="{apps.dock}" key="{item.id ?? i}" index="i" {
                text "{i}. {item.name}"
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("in sieht die eigene Schleifenvariable nicht")
    func inDoesNotSeeItsOwnVariable() {
        let errors = Self.errors("""
        panel "sidebar" {
            each item in="{item.children}" {
            }
        }
        """)
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("unknown root 'item'") == true)
    }

    @Test("each, when, else und switch in Handlern pruefen ihre Kinder als Aktionen")
    func languageNodesInHandlersKeepActionContext() {
        let result = SchemaStageTests.pipeline("""
        panel "sidebar" {
            button {
                on-click {
                    each app in="{apps.dock}" {
                        toggle "sidebar"
                    }
                    when "{var.open}" {
                        toggle "sidebar"
                    }
                    else {
                        toggle "sidebar"
                    }
                    switch "{var.tab}" {
                        case "a" {
                            toggle "sidebar"
                        }
                        default {
                            toggle "sidebar"
                        }
                    }
                }
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("ein Element in einem each im Handler ist ein Fehler")
    func elementInsideEachInHandlerIsAnError() {
        let errors = Self.errors("""
        panel "sidebar" {
            button {
                on-click {
                    each app in="{apps.dock}" {
                        text "x"
                    }
                }
            }
        }
        """)
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("unknown node 'text'") == true)
    }

    @Test("each, when und switch in Menues pruefen ihre Kinder als Menue-Eintraege")
    func languageNodesInMenusKeepMenuContext() {
        let result = SchemaStageTests.pipeline("""
        panel "sidebar" {
            button {
                menu {
                    each app in="{apps.dock}" {
                        item "{app.name}" {
                            toggle "sidebar"
                        }
                    }
                    when "{var.open}" {
                        separator
                    }
                    switch "{var.tab}" {
                        case "a" {
                            item "A" {
                                toggle "sidebar"
                            }
                        }
                        default {
                            separator
                        }
                    }
                }
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("Schleifenvariable mit dem Namen eines Providers ist reserviert")
    func eachVariableWithProviderNameIsReserved() {
        let diagnostics = Self.all("""
        panel "sidebar" {
            each perf in="{apps.dock}" {
                text "{perf.name}"
            }
        }
        """)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.severity == .error)
        #expect(diagnostics.first?.message == "'perf' is reserved")
        #expect(diagnostics.first?.span?.start.line == 2)
    }

    @Test("Index mit dem Namen einer festen Wurzel ist reserviert")
    func eachIndexWithFixedRootNameIsReserved() {
        let diagnostics = Self.all("""
        panel "sidebar" {
            each app in="{apps.dock}" index="event" {
                text "{event}"
            }
        }
        """)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.message == "'event' is reserved")
    }

    @Test("Schleifenvariable verdeckt einen spaeteren Provider mit Notiz")
    func eachVariableHidesFutureProviderWithNote() {
        let diagnostics = Self.all("""
        panel "sidebar" {
            each reminders in="{apps.dock}" {
                text "{reminders.path}"
            }
        }
        """)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.severity == .note)
        #expect(diagnostics.first?.message == "'reminders' hides provider 'reminders'")
    }

    @Test("Argumente eines use werden an der Aufrufstelle geprueft")
    func useArgumentsAreCheckedAtTheCallSite() {
        let errors = Self.errors("""
        define "card" {
            param "title"
            text "{title}"
        }
        panel "sidebar" {
            use "card" title="{apps.dokc}"
        }
        """)
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("unknown field 'dokc' on 'apps'") == true)
        #expect(errors.first?.help?.contains("dock") == true)
        #expect(errors.first?.span?.start.line == 6)
    }

    @Test("Argumente eines use sehen var und each der Aufrufstelle")
    func useArgumentsSeeCallSiteVarAndEach() {
        let result = SchemaStageTests.pipeline("""
        var prefix "App"
        define "card" {
            param "title"
            text "{title}"
        }
        panel "sidebar" {
            each item in="{apps.dock}" {
                use "card" title="{var.prefix} {item.name}"
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("Argument aus aeusserem each landet in einem Rumpf mit gleichnamigem each")
    func argumentFromOuterEachMeetsBodyEachWithSameName() {
        let result = SchemaStageTests.pipeline("""
        define "list" {
            param "label"
            each item in="{apps.running}" {
                text "{label} {item.name}"
            }
        }
        panel "sidebar" {
            each item in="{apps.dock}" {
                use "list" label="{item.name}"
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("Argument eines verschachtelten use wird mit den Parametern des aeusseren Rumpfs geprueft")
    func nestedUseArgumentSeesOuterParameters() {
        let errors = Self.errors("""
        define "inner" {
            param "value"
            text "{value}"
        }
        define "outer" {
            param "label"
            use "inner" value="{label} {lable}"
        }
        panel "sidebar" {
            use "outer" label="x"
        }
        """)
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("unknown root 'lable'") == true)
    }

    @Test("ein nie benutztes define wird mit seinen Parametern geprueft")
    func unusedDefineBodyIsChecked() {
        let errors = Self.errors("""
        define "unused" {
            param "title"
            text "{title | rond}"
        }
        """)
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("unknown filter 'rond'") == true)
    }

    @Test("ein benutztes define meldet Fehler im Rumpf nicht doppelt")
    func usedDefineBodyIsNotReportedTwice() {
        let errors = Self.errors("""
        define "card" {
            param "title"
            text "{title | rond}"
        }
        panel "sidebar" {
            use "card" title="x"
        }
        """)
        #expect(errors.count == 1)
    }

    @Test("Laufzeit-use prueft Parameter als Ausdruecke der Aufrufstelle")
    func runtimeUseChecksParametersAsExpressions() {
        let errors = Self.errors("""
        define "sidebar-card" {
            param "module"
            text "{module.name}"
        }
        panel "sidebar" {
            each m in="{apps.dock}" {
                use "sidebar-{m.kind}" module="{m}" extra="{apps.dokc}"
            }
        }
        """)
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("unknown field 'dokc' on 'apps'") == true)
    }

    @Test("Tastenkombinationen werden mit KeyChord geprueft")
    func keyChordLiteralsAreParsed() {
        let errors = Self.errors("""
        bind "alt+spcae" {
            toggle "sidebar"
        }
        bind "alt+space" {
            toggle "sidebar"
        }
        """)
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("key-chord") == true)
        #expect(errors.first?.span?.start.line == 1)
    }

    @Test("doppelte Klammern sind an Stellen ohne Ausdruck kein Fehler")
    func doubledBracesAreNoExpression() {
        let result = SchemaStageTests.pipeline("""
        panel "sidebar" {
            button {
                menu {
                    item "A" shortcut="{{x}}" {
                        toggle "sidebar"
                    }
                }
            }
        }
        """)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("unbekannte Wurzel und unbekanntes Feld zeigen auf ihre Spalte im String")
    func rootAndFieldErrorsPointAtTheirColumn() {
        let errors = Self.errors("""
        panel "sidebar" {
            text "{itme.name}"
            text "{perf.cpuu}"
            text "{itme} {itme}"
        }
        """)
        #expect(errors.count == 4)
        let positions = errors.compactMap { $0.span }.map { [$0.start.line, $0.start.column, $0.end.column] }
        #expect(positions == [[2, 12, 16], [3, 17, 21], [4, 12, 16], [4, 19, 23]])
    }

    @Test("Spalte nach einem Emoji zaehlt Unicode-Zeichen")
    func columnAfterEmojiCountsCharacters() {
        let errors = Self.errors("""
        panel "sidebar" {
            text "🙂 {itme}"
        }
        """)
        #expect(errors.count == 1)
        #expect(errors.first?.span?.start.column == 14)
        #expect(errors.first?.span?.end.column == 18)
    }

    @Test("Raw-String und mehrzeiliger String melden die ganze Spanne")
    func rawAndMultilineStringsReportTheWholeSpan() {
        let errors = Self.errors("""
        panel "sidebar" offset-x=#"{1 +}"# {
            text #"{itme}"#
            text "\\t{itme}"
            text \"\"\"
                {itme}
                \"\"\"
        }
        """)
        #expect(errors.count == 4)
        let starts = errors.compactMap { $0.span }.map { [$0.start.line, $0.start.column] }
        #expect(starts == [[1, 26], [2, 10], [3, 10], [4, 10]])
    }

    @Test("512 Token und 32 Klammerebenen ergeben eine Diagnose statt eines Absturzes")
    func expressionLimitsProduceDiagnostics() {
        let long = Array(repeating: "1", count: 300).joined(separator: " + ")
        let deep = String(repeating: "(", count: 40) + "1" + String(repeating: ")", count: 40)
        let errors = Self.errors("""
        panel "sidebar" {
            text "{\(long)}"
            text "{\(deep)}"
        }
        """)
        #expect(errors.count == 2)
        #expect(errors.first?.message.contains("too long") == true)
        #expect(errors.map { $0.span?.start.line } == [2, 3])
    }
}
