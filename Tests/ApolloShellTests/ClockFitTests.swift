import Testing
import AppKit
import SwiftUI
import Observation
@testable import ApolloShell

@MainActor
@Suite("Grösse von panels ohne feste Breite")
struct ClockFitTests {
    static let shell = """
    panel "clock" anchor="bottom-right" layer="desktop" click-through=#true {
        row class="clock" {
            row class="time" {
                text "20"
                text ":" class="colon"
                text "36"
            }
            stack class="rule"
            column class="date" {
                text "SEPTEMBER" class="month"
                text "30" class="day"
                text "Wednesday" class="weekday"
            }
        }
    }
    """

    static let css = """
    .clock { padding: 24px; gap: 20px; align-items: center; color: white; filter: drop-shadow(0 0 20px rgb(0 0 0 / 0.7)); }
    .time { font-size: 84px; font-weight: 700; }
    .rule { width: 3px; height: 86px; background: white; }
    .date { gap: 2px; align-items: start; }
    .month { font-size: 16px; letter-spacing: 4px; }
    .day { font-size: 28px; }
    .weekday { font-size: 16px; letter-spacing: 2px; }
    """

    @Test("Die echte Hosting-Ansicht misst die Uhr in ihrer ganzen Breite")
    func realHostingWidth() throws {
        let fixture = try HostFixture(Self.shell, css: Self.css)
        let fake = try #require(fixture.window("clock"))
        let real = AppKitHostWindow(spec: fake.spec, content: try #require(fake.content))
        let fit = real.fittingSize
        #expect(fit.width > 300, "\(fit)")
        #expect(fit.height < 200, "\(fit)")
    }

    @Test("Der Host beobachtet die Grösse nur bei panels ohne feste Breite oder Höhe")
    func watchesOnlyFitting() throws {
        let fixture = try HostFixture("""
        panel "fit" { text "x" }
        panel "fixed" { text "x" }
        """, css: "#fixed { width: 200px; height: 40px; }")
        #expect(try #require(fixture.window("fit")).watching)
        #expect(try #require(fixture.window("fixed")).watching == false)
    }

    @Test("Wächst der Inhalt ohne invalidateIntrinsicContentSize, meldet die beobachtete Hosting-Ansicht die neue Grösse")
    func growthIsReported() async throws {
        let model = GrowModel()
        let real = AppKitHostWindow(spec: SurfaceWindowSpec(kind: "panel", property: { _ in .null }), content: AnyView(GrowView(model: model)))
        real.setFrame(CGRect(x: 0, y: 0, width: 40, height: 40))
        real.watchFitting(true)
        var reported = 0
        real.onFittingChange = { reported += 1 }
        real.hosting.layoutSubtreeIfNeeded()
        let before = real.fittingSize
        reported = 0
        model.text = String(repeating: "wide ", count: 20)
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 20_000_000)
            real.hosting.layoutSubtreeIfNeeded()
        }
        #expect(real.fittingSize.width > before.width)
        #expect(reported > 0)
    }
}

@MainActor
@Observable
final class GrowModel {
    var text = "x"
}

struct GrowView: View {
    let model: GrowModel

    var body: some View {
        Text(model.text).fixedSize().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
