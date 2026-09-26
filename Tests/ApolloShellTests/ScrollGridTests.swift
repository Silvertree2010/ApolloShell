import Testing
import AppKit
@testable import ApolloShell

@MainActor
@Suite("scroll mit grid")
struct ScrollGridTests {
    let red: (RGBA) -> Bool = { $0.r > 200 && $0.g < 60 && $0.b < 60 }

    @Test("Ein grid im scroll mit flex-grow ist sichtbar wie im Marketplace")
    func gridInScrollIsVisible() throws {
        let kdl = "panel \"p\" anchor=\"left\" { column class=\"c\" { scroll class=\"s\" axis=\"vertical\" { grid class=\"g\" { stack class=\"box\"; stack class=\"box\"; stack class=\"box\"; stack class=\"box\" } } } }"
        let css = "#p { width: 300px; height: 300px; } .c { width: 300px; height: 300px; } .s { flex-grow: 1; } .g { padding: 16px; gap: 16px; grid-template-columns: repeat(3, 1fr); } .box { height: 40px; background: rgb(255 0 0); }"
        let bounds = try RenderProbe.render(kdl, css: css).bounds(where: red)
        #expect((bounds?.height ?? 0) >= 80)
    }

    @Test("axis both: breiter Inhalt beginnt links statt in der Mitte abgeschnitten")
    func bothAxes() throws {
        let css = "#p { width: 100px; height: 40px; align-items: start; } .s { width: 100px; height: 40px; } .r { width: 300px; height: 80px; } .a { width: 100px; height: 80px; background: rgb(255 0 0); } .b { width: 100px; height: 80px; background: rgb(0 255 0); } .d { width: 100px; height: 80px; background: rgb(0 0 255); }"
        func shot(_ axis: String) throws -> Snapshot {
            try RenderProbe.render("panel \"p\" anchor=\"left\" { scroll class=\"s\" axis=\"\(axis)\" { row class=\"r\" { stack class=\"a\"; stack class=\"b\"; stack class=\"d\" } } }", css: css)
        }
        let both = try shot("both")
        #expect(both.pixel(50, 20).near(.red, tolerance: 30))
        #expect(both.pixel(50, 20) != (try shot("vertical")).pixel(50, 20))
    }

    @Test("Ein grid mit each im scroll ist sichtbar")
    func eachGridInScroll() throws {
        let kdl = """
        var items type="list" {
            - "a"
            - "b"
            - "c"
            - "d"
        }
        panel "p" anchor="left" {
            column class="c" {
                scroll class="s" axis="vertical" {
                    grid class="g" {
                        each item in="{var.items}" key="{item}" {
                            column class="card" { stack class="box" }
                        }
                    }
                }
            }
        }
        """
        let css = "#p { width: 300px; height: 300px; } .c { width: 300px; height: 300px; } .s { flex-grow: 1; } .g { padding: 16px; gap: 16px; grid-template-columns: repeat(3, 1fr); } .card { gap: 8px; } .box { height: 40px; background: rgb(255 0 0); }"
        let bounds = try RenderProbe.render(kdl, css: css).bounds(where: red)
        #expect((bounds?.height ?? 0) >= 80)
    }

    @Test("Marketplace-Aufbau: Kopf, wachsender Körper, scroll mit grid aus theme-preview")
    func marketplaceShape() throws {
        let kdl = """
        var items type="list" {
            - "a"
            - "b"
            - "c"
            - "d"
        }
        panel "p" anchor="left" {
            stack class="m" {
                column class="main" {
                    row class="head" { text "Marketplace" }
                    column class="body" {
                        scroll class="s" axis="vertical" {
                            grid class="g" {
                                each item in="{var.items}" key="{item}" {
                                    column class="card" {
                                        button class="pv" { theme-preview theme="{item}" }
                                        row class="foot" { text "{item}" class="name" }
                                    }
                                }
                            }
                        }
                    }
                    row class="bottom" { text "Done" }
                }
            }
        }
        """
        let css = "#p { width: 780px; height: 620px; } .main { width: 100%; height: 100%; } .body { flex-grow: 1; } .s { flex-grow: 1; } .g { padding: 16px; gap: 16px; grid-template-columns: repeat(3, 1fr); } .card { gap: 8px; } .foot { background: rgb(255 0 0); height: 20px; } .m { width: 100%; height: 100%; } .s { justify-content: start; }"
        let bounds = try #require(try RenderProbe.render(kdl, css: css).bounds(where: red))
        #expect(bounds.height >= 150)
        #expect(bounds.minY < 250)
    }
}
