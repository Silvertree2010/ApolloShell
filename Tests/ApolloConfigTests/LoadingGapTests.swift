import Testing
import Foundation
import ApolloBase
import ApolloKDL
@testable import ApolloConfig

@Suite("Luecken vor dem IR-Bau")
struct LoadingGapTests {
    @Test("Argumente eines use mit leerem Rumpf werden an der Aufrufstelle geprueft")
    func argumentsOfEmptyUseAreChecked() {
        let diagnostics = SchemaStageScopeTests.all("""
        define "noop" {
            param "label"
        }
        panel "sidebar" {
            each item in="{apps.dock}" {
                use "noop" label="{item.name}"
            }
            use "noop" label="{apps.dokc}"
        }
        """)
        #expect(diagnostics.map(\.message) == ["unknown field 'dokc' on 'apps'"])
        #expect(diagnostics.first?.span?.start.line == 8)
    }

    @Test("Ein leeres use erzeugt keinen sichtbaren Knoten")
    func emptyUseLeavesNoVisibleNode() {
        let fs = MemoryFileSystem(["/config/shell.kdl": """
        define "noop" {
            param "label"
        }
        panel "sidebar" {
            use "noop" label="x"
            text "after"
        }
        """])
        let included = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: UseStageTests.paths)
        let lets = LetStage.run(included.nodes, registry: .builtin)
        let used = UseStage.run(lets.nodes, registry: .builtin)
        let panel = used.nodes.first { $0.kdl.name == "panel" }
        #expect(panel?.children.filter { !$0.isExpansionMarker }.map(\.kdl.name) == ["text"])
        #expect(panel?.children.filter(\.isExpansionMarker).map(\.kdl.name) == ["use"])
    }

    @Test("fill in einem eingebauten Baustein ist ein benannter Slot")
    func fillInsideBuiltinElementIsAllowed() {
        let diagnostics = SchemaStageScopeTests.all("""
        define "volume" {
            slider value="{audio.volume}" {
                fill "thumb" {
                    text "{audio.volume | percent}"
                }
            }
        }
        osd "volume" {
            use "volume"
            slider value="{audio.volume}" {
                fill "thumb" {
                    icon "speaker"
                }
            }
        }
        """)
        #expect(diagnostics.isEmpty)
    }

    @Test("fill auf oberster Ebene bleibt ein Fehler")
    func fillAtTopLevelIsStillAnError() {
        let diagnostics = SchemaStageScopeTests.all("""
        fill "thumb" {
            text "x"
        }
        """)
        #expect(diagnostics.map(\.message).contains("'fill' is only allowed directly inside 'use'"))
    }

    @Test("Provider-Einstellungen auf oberster Ebene werden gegen die Registry geprueft")
    func providerSettingsAreChecked() {
        let valid = SchemaStageScopeTests.all("""
        var weather-source "open-meteo"
        weather source="{var.weather-source}" place="{var.places | first}"
        apps file-manager="{var.file-manager}"
        clock first-weekday="monday"
        """)
        #expect(valid.filter { $0.severity == .error }.isEmpty)
        let invalid = SchemaStageScopeTests.all("""
        weather sourc="wttr"
        """)
        #expect(invalid.map(\.message) == ["unknown property 'sourc' on 'weather'"])
        #expect(invalid.first?.help == "did you mean 'source'?")
    }

    @Test("Provider-Aktionen in Handlern sind bekannt")
    func providerActionsInHandlers() {
        let diagnostics = SchemaStageScopeTests.all("""
        osd "volume" {
            slider value="{audio.volume}" {
                on-change { audio.set-volume "{event.value}" }
            }
        }
        """)
        #expect(diagnostics.isEmpty)
        #expect(SchemaRegistry.builtin.action("audio.set-volume")?.name == "audio.set-volume")
        #expect(SchemaRegistry.builtin.action("audio.nothing") == nil)
    }

    @Test("Menue-Quellen pruefen ihre eigenen Properties")
    func menuSourcesCheckTheirProperties() {
        let valid = SchemaStageScopeTests.all("""
        panel "dock" {
            each app in="{apps.dock}" {
                button {
                    menu {
                        source "app-windows" app="{app}"
                        source "app-dock" app="{app}" fallback="commands"
                    }
                }
            }
        }
        """)
        #expect(valid.isEmpty)
        let invalid = SchemaStageScopeTests.all("""
        panel "dock" {
            button {
                menu {
                    source "app-window" app="x"
                }
            }
        }
        """)
        #expect(invalid.map(\.message) == ["unknown menu source 'app-window'"])
        #expect(invalid.first?.help == "did you mean 'app-windows'?")
    }

    @Test("override=#true ist an Oberflaechen erlaubt")
    func overrideOnSurfaces() {
        let diagnostics = SchemaStageScopeTests.all("""
        panel "bar" {
        }
        panel "bar" override=#true {
        }
        """)
        #expect(diagnostics.isEmpty)
    }
}
