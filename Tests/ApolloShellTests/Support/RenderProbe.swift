import Testing
import Foundation
import AppKit
import ApolloBase
import ApolloProviders
import ApolloRuntime
@testable import ApolloShell

struct RGBA: Equatable, CustomStringConvertible {
    var r: Int, g: Int, b: Int, a: Int

    func near(_ other: RGBA, tolerance: Int = 12) -> Bool {
        abs(r - other.r) <= tolerance && abs(g - other.g) <= tolerance && abs(b - other.b) <= tolerance
    }

    var description: String { "(\(r),\(g),\(b),\(a))" }

    static let white = RGBA(r: 255, g: 255, b: 255, a: 255)
    static let black = RGBA(r: 0, g: 0, b: 0, a: 255)
    static let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    static let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
    static let green = RGBA(r: 0, g: 255, b: 0, a: 255)
}

struct Snapshot {
    let rep: NSBitmapImageRep
    let scale: CGFloat

    var size: CGSize { CGSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale) }

    func pixel(_ x: CGFloat, _ y: CGFloat) -> RGBA {
        let px = min(rep.pixelsWide - 1, max(0, Int((x * scale).rounded(.down))))
        let py = min(rep.pixelsHigh - 1, max(0, Int((y * scale).rounded(.down))))
        guard let data = rep.bitmapData, rep.bitsPerSample == 8 else { return RGBA(r: -1, g: -1, b: -1, a: -1) }
        let base = py * rep.bytesPerRow + px * rep.samplesPerPixel
        let alpha = rep.samplesPerPixel > 3 ? Int(data[base + 3]) : 255
        return RGBA(r: Int(data[base]), g: Int(data[base + 1]), b: Int(data[base + 2]), a: alpha)
    }

    func bounds(where test: (RGBA) -> Bool) -> CGRect? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where test(pixel(CGFloat(x) / scale, CGFloat(y) / scale)) {
                minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    func count(where test: (RGBA) -> Bool) -> Int {
        var total = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where test(pixel(CGFloat(x) / scale, CGFloat(y) / scale)) { total += 1 }
        }
        return total
    }

    func ink(background: RGBA = .white) -> CGRect? {
        bounds { !$0.near(background, tolerance: 24) }
    }
}

@MainActor
enum RenderProbe {
    static var dumped = 0

    static func folder(_ files: [String: Data]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("render-probe-\(UUID().uuidString)")
        for (name, data) in files {
            let target = url.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        }
        return url
    }

    static func session(_ kdl: String, css: String = "", files: [String: Data] = [:], fixture: String? = nil, dark: Bool = false,
                        scale: CGFloat = 1) throws -> (RenderSession, [Diagnostic]) {
        var all = files
        all["shell.kdl"] = Data(("style \"style.css\"\n" + kdl).utf8)
        all["style.css"] = Data(css.utf8)
        let config = try folder(all)
        let fixtureData = fixture.map { ProviderFixture.parse($0, file: "probe-fixture.kdl") }
            ?? ProviderFixture.load(PackageResources.root.appendingPathComponent("Resources/render/fixture.kdl"))
        var diagnostics: [Diagnostic] = []
        let session = try RenderSession(config: config, resources: PackageResources.root.appendingPathComponent("Resources"),
                                        fixture: fixtureData, fixtureRoot: config, dark: dark, scale: scale) { diagnostics += $0 }
        return (session, diagnostics)
    }

    static func render(_ kdl: String, css: String = "", files: [String: Data] = [:], fixture: String? = nil, dark: Bool = false,
                       surface: String? = nil, scale: CGFloat = 1) throws -> Snapshot {
        let (session, diagnostics) = try self.session(kdl, css: css, files: files, fixture: fixture, dark: dark, scale: scale)
        let problems = (diagnostics + session.context.styles.diagnostics).filter { $0.severity != .note }
        #expect(problems.isEmpty, "\(problems.map(\.message))")
        let target = try #require(surface.flatMap(session.surface) ?? session.surfaces.first)
        let data = try session.capture(target, name: target.id)
        if let dump = ProcessInfo.processInfo.environment["APOLLO_PROBE_DUMP"] {
            dumped += 1
            try? data.write(to: URL(fileURLWithPath: dump).appendingPathComponent("probe-\(dumped).png"))
        }
        let later = session.context.styles.diagnostics.filter { $0.severity != .note }
        #expect(later.isEmpty, "\(later.map(\.message))")
        return Snapshot(rep: try #require(NSBitmapImageRep(data: data)), scale: scale)
    }
}
