
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
    fatalError("run this from the package root")
}
let markSVG = root.appendingPathComponent("Support/ApolloMark.svg")
let temp = FileManager.default.temporaryDirectory.appendingPathComponent("apollo-mark-\(UUID().uuidString).png")
defer { try? FileManager.default.removeItem(at: temp) }

func rsvg(_ args: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["rsvg-convert"] + args
    try! process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("rsvg-convert failed; is librsvg installed?") }
}
rsvg(["-w", "2048", "-h", "2048", markSVG.path, "-o", temp.path])

let markFull = NSBitmapImageRep(data: try! Data(contentsOf: temp))!.cgImage!
let (mw, mh) = (markFull.width, markFull.height)
let bytesPerRow = mw * 4
var pixels = [UInt8](repeating: 0, count: bytesPerRow * mh)
let scan = CGContext(data: &pixels, width: mw, height: mh, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
scan.draw(markFull, in: CGRect(x: 0, y: 0, width: mw, height: mh))
var minX = mw, minY = mh, maxX = 0, maxY = 0
for y in 0..<mh {
    for x in 0..<mw where pixels[y * bytesPerRow + x * 4 + 3] > 8 {
        if x < minX { minX = x }; if x > maxX { maxX = x }
        if y < minY { minY = y }; if y > maxY { maxY = y }
    }
}
let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
let mark = markFull.cropping(to: cropRect)!
let iw = CGFloat(mark.width), ih = CGFloat(mark.height)

let canvas: CGFloat = 1024
let body = CGRect(x: 76, y: 76, width: 872, height: 872)

func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(gray: v, alpha: a) }

func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2, steps = 1440
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

func render(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    let shape = squircle(in: body)
    ctx.addPath(shape)
    ctx.setFillColor(gray(1))
    ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(gray(0, 0.06))
    ctx.setLineWidth(2)
    ctx.strokePath()
    ctx.restoreGState()
    let targetW = body.width * 0.62
    let targetH = targetW * ih / iw
    ctx.draw(mark, in: CGRect(x: body.midX - targetW / 2, y: body.midY - targetH / 2,
                              width: targetW, height: targetH))
    return ctx.makeImage()!
}

func png(_ image: CGImage) -> Data {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
var cache: [Int: CGImage] = [:]
func image(_ size: Int) -> CGImage { cache[size] ?? { let i = render(size: size); cache[size] = i; return i }() }
for (name, size) in entries {
    try! png(image(size)).write(to: iconset.appendingPathComponent("\(name).png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Support/AppIcon.icns").path]
try! iconutil.run(); iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)

try! png(image(512)).write(to: root.appendingPathComponent("docs/images/icon.png"))
try! png(render(size: 180)).write(to: root.appendingPathComponent("docs/apple-touch-icon.png"))

print("wrote Support/AppIcon.icns, docs/images/icon.png, docs/apple-touch-icon.png")
