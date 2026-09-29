import AppKit
import SwiftUI
import Testing
@testable import ApolloShell
@testable import ApolloShellCore
import ApolloStyle
import ApolloRuntime

@MainActor
@Suite("Fusion: Haut über die Oberflächen einer fuse-group")
struct FusionTests {
    static let shell = """
    panel "bar" anchor="left" fuse-group="shell" fuse-fill=#true { row {} }
    popup "drawer" anchor="bottom-right" fuse-group="shell" { row {} }
    panel "alone" anchor="top" { row {} }
    """
    static let css = "#bar { width: 40px; height: 100%; background: red; } #drawer { width: 200px; height: 100px; background: blue; border-radius: 20px; } #alone { height: 20px; background: green; }"

    func fixture(_ tokens: [String: String] = [:]) throws -> HostFixture {
        let fixture = try HostFixture(Self.shell, css: Self.css)
        if !tokens.isEmpty {
            let sheets = fixture.ir.map { StyleSheets.load($0).0 } ?? []
            let environment = StyleEnvironment(appearance: .light, reduceMotion: false, reduceTransparency: false, tokens: TokenEnvironment(values: tokens))
            fixture.host.restyle(RenderContext(styles: StyleResolver(sheets: sheets, environment: environment), icons: FixtureAppIcons(), trigger: { _, _, _ in }))
        }
        return fixture
    }

    @Test("Vorgabe rounded: eine Haut je Bildschirm, Gruppenmitglieder ohne eigenen Hintergrund, Füllung vom fuse-fill")
    func skinAndPainter() throws {
        let fixture = try fixture()
        let host = fixture.host
        #expect(host.fusion.isOn)
        #expect(fixture.factory.auxiliary.count == 1)
        #expect(fixture.factory.auxiliary.first?.level == FusionCoordinator.calmLevel)
        let bar = try #require(fixture.assembly.runtime.surface("bar", screenKey: HostFixture.screen.key))
        let alone = try #require(fixture.assembly.runtime.surface("alone", screenKey: HostFixture.screen.key))
        let style = try #require(host.context).styles.resolve(surface: bar)
        #expect(SurfaceBackground.resolve(host.painter, surface: bar, style: style).style["background"] == nil)
        let aloneStyle = try #require(host.context).styles.resolve(surface: alone)
        #expect(SurfaceBackground.resolve(host.painter, surface: alone, style: aloneStyle).style["background"] != nil)
        #expect(host.fusionFill(HostFixture.screen.key)["background"] != nil)
        let pieces = host.fusion.pieces(on: HostFixture.screen.key)
        #expect(pieces.map(\.id) == ["bar@" + HostFixture.screen.key])
        #expect(abs((pieces.first?.piece.rect.width ?? 0) - 40) < 0.5)
        #expect(host.fusion.models[HostFixture.screen.key]?.pieces.count == 1)
    }

    @Test("Klassenwechsel am fuse-fill-Mitglied erneuert die Füllung der Haut")
    func fillFollowsClass() throws {
        let fixture = try HostFixture("""
        var red #false
        panel "bar" anchor="left" fuse-group="shell" fuse-fill=#true class="{var.red ? 'red' : ''}" { row {} }
        """, css: "#bar { width: 40px; height: 100%; background: blue; } #bar.red { background: red; }")
        let screen = HostFixture.screen.key
        let before = try #require(fixture.host.fusion.models[screen]?.fill["background"])
        fixture.assembly.actions.vars.set("red", .bool(true))
        fixture.flush()
        for work in fixture.deferred { work() }
        fixture.deferred.removeAll()
        #expect(fixture.host.fusion.models[screen]?.fill["background"] != before)
    }

    @Test("separate: keine Haut, kein Maler, Hintergründe wie ohne Fusion")
    func separate() throws {
        let fixture = try fixture(["--apollo-fusion-style": "separate"])
        #expect(!fixture.host.fusion.isOn)
        #expect(fixture.host.painter == nil)
        #expect(fixture.factory.auxiliary.allSatisfy { $0.closed })
    }

    @Test("Öffnen wächst aus der Kante mit Federn, Schliessen schrumpft zurück, danach Ruhe ohne Ticker")
    func jellyOpenClose() throws {
        let fixture = try fixture()
        let host = fixture.host
        let screen = HostFixture.screen.key
        var tickers: [ManualTicker] = []
        host.fusion.makeTicker = { _ in
            let ticker = ManualTicker()
            tickers.append(ticker)
            return ticker
        }
        let key = "drawer@" + screen
        host.fusion.frameChanged(key, CGRect(x: 1240, y: 0, width: 200, height: 100))
        let first = try #require(host.fusion.pieces(on: screen).first { $0.id == key })
        #expect(first.piece.rect.height < 1)
        #expect(tickers.count == 1)
        for _ in 0..<240 { host.fusion.tick(screen, by: 1.0 / 120) }
        let open = try #require(host.fusion.pieces(on: screen).first { $0.id == key })
        #expect(abs(open.piece.rect.height - 100) < 0.5)
        #expect(open.piece.radius == 20)
        host.fusion.frameChanged(key, .null)
        for _ in 0..<240 { host.fusion.tick(screen, by: 1.0 / 120) }
        #expect(host.fusion.pieces(on: screen).allSatisfy { $0.id != key })
    }

    @Test("Hohlkehlen-Radius und Bildschirmrand aus den Tokens, jelly off springt sofort")
    func tokens() {
        let settings = FusionSettings(tokens: TokenEnvironment(values: ["--apollo-fusion-style": "square", "--apollo-fusion-radius": "30px", "--apollo-fusion-screen-edge": "rounded", "--apollo-jelly": "off"]), reduceMotion: false)
        #expect(settings.shape == FusionShape(style: .square, innerRadius: 30, screenEdge: .rounded))
        #expect(settings.springs == nil)
        #expect(FusionSettings(tokens: .empty, reduceMotion: true).springs == nil)
        #expect(FusionSettings(tokens: .empty, reduceMotion: false).shape == .standard)
        #expect(FusionSettings(tokens: TokenEnvironment(values: ["--apollo-animation-speed": "0"]), reduceMotion: false).springs == nil)
    }

    @Test("jelly: Inhalt erst ab 80 % der Grösse, Schliessen nimmt den Rahmen sofort weg")
    func jellyAnimator() {
        let springs = JellySpringParameters(strength: .subtle, speed: 1)
        let delay = FusionCoordinator.contentDelay(springs)
        #expect(delay > 0.05 && delay < 0.3)
        var field = JellyField(parameters: springs)
        field.set("p", rect: CGRect(x: 0, y: 0, width: 100, height: 100), radius: 0, grow: .minX)
        field.step(max(0, delay - 0.02))
        #expect((field.pieces.first?.piece.rect.width ?? 0) < 80)
        #expect(FusionCoordinator.contentDelay(nil) == 0)
        let animator = JellyAnimator(springs: { springs })
        #expect(animator.fadeDelay(opening: true) == delay)
        let geometry = MotionGeometry(edge: .top, size: CGSize(width: 10, height: 10), topInset: 0, flipped: false)
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(animator.visibleFrame(open: frame, geometry: geometry, progress: animator.progress(at: 0, opening: true)) == frame)
        #expect(animator.visibleFrame(open: frame, geometry: geometry, progress: animator.progress(at: 0, opening: false)).isNull)
    }

    @Test("Nachbar-Impuls: bewegte Kante gibt 20 % an die anliegende Fläche")
    func neighbourPush() {
        var field = JellyField(parameters: JellySpringParameters(strength: .strong, speed: 1))
        field.set("a", rect: CGRect(x: 0, y: 0, width: 40, height: 300), radius: 0, grow: nil)
        field.set("b", rect: CGRect(x: 40, y: 100, width: 100, height: 100), radius: 0, grow: nil)
        field.step(1)
        field.set("a", rect: CGRect(x: 0, y: 0, width: 60, height: 300), radius: 0, grow: nil)
        field.step(1.0 / 60)
        let b = field.pieces.first { $0.id == "b" }?.piece.rect
        #expect((b?.minX ?? 40) > 40)
    }
}
