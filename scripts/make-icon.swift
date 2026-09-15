// Draws the ApolloShell app icon and turns it into Support/AppIcon.icns.
//
// Original artwork, drawn entirely in code (no fonts, no bitmaps, no logos):
// a warm planet with a tilted orbit ring and a small moon on a night-blue
// squircle, in the style of macOS 26 app icons (1024 canvas, 824 pt body,
// continuous corners, soft drop shadow, a faint glass sheen on top).
//
// Usage (from the repository root, Command Line Tools are enough):
//   SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift scripts/make-icon.swift
// Writes Support/AppIcon.icns and docs/images/icon.png (512 px preview).
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
    FileHandle.standardError.write(Data("run from the repository root\n".utf8))
    exit(2)
}

// MARK: - Geometry (1024 x 1024 canvas, y grows upwards like Core Graphics)

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let planetCenter = CGPoint(x: 500, y: 520)
let planetRadius: CGFloat = 196
let ringTilt: CGFloat = -0.36 // radians, counter-clockwise is positive
let ringRadii = CGSize(width: 330, height: 96)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Superellipse (n = 5) - close to Apple's continuous-corner squircle.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
               colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

/// The orbit ring as an ellipse around the planet, tilted.
func ringPath() -> CGPath {
    var transform = CGAffineTransform(translationX: planetCenter.x, y: planetCenter.y).rotated(by: ringTilt)
    return CGPath(ellipseIn: CGRect(x: -ringRadii.width, y: -ringRadii.height,
                                    width: ringRadii.width * 2, height: ringRadii.height * 2),
                  transform: &transform)
}

/// Half-plane below the ring's long axis (the part of the ring in front of the planet).
func frontHalf() -> CGPath {
    var transform = CGAffineTransform(translationX: planetCenter.x, y: planetCenter.y).rotated(by: ringTilt)
    return CGPath(rect: CGRect(x: -600, y: -600, width: 1200, height: 600), transform: &transform)
}

func drawRing(_ ctx: CGContext, detail: Bool) {
    ctx.saveGState()
    ctx.addPath(ringPath())
    ctx.setLineWidth(detail ? 22 : 30)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, color(0xB9F3FF)), (0.5, color(0xFFFFFF)), (1, color(0x7FB7FF))]),
                           start: CGPoint(x: 150, y: 400), end: CGPoint(x: 870, y: 640), options: [])
    ctx.restoreGState()
}

func draw(size: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    // Fine detail only where it is visible.
    let detail = size >= 64
    let shape = squircle(in: body)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x000000, 0.38))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x151B3D))
    ctx.fillPath()
    ctx.restoreGState()

    // Everything else lives inside the body.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Night sky: indigo top-left to deep navy bottom-right, with a teal glow low right.
    ctx.drawLinearGradient(gradient([(0, color(0x3C4FC4)), (0.55, color(0x1A2266)), (1, color(0x0A0F2E))]),
                           start: CGPoint(x: 180, y: 930), end: CGPoint(x: 860, y: 90), options: [])
    ctx.drawRadialGradient(gradient([(0, color(0x2BC4C9, 0.45)), (1, color(0x2BC4C9, 0))]),
                           startCenter: CGPoint(x: 820, y: 200), startRadius: 0,
                           endCenter: CGPoint(x: 820, y: 200), endRadius: 420, options: [])

    if detail {
        // A few stars, fixed positions.
        let stars: [(CGFloat, CGFloat, CGFloat)] = [
            (230, 820, 7), (330, 760, 4), (760, 830, 6), (842, 720, 4), (205, 300, 5),
            (300, 210, 4), (690, 250, 5), (860, 470, 4), (170, 590, 4), (600, 870, 4),
        ]
        for (x, y, r) in stars {
            ctx.setFillColor(color(0xFFFFFF, 0.75))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
    }

    // Back half of the ring, dimmed - it passes behind the planet.
    ctx.saveGState()
    ctx.setAlpha(0.55)
    drawRing(ctx, detail: detail)
    ctx.restoreGState()

    // Planet: warm sphere lit from the upper left, with a soft halo.
    ctx.drawRadialGradient(gradient([(0, color(0xFF9A5C, 0.35)), (1, color(0xFF9A5C, 0))]),
                           startCenter: planetCenter, startRadius: planetRadius * 0.9,
                           endCenter: planetCenter, endRadius: planetRadius * 1.55, options: [])
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: planetCenter.x - planetRadius, y: planetCenter.y - planetRadius,
                              width: planetRadius * 2, height: planetRadius * 2))
    ctx.clip()
    let light = CGPoint(x: planetCenter.x - planetRadius * 0.42, y: planetCenter.y + planetRadius * 0.46)
    ctx.drawRadialGradient(gradient([(0, color(0xFFF1C9)), (0.35, color(0xFFB36B)),
                                     (0.72, color(0xE0584A)), (1, color(0x6E1F5C))]),
                           startCenter: light, startRadius: 0,
                           endCenter: planetCenter, endRadius: planetRadius * 1.05,
                           options: [.drawsAfterEndLocation])
    if detail {
        // Two faint bands across the planet, following the ring's tilt.
        ctx.saveGState()
        ctx.translateBy(x: planetCenter.x, y: planetCenter.y)
        ctx.rotate(by: ringTilt)
        for (offset, height, alpha) in [(CGFloat(58), CGFloat(26), CGFloat(0.14)), (-40, 18, 0.10)] {
            ctx.setFillColor(color(0xFFFFFF, alpha))
            ctx.fillEllipse(in: CGRect(x: -planetRadius * 1.2, y: offset - height / 2,
                                       width: planetRadius * 2.4, height: height))
        }
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // Front half of the ring, full strength.
    ctx.saveGState()
    ctx.addPath(frontHalf())
    ctx.clip()
    drawRing(ctx, detail: detail)
    ctx.restoreGState()

    // Moon on the ring, front right.
    let moonAngle: CGFloat = -0.55
    let moonLocal = CGPoint(x: ringRadii.width * cos(moonAngle), y: ringRadii.height * sin(moonAngle))
    let moon = moonLocal.applying(CGAffineTransform(rotationAngle: ringTilt))
    let moonCenter = CGPoint(x: planetCenter.x + moon.x, y: planetCenter.y + moon.y)
    let moonRadius: CGFloat = 40
    ctx.drawRadialGradient(gradient([(0, color(0xBDEBFF, 0.55)), (1, color(0xBDEBFF, 0))]),
                           startCenter: moonCenter, startRadius: moonRadius * 0.8,
                           endCenter: moonCenter, endRadius: moonRadius * 2.2, options: [])
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: moonCenter.x - moonRadius, y: moonCenter.y - moonRadius,
                              width: moonRadius * 2, height: moonRadius * 2))
    ctx.clip()
    ctx.drawRadialGradient(gradient([(0, color(0xFFFFFF)), (1, color(0x8CC8F0))]),
                           startCenter: CGPoint(x: moonCenter.x - 14, y: moonCenter.y + 16), startRadius: 0,
                           endCenter: moonCenter, endRadius: moonRadius, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Glass sheen over the top half.
    ctx.drawLinearGradient(gradient([(0, color(0xFFFFFF, 0.20)), (0.45, color(0xFFFFFF, 0.04)), (0.5, color(0xFFFFFF, 0))]),
                           start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
    ctx.restoreGState()

    // Thin light edge, like the rim of macOS 26 icons.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setLineWidth(3)
    ctx.setStrokeColor(color(0xFFFFFF, 0.22))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url)
}

// MARK: - Iconset -> icns

let work = FileManager.default.temporaryDirectory.appendingPathComponent("apolloshell-icon-\(getpid())")
let iconset = work.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: work)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

for points in [16, 32, 128, 256, 512] {
    try writePNG(draw(size: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(draw(size: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let icns = root.appendingPathComponent("Support/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

let preview = root.appendingPathComponent("docs/images/icon.png")
try FileManager.default.createDirectory(at: preview.deletingLastPathComponent(), withIntermediateDirectories: true)
try writePNG(draw(size: 512), to: preview)
print("wrote \(icns.path)")
print("wrote \(preview.path)")
