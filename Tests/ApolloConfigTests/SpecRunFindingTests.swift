import Testing
import Foundation
import ApolloBase
import ApolloConfig

@Suite("Funde aus dem Lauf ueber die Spec-Beispiele")
struct SpecRunFindingTests {
    static func messages(_ result: ConfigLoadResult) -> [String] {
        result.diagnostics.map { "\($0.span.map { "\($0.start.line):\($0.start.column)" } ?? "-") \($0.message)" }
    }

    @Test("var mit Kindern als Liste und mit Properties als Record")
    func varDefaultsFromChildrenAndProperties() throws {
        let result = LoaderHarness.load(["/config/shell.kdl": """
        var sidebar-modules persist=#true {
            - kind="dashboard-button"
            - kind="spaces" style="dots"
        }
        var place name="Chur" latitude=46.85
        panel "bar" {
            text "{var.place.name}"
        }
        """])
        #expect(result.diagnostics.isEmpty, "\(Self.messages(result))")
        let ir = try #require(result.ir)
        #expect(ir.vars.map(\.name) == ["sidebar-modules", "place"])
        #expect(ir.vars.map(\.type) == [.list, .record])
        #expect(ir.vars[0].persist)
    }

    @Test("Properties einer Oberflaeche sehen theme, surfaces, surface und screen")
    func surfacePropertiesSeeSurfaceRoots() {
        let result = LoaderHarness.load(["/config/shell.kdl": """
        toast "default" offset-y="{surfaces.utilities.open ? surfaces.utilities.height + 12 : 0}" {
            text "{toast.title}"
        }
        panel "bar" class="{theme.set['bar-color'] ? 'themed' : 'plain'} {surface.open ? 'open' : ''} {screen.notch ? 'notch' : ''}" {
        }
        panel "utilities" {
        }
        """])
        #expect(result.diagnostics.isEmpty, "\(Self.messages(result))")
        #expect(result.ir != nil)
    }

    @Test("surfaces.<id> prueft das Feld hinter der Kennung")
    func surfacesChecksFieldAfterId() {
        let result = LoaderHarness.load(["/config/shell.kdl": """
        panel "bar" {
            text "{surfaces.utilities.wdth}"
        }
        """])
        #expect(result.diagnostics.map(\.message) == ["unknown field 'wdth' on 'surfaces'"])
        #expect(result.diagnostics.first?.help == "did you mean 'width'?")
    }

    @Test("event bleibt in Properties einer Oberflaeche ungueltig")
    func eventStaysInvalidOnSurfaceProperties() {
        let result = LoaderHarness.load(["/config/shell.kdl": "panel \"bar\" class=\"{event.value}\" {\n}\n"])
        #expect(result.diagnostics.map(\.message) == ["'event' is not valid here"])
    }

    @Test("flyout mit Vorlage als anchor und on-close")
    func flyoutAnchorTemplateAndOnClose() {
        let result = LoaderHarness.load(["/config/shell.kdl": """
        var status-popout ""
        panel "sidebar" {
            text "wifi" id="status-wifi"
            flyout id="status-popout" anchor="{'status-' + var.status-popout}" side="right" open="{var.status-popout != ''}" {
                on-close { set "status-popout" "" }
                text "details"
            }
        }
        """])
        #expect(result.diagnostics.isEmpty, "\(Self.messages(result))")
        #expect(result.ir != nil)
    }

    @Test("Provider-Aktionen mit benannten Properties wie in providers.md")
    func providerActionProperties() {
        let result = LoaderHarness.load(["/config/shell.kdl": """
        panel "dock" {
            each app in="{apps.dock}" {
                button {
                    on-click { apps.click "{app}" modifiers="{event.modifiers}" }
                    menu {
                        item "Show in Finder" { apps.reveal "{app}" in="finder" }
                    }
                }
            }
        }
        bind "alt+h" { system.hide-apps keep-frontmost=#true }
        """])
        #expect(result.diagnostics.isEmpty, "\(Self.messages(result))")
        #expect(result.ir != nil)
    }

    @Test("self im Menue verweist auf das Element, an dem das Menue haengt")
    func selfIsValidInMenuAndActions() {
        let result = LoaderHarness.load(["/config/shell.kdl": """
        panel "dock" {
            button {
                menu {
                    item "Toggle" checked="{self.pressed}" {
                        system.hide-apps keep-frontmost="{self.hover}"
                    }
                }
            }
        }
        """])
        #expect(result.diagnostics.isEmpty, "\(Self.messages(result))")
        #expect(result.ir != nil)
    }
}
