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
