import Testing
import AppKit
@testable import ApolloShell

@MainActor
@Suite("image fit=fill bleibt in seinem Rahmen")
struct ImageFillTests {
    static func png(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    @Test("Ein 16:9-Bild mit fit=fill in 98×98 füllt genau 98×98 und ragt nicht hinaus")
    func wideImageStaysInFrame() throws {
        let kdl = """
        panel "p" anchor="left" {
            column class="c" {
                row class="strip" {
                    stack class="cover" { image "art.png" fit="fill" class="art" }
                    text "Title"
                }
            }
        }
        """
        let css = "#p { width: 400px; height: 300px; } .c { width: 400px; height: 300px; } .strip { padding: 16px; gap: 16px; align-items: center; } .cover { width: 98px; height: 98px; } .art { width: 98px; height: 98px; }"
        let red: (RGBA) -> Bool = { $0.r > 200 && $0.g < 60 && $0.b < 60 }
        let bounds = try #require(try RenderProbe.render(kdl, css: css, files: ["art.png": Self.png(width: 1280, height: 720)]).bounds(where: red))
        #expect(abs(bounds.width - 98) <= 1, "\(bounds)")
        #expect(abs(bounds.height - 98) <= 1, "\(bounds)")
    }

    @Test("border-radius schneidet ein Bild rund zu wie in CSS")
    func radiusClipsImage() throws {
        let kdl = """
        panel "p" anchor="left" {
            column class="c" { image "art.png" fit="fill" class="art" }
        }
        """
        let css = "#p { width: 200px; height: 200px; } .c { width: 200px; height: 200px; align-items: start; } .art { width: 144px; height: 144px; border-radius: 9999px; }"
        let shot = try RenderProbe.render(kdl, css: css, files: ["art.png": Self.png(width: 1280, height: 720)])
        let red: (RGBA) -> Bool = { $0.r > 200 && $0.g < 60 && $0.b < 60 }
        let bounds = try #require(shot.bounds(where: red))
        #expect(!red(shot.pixel(bounds.minX + 2, bounds.minY + 2)))
        #expect(red(shot.pixel(bounds.midX, bounds.midY)))
    }
}

@MainActor
@Suite("Flex: wachsendes Kind mit zu breitem Inhalt")
struct FlexOverflowTests {
    @Test("Ein wachsendes Kind mit langem Text bekommt den Restplatz und schneidet ab, statt auf 0 zu fallen")
    func growingChildGetsRemainingSpace() throws {
        let kdl = """
        panel "p" anchor="left" {
            row class="r" {
                stack class="cover"
                column class="info" { text "Committing HEINOUS CRIMES in Payday 2 with a very very long title that does not fit" lines=1 truncate="tail" class="t" }
            }
        }
        """
        let css = "#p { width: 400px; height: 100px; } .r { width: 400px; height: 100px; gap: 20px; align-items: center; } .cover { width: 100px; height: 60px; background: rgb(0 0 255); } .info { flex-grow: 1; background: rgb(255 0 0); } .t { font-size: 20px; }"
        let shot = try RenderProbe.render(kdl, css: css)
        let red: (RGBA) -> Bool = { $0.r > 200 && $0.g < 60 && $0.b < 60 }
        let info = try #require(shot.bounds(where: red))
        #expect(abs(info.minX - 120) <= 1, "\(info)")
        #expect(abs(info.maxX - 400) <= 1, "\(info)")
    }
}

@MainActor
@Suite("Flex: Querachse bei align-items start")
struct FlexCrossClampTests {
    @Test("Ein zu langer Text in einer Spalte mit align-items start wird auf die Spaltenbreite gekürzt")
    func textClampsToColumn() throws {
        let kdl = """
        panel "p" anchor="left" {
            column class="c" {
                text "Committing HEINOUS CRIMES in Payday 2 with a very very long title that does not fit" lines=1 truncate="tail" class="t"
            }
        }
        """
        let css = "#p { width: 200px; height: 60px; } .c { width: 200px; height: 60px; align-items: start; } .t { font-size: 20px; background: rgb(255 0 0); }"
        let shot = try RenderProbe.render(kdl, css: css)
        let red: (RGBA) -> Bool = { $0.r > 200 && $0.g < 60 && $0.b < 60 }
        let bounds = try #require(shot.bounds(where: red))
        #expect(bounds.minX >= 0 && bounds.maxX <= 200, "\(bounds)")
        #expect(bounds.width >= 190, "\(bounds)")
    }
}

@MainActor
@Suite("stack: Kinder mit Prozentbreite")
struct StackPercentTests {
    @Test("Eine Zeile mit width 100% in einem gestreckten Knopf füllt die ganze Breite")
    func percentRowFillsStretchedButton() throws {
        let kdl = "panel \"p\" anchor=\"left\" { column class=\"page\" { column class=\"group\" { text \"Style\"; button class=\"b\" { row class=\"button-content\" { icon \"star\"; text \"Wallpaper\"; spacer; icon \"star\" } } } } }"
        let css = "#p { width: 400px; height: 200px; } .page { width: 400px; padding: 20px; } .group { gap: 8px; padding: 12px; } .b { align-self: stretch; padding: 4px 6px; } .button-content { width: 100%; gap: 12px; align-items: center; background: rgb(255 0 0); }"
        let red: (RGBA) -> Bool = { $0.r > 200 && $0.g < 60 && $0.b < 60 }
        let bounds = try #require(try RenderProbe.render(kdl, css: css).bounds(where: red))
        #expect(abs(bounds.width - 324) <= 1, "\(bounds)")
    }
}
