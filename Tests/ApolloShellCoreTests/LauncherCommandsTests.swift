import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Launcher: the > action mode")
struct LauncherCommandsTests {
    @Test("what a search line means", arguments: [
        ("kitty", LauncherQuery.apps("kitty")),
        ("", LauncherQuery.apps("")),
        (">", LauncherQuery.actions("")),
        (">sh", LauncherQuery.actions("sh")),
        (" > dark ", LauncherQuery.actions("dark")),
        (">calc", LauncherQuery.actions("calc")),
        (">calc ", LauncherQuery.calculator("")),
        (">calc 2*(3+4)", LauncherQuery.calculator("2*(3+4)")),
        (">Calc 1+1", LauncherQuery.calculator("1+1")),
        (">theme cla", LauncherQuery.theme("cla")),
        (">wallpaper big sur", LauncherQuery.wallpaper("big sur")),
    ])
    func parse(text: String, expected: LauncherQuery) {
        #expect(LauncherQuery.parse(text) == expected)
    }

    @Test("the action list filters by the start of a word", arguments: [
        ("", LauncherAction.allCases),
        ("shut", [LauncherAction.shutDown]),
        ("wall", [LauncherAction.wallpaper, .randomWallpaper]),
        ("calc", [LauncherAction.calculator]),
        ("dark", [LauncherAction.dark]),
        ("xyz", []),
    ])
    func matching(text: String, expected: [LauncherAction]) {
        #expect(LauncherAction.matching(text) == expected)
    }

    @Test("only log out, restart and shut down ask first")
    func confirmation() {
        #expect(LauncherAction.allCases.filter(\.needsConfirmation) == [.logOut, .restart, .shutDown])
    }

    @Test("the calculator", arguments: [
        ("1+1", 2.0), ("2*(3+4)", 14), ("10/4", 2.5), ("2^3^2", 512), ("-3+5", 2),
        ("50%", 0.5), ("200*15%", 30), ("1,5*2", 3), ("sqrt(16)", 4), ("abs(-2)", 2),
        ("2 × 3 − 1", 5), ("8 ÷ 2", 4), ("round(2.6)", 3), ("log(1000)", 3), ("(1)", 1),
    ])
    func evaluate(text: String, expected: Double) {
        #expect(LauncherCalculator.evaluate(text) == expected)
    }

    @Test("half-typed or broken input gives nothing, never a crash", arguments: [
        "", "2*(", "(", ")", "2+", "*3", "1/0", "sqrt", "sqrt 4", "foo(2)", "1e5", "2..3", "abc",
    ])
    func invalid(text: String) {
        #expect(LauncherCalculator.evaluate(text) == nil)
    }

    @Test("pi and e", arguments: [("pi", Double.pi), ("2*pi", 2 * .pi), ("e", M_E)])
    func constants(text: String, expected: Double) {
        #expect(LauncherCalculator.evaluate(text) == expected)
    }

    @Test("results read like a calculator", arguments: [
        (7.0, "7"), (0.5, "0.5"), (-2, "-2"), (Double.pi, "3.141592654"), (1.0 / 3, "0.3333333333"),
    ])
    func format(value: Double, text: String) {
        #expect(LauncherCalculator.format(value) == text)
    }
}
