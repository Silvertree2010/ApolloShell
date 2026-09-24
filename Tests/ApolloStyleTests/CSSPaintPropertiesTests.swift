import ApolloShellCore
import Foundation
import Testing
@testable import ApolloStyle

private let red = CSSColor.rgba(red: 1, green: 0, blue: 0, alpha: 1)
private let blue = CSSColor.rgba(red: 0, green: 0, blue: 1, alpha: 1)
private let black = CSSColor.rgba(red: 0, green: 0, blue: 0, alpha: 1)
private let white = CSSColor.rgba(red: 1, green: 1, blue: 1, alpha: 1)

@Suite("CSS: Farbe, Fläche, Schichten")
struct CSSPaintPropertiesTests {
    private let pixel = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private func parse(_ property: String, _ text: String, root: URL? = nil, limits: ThemeLimits = .standard) throws -> CSSValue {
        try CSSPropertyRegistry.parse(property, text, context: CSSParseContext(assetRoot: root, limits: limits))
    }

    @Test("Schichten aus der Spec",
          arguments: [
              ("material(regular)", [BackgroundLayer.material(.regular)]),
              ("glass(regular)", [.glass(.regular, tint: nil)]),
              ("glass(regular, rgb(from -apple-system-window-background r g b / 0.7))",
               [.glass(.regular, tint: .system(name: "-apple-system-window-background", alpha: 0.7))]),
              ("glass(clear), -apple-system-window-background",
               [.glass(.clear, tint: nil), .color(.system(name: "-apple-system-window-background", alpha: 1))]),
              ("#ff0000, glass(regular)", [.color(red), .glass(.regular, tint: nil)]),
              ("rgb(from -apple-system-label r g b / 0.14)", [.color(.system(name: "-apple-system-label", alpha: 0.14))]),
              ("none", []),
              ("linear-gradient(90deg, #000000 0%, #ffffff 100%)",
               [.gradient(LinearGradient(angleDegrees: 90, stops: [GradientStop(color: black, position: 0), GradientStop(color: white, position: 1)]))]),
              ("linear-gradient(to right, red, -apple-system-blue 80%, blue)",
               [.gradient(LinearGradient(angleDegrees: 90, stops: [
                   GradientStop(color: red, position: 0),
                   GradientStop(color: .system(name: "-apple-system-blue", alpha: 1), position: 0.8),
                   GradientStop(color: blue, position: 1),
               ]))]),
              ("linear-gradient(red, blue, red)",
               [.gradient(LinearGradient(angleDegrees: 180, stops: [
                   GradientStop(color: red, position: 0), GradientStop(color: blue, position: 0.5), GradientStop(color: red, position: 1),
               ]))]),
              ("linear-gradient(to top left, red 50%, blue 20%)",
               [.gradient(LinearGradient(angleDegrees: 315, stops: [
                   GradientStop(color: red, position: 0.5), GradientStop(color: blue, position: 0.5),
               ]))]),
          ])
    func layers(text: String, expected: [BackgroundLayer]) throws {
        #expect(try parse("background", text) == .layers(expected))
    }

    @Test("jede Materialstärke", arguments: ["ultra-thin", "thin", "regular", "thick", "ultra-thick", "bar"])
    func materials(name: String) throws {
        #expect(try parse("background", "material(\(name))") == .layers([.material(MaterialThickness(rawValue: name)!)]))
    }

    @Test("ungültige Schichten",
          arguments: [
              "radial-gradient(red, blue)", "linear-gradient(red)",
              "linear-gradient(red, red, red, red, red, red, red, red, red)",
              "linear-gradient(45px, red, blue)", "glass(thick)", "glass(regular, red, blue)", "material(huge)",
              "red blue", "red,", "url(\"a.png\")",
          ])
    func invalidLayers(text: String) {
        #expect(throws: CSSValueError.self) { try parse("background", text) }
    }

    @Test("Rahmen, Radius, Deckkraft, Form, Ränder",
          arguments: [
              ("border", "1px solid red", CSSValue.border(width: 1, dashed: false, color: red)),
              ("border", "2px dashed", .border(width: 2, dashed: true, color: .currentColor)),
              ("border", "red 1px", .border(width: 1, dashed: false, color: red)),
              ("border", "none", .border(width: 0, dashed: false, color: .currentColor)),
              ("border-width", "2px", .length(CSSLength(2, .points))),
              ("border-color", "-apple-system-separator", .color(.system(name: "-apple-system-separator", alpha: 1))),
              ("border-radius", "9px", .lengths(Array(repeating: CSSLength(9, .points), count: 4))),
              ("border-radius", "50%", .lengths(Array(repeating: CSSLength(50, .percent), count: 4))),
              ("border-radius", "1px 2px", .lengths([CSSLength(1, .points), CSSLength(2, .points), CSSLength(1, .points), CSSLength(2, .points)])),
              ("opacity", "0.5", .number(0.5)),
              ("opacity", "40%", .number(0.4)),
              ("opacity", "1.4", .number(1)),
              ("-apollo-corner-shape", "circular", .keyword("circular")),
              ("-apollo-fade-edges", "4%", .length(CSSLength(4, .percent))),
              ("-apollo-join-radius", "14px", .length(CSSLength(14, .points))),
              ("color", "-apple-system-label", .color(.system(name: "-apple-system-label", alpha: 1))),
              ("accent-color", "#0000ff", .color(blue)),
              ("background-color", "transparent", .color(.rgba(red: 0, green: 0, blue: 0, alpha: 0))),
          ])
    func paint(property: String, text: String, expected: CSSValue) throws {
        #expect(try parse(property, text) == expected)
    }

    @Test("ungültige Rahmen und Formen",
          arguments: [("border", "solid red"), ("border", "1px 2px solid"), ("border", "1px solid dotted"),
                      ("border-radius", "-1px"), ("-apollo-corner-shape", "square"), ("opacity", "1px")])
    func invalidPaint(property: String, text: String) {
        #expect(throws: CSSValueError.self) { try parse(property, text) }
    }

    @Test("Schatten und Filter")
    func shadowsAndFilters() throws {
        let shadow = Shadow(x: 0, y: 1, blur: 3, spread: 0, color: .rgba(red: 0, green: 0, blue: 0, alpha: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.25).alpha))
        #expect(try parse("box-shadow", "0 1px 3px rgb(0 0 0 / 25%)") == .shadows([shadow]))
        #expect(try parse("box-shadow", "0 0 2px 1px red, 1px 1px blue") == .shadows([
            Shadow(x: 0, y: 0, blur: 2, spread: 1, color: red),
            Shadow(x: 1, y: 1, blur: 0, spread: 0, color: blue),
        ]))
        #expect(try parse("box-shadow", "none") == .shadows([]))
        #expect(try parse("filter", "drop-shadow(0 1px 1px rgb(from -apple-system-label r g b / 0.3)) blur(12px)") == .filters([
            .dropShadow(Shadow(x: 0, y: 1, blur: 1, spread: 0, color: .system(name: "-apple-system-label", alpha: 0.3))),
            .blur(12),
        ]))
        #expect(try parse("filter", "none") == .filters([]))
        #expect(throws: CSSValueError.self) { try parse("box-shadow", "inset 0 1px red") }
        #expect(throws: CSSValueError.self) { try parse("box-shadow", "1px red") }
        #expect(throws: CSSValueError.self) { try parse("box-shadow", "0 1px -2px red") }
        #expect(throws: CSSValueError.self) { try parse("filter", "invert(1)") }
        #expect(throws: CSSValueError.self) { try parse("filter", "drop-shadow(1px 1px 1px 1px red)") }
    }

    @Test("accent-color erbt und hat die Systemfarbe als Vorgabe, color erbt, background nicht")
    func schemas() {
        #expect(CSSPropertyRegistry.builtin["accent-color"]?.inherits == true)
        #expect(CSSPropertyRegistry.builtin["accent-color"]?.initial == .color(.system(name: "-apple-system-control-accent", alpha: 1)))
        #expect(CSSPropertyRegistry.builtin["color"]?.inherits == true)
        #expect(CSSPropertyRegistry.builtin["background"]?.inherits == false)
        #expect(CSSPropertyRegistry.builtin["-apollo-corner-shape"]?.initial == .keyword("continuous"))
    }

    @Test("url() folgt den Regeln für Theme-Bilder")
    func imageSecurity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("apolloshell-style-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let secret = root.appendingPathComponent("secret.png")
        try pixel.write(to: secret)
        let folder = root.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try pixel.write(to: folder.appendingPathComponent("ok.png"))
        try Data("nur Text".utf8).write(to: folder.appendingPathComponent("notizen.txt"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.png"), withDestinationURL: secret)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("hinaus"), withDestinationURL: root)

        let attacks: [(String, ThemeAssetRejection)] = [
            ("../secret.png", .escapesFolder),
            ("../../secret.png", .escapesFolder),
            ("sub/../../secret.png", .escapesFolder),
            ("%2e%2e/secret.png", .escapesFolder),
            ("..%2Fsecret.png", .escapesFolder),
            ("/etc/hosts.png", .escapesFolder),
            ("~/Pictures/x.png", .escapesFolder),
            ("https://example.com/x.png", .notALocalPath),
            ("http://example.com/x.png", .notALocalPath),
            ("file:///etc/hosts.png", .notALocalPath),
            ("data:image/png;base64,AAAA", .notALocalPath),
            ("link.png", .outsideThemeFolder),
            ("hinaus/secret.png", .outsideThemeFolder),
            ("notizen.txt", .unsupportedType("txt")),
            ("fehlt.png", .missing),
        ]
        for (reference, expected) in attacks {
            do {
                _ = try parse("background", "url(\"\(reference)\")", root: folder)
                Issue.record("\(reference) hätte abgelehnt werden müssen")
            } catch let error as CSSValueError {
                #expect(error.assetRejection == expected, "\(reference): \(error.message)")
            }
        }

        let quoted = try parse("background", "url(\"ok.png\"), red", root: folder)
        guard case let .layers(layers) = quoted, case let .image(path)? = layers.first else {
            Issue.record("kein Bild: \(quoted)")
            return
        }
        #expect(path.hasSuffix("/config/ok.png"))
        #expect(layers.count == 2)

        let unquoted = try parse("background", "url(ok.png)", root: folder)
        #expect(unquoted == .layers([.image(path: path)]))

        do {
            _ = try parse("background", "url(ok.png)", root: folder, limits: ThemeLimits(maxAssetBytes: 4))
            Issue.record("zu grosses Bild wurde angenommen")
        } catch let error as CSSValueError {
            #expect(error.assetRejection == .tooLarge(bytes: pixel.count, limit: 4))
        }
    }
}
