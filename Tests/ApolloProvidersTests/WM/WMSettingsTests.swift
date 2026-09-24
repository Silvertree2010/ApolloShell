import Testing
import Foundation
import ApolloBase
import ApolloConfig
import ApolloShellCore
import ApolloWMCore
@testable import ApolloProviders

enum WMLoad {
    static func ir(_ shell: String, extra: [String: String] = [:]) -> (ConfigIR?, [Diagnostic]) {
        var files = ["/config/shell.kdl": "require \"0.2.0\"\n" + shell]
        for (path, text) in extra { files[path] = text }
        let paths = ConfigPaths(builtinConfigs: URL(fileURLWithPath: "/builtin"), userConfig: URL(fileURLWithPath: "/config"), applicationSupport: URL(fileURLWithPath: "/support"))
        let loader = ConfigLoader(fileSystem: MemoryFileSystem(files), paths: paths, registry: .builtin, filters: .builtin, shellVersion: "0.2.0")
        let result = loader.load(ConfigLocation(id: "mine", root: URL(fileURLWithPath: "/config"), isBuiltin: false))
        return (result.ir, result.diagnostics)
    }

    static func settings(_ shell: String) -> WMSettings? {
        let (ir, diagnostics) = ir(shell)
        #expect(diagnostics.filter { $0.severity == .error }.isEmpty, "\(diagnostics)")
        return ir.flatMap(WMSettings.init(config:))
    }
}

@Suite("wm-Block")
struct WMSettingsTests {
    @Test("Ohne wm-Block gibt es keine Einstellungen")
    func absent() {
        #expect(WMLoad.settings("var x") == nil)
    }

    @Test("Leerer Block hat die Vorgaben aus runtime.md 9.1")
    func defaults() throws {
        let settings = try #require(WMLoad.settings("wm"))
        #expect(settings.layout == .dwindle)
        #expect(settings.innerGap == 10 && settings.outerGap == 12)
        #expect(settings.focusFollowsMouse && settings.focusDelay == 0.025 && settings.focusSuspendWith == [])
        #expect(settings.dragModifiers == .hyper && settings.scrollPans && settings.scrollSpeed == 1.5 && !settings.invertScroll)
        #expect(settings.resize == .smooth)
        #expect(settings.springResponse == 0.28 && settings.frameRate == 120)
        #expect(settings.tabBarHeight == 30)
        #expect(settings.columnWidth == 0.5 && !settings.centerFocused)
        #expect(settings.scratchpadShare == 0.7)
        #expect(settings.terminals == ["net.kovidgoyal.kitty", "com.mitchellh.ghostty", "com.apple.Terminal"])
        #expect(settings.appleDesktops)
        #expect(settings.rules.isEmpty && settings.reservePanels && settings.reserves.isEmpty)
        #expect(settings.enabled == nil)
        #expect(settings.problems.isEmpty)
    }

    @Test("Beispiel aus runtime.md 9.1")
    func specExample() throws {
        let settings = try #require(WMLoad.settings("""
        wm enabled=#true {
            layout "canvas"
            gaps inner=6 outer=8
            focus-follows-mouse #false delay="80ms" suspend-with="cmd+alt"
            drag super="ctrl+shift" scroll-pans=#false scroll-speed=2 invert-scroll=#true
            resize-animation "proxy"
            spring response=0.2 frame-rate=60
            tab-bar height=24
            canvas column-width=0.6 center-focused=#true
            scratchpad share=0.5
            terminal "com.mitchellh.ghostty" "com.apple.Terminal"
            apple-desktops #false
            rule "float" app="com.apple.calculator"
            rule "float" app="System Settings"
            rule "ignore" app="zoom.us" title="Meeting"
            reserve-panels #false
            reserve top=24
            reserve left=40 screen="main"
        }
        """))
        #expect(settings.enabled?.isConstant == true)
        #expect(settings.layout == .canvas)
        #expect(settings.innerGap == 6 && settings.outerGap == 8)
        #expect(!settings.focusFollowsMouse && abs(settings.focusDelay - 0.08) < 1e-9)
        #expect(settings.focusSuspendWith == [.command, .option])
        #expect(settings.dragModifiers == [.control, .shift] && !settings.scrollPans && settings.scrollSpeed == 2 && settings.invertScroll)
        #expect(settings.resize == .proxy)
        #expect(settings.springResponse == 0.2 && settings.frameRate == 60 && settings.tabBarHeight == 24)
        #expect(settings.columnWidth == 0.6 && settings.centerFocused && settings.scratchpadShare == 0.5)
        #expect(settings.terminals == ["com.mitchellh.ghostty", "com.apple.Terminal"])
        #expect(!settings.appleDesktops && !settings.reservePanels)
        #expect(settings.rules == [
            WindowRule(action: .float, app: "com.apple.calculator"),
            WindowRule(action: .float, app: "System Settings"),
            WindowRule(action: .ignore, app: "zoom.us", title: "Meeting"),
        ])
        #expect(settings.reserves == [
            WMSettings.Reserve(top: 24),
            WMSettings.Reserve(left: 40, screen: "main"),
        ])
        #expect(settings.problems.isEmpty)
    }

    @Test("enabled als Ausdruck bleibt ein Ausdruck")
    func enabledExpression() throws {
        let settings = try #require(WMLoad.settings("var tiling type=\"bool\"\nwm enabled=\"{var.tiling}\""))
        let enabled = try #require(settings.enabled)
        #expect(!enabled.isConstant)
        #expect(enabled.dependencies.contains { $0.root == "var" })
    }

    @Test("Mehrere wm-Blöcke: spätere Werte gewinnen, Regeln und Ränder sammeln sich")
    func merge() throws {
        let settings = try #require(WMLoad.settings("""
        wm { layout "canvas"; rule "float" app="a"; reserve top=10 }
        wm { gaps inner=4; rule "tile" title="b"; reserve bottom=5 }
        """))
        #expect(settings.layout == .canvas && settings.innerGap == 4 && settings.outerGap == 12)
        #expect(settings.rules.map(\.action) == [.float, .tile])
        #expect(settings.reserves.count == 2)
    }

    @Test("Unsinnige Werte melden ein Problem und behalten die Vorgabe")
    func problems() throws {
        let settings = try #require(WMLoad.settings("""
        wm {
            rule "float"
            drag super="cmd+banana"
            canvas column-width=3
        }
        """))
        #expect(settings.rules.isEmpty)
        #expect(settings.dragModifiers == .hyper)
        #expect(settings.columnWidth == 0.5)
        #expect(settings.problems.count == 3)
    }
}
