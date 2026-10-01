import Testing
import AppKit
import Foundation
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
import ApolloStyle
@testable import ApolloShell

@MainActor
@Suite("VM test findings", .serialized)
struct VMFixTests {
    @Test("Wi-Fi popout without an interface still draws its header and lead row")
    func wifiNone() throws {
        let s = try DefaultRenderTests.shot("menubar-status-popout", state: "menubar-popout-wifi-none")
        #expect(s.size.height > 60)
    }
}

@MainActor
@Suite("VM test findings: popout open", .serialized)
struct PopoutOpenTests {
    @Test("A status button sets the next popout, emits, and the popup opens attached to that button")
    func opens() async throws {
        let fx = try HostFixture("""
        var po ""
        var pn ""
        panel "bar" anchor="top" {
            button id="b-wifi" { on-click { set "pn" "wifi"; emit "pop" } }
        }
        on "user.pop" when="{var.po == var.pn}" { close "p" }
        on "user.pop" when="{var.po != var.pn}" { set "po" "{var.pn}"; open "p" }
        popup "p" attach="{'bar#b-' + var.po}" side="bottom" {
            text "x"
        }
        """)
        fx.assembly.runtime.open("bar", screenKey: HostFixture.screen.key)
        fx.flush()
        let t = fx.assembly.runtime.trigger("on-click", on: Identity(["bar@\(HostFixture.screen.key)", "#b-wifi"]), event: Record())
        await t?.value
        fx.flush()
        let c = try #require(fx.host.controllers.values.first { $0.surface.id == "p" })
        #expect(c.surface.property("attach") == .string("bar#b-wifi"))
        #expect(fx.window("p")?.isShown == true)
    }
}

@MainActor
@Suite("VM test findings: imported dashboard pages", .serialized)
struct ImportedPagesTests {
    func state() throws -> [String: Value] {
        LegacyImport.convert(settings: try LegacyImportStartTests.fixture("settings-vmtest.json"), weather: nil, launcherOnly: false).state
    }

    func widgets(_ page: String) throws -> [Record] {
        guard case .list(let l)? = try state()["dashboard-widgets"] else { return [] }
        return l.compactMap { if case .record(let r) = $0, r["page"] == .string(page) { return r } else { return nil } }
    }

    @Test("dashboardPages are imported with the four template pages mapped to the default ids")
    func pages() throws {
        guard case .list(let l)? = try state()["dashboard-pages"] else { Issue.record("no pages"); return }
        let ids = l.compactMap { v -> String? in if case .record(let r) = v, case .string(let i)? = r["id"] { return i } else { return nil } }
        #expect(Array(ids.prefix(4)) == ["dashboard", "media", "performance", "weather"])
        #expect(ids.count == 6)
        #expect(try state()["dashboard-seeded"] == .bool(true))
    }

    @Test("widget options come across with kebab-case names")
    func options() throws {
        let overview = try widgets("dashboard")
        let cal = try #require(overview.first { $0["kind"] == .string("calendar") })
        #expect(cal["first-weekday"] == .string("monday"))
        #expect(cal["show-week-numbers"] == .bool(false))
        let res = try #require(overview.first { $0["kind"] == .string("resources") })
        #expect(res["show-cpu"] == .bool(true) && res["show-memory"] == .bool(true) && res["show-storage"] == .bool(true))
        let w = try #require(overview.first { $0["kind"] == .string("weather") })
        #expect(w["show-condition"] == .bool(true))
        #expect(w["place-id"] == .string("14454FBF-A692-4FE5-9238-66D7B07EA735"))
        let apps = try #require(try state()["dashboard-widgets"].flatMap { v -> Record? in
            if case .list(let l) = v { return l.compactMap { if case .record(let r) = $0, r["kind"] == .string("apps") { return r } else { return nil } }.first } else { return nil }
        })
        #expect(apps["apps"] == .list([.string("com.apple.finder"), .string("com.apple.Safari"), .string("com.apple.mail"), .string("com.apple.Music"), .string("com.apple.systempreferences")]))
    }
}

@Suite("VM test findings: default config structure")
struct VMFixConfigTests {
    @Test("the dashboard popup sits below Apple's menu bar so the bar stays reachable")
    func dashboardArea() throws {
        let ir = try #require(PackageResources.load(DefaultConfigTests.defaultFolder, id: "apolloshell-default").ir)
        let d = try #require(ir.surfaces.first { $0.id == "dashboard" })
        #expect(String(describing: d.properties["area"]).contains("below-menubar"))
    }
}

@MainActor
@Suite("VM test findings: edit mode Esc chain", .serialized)
struct EditEscapeTests {
    func v(_ h: ShellHarness, _ n: String) -> Value? { h.shell.assembly?.vars.value(n) }

    func run(_ h: ShellHarness, _ a: String) async throws { _ = try await h.shell.runActions(a); h.settle() }

    func esc(_ h: ShellHarness) {
        _ = h.shell.keyPressed("escape", surfaceID: "dashboard-toolbar", screenKey: ShellHarness.a.key)
        h.settle()
    }

    @Test("Esc closes selection, then gallery, then asks before discarding changes, and only cancels when nothing changed")
    func chain() async throws {
        let h = try ShellHarness("include \"builtin:apolloshell-default/shell.kdl\"\non \"user.t-begin\" { use \"edit-begin\" }")
        try await h.start()
        defer { h.shell.shutdown() }
        for task in h.shell.assembly?.runtime.emit("user.t-begin", Record()) ?? [] { await task.value }
        h.settle()
        try await run(h, "set \"dashboard-selected\" \"dashboard-weather\"; set \"dashboard-gallery\" #true")
        esc(h)
        #expect(v(h, "dashboard-selected") == .null && v(h, "dashboard-gallery") == .bool(true) && v(h, "shell-editing") == .bool(true))
        esc(h)
        #expect(v(h, "dashboard-gallery") == .bool(false) && v(h, "shell-editing") == .bool(true))
        try await run(h, "set \"dashboard-widgets\" \"{var.dashboard-widgets | where 'kind' 'none'}\"")
        esc(h)
        #expect(v(h, "dashboard-confirm") == .bool(true) && v(h, "shell-editing") == .bool(true))
        esc(h)
        #expect(v(h, "dashboard-confirm") == .bool(false) && v(h, "shell-editing") == .bool(true))
        try await run(h, "set \"dashboard-widgets\" \"{var.dashboard-backup-widgets}\"")
        esc(h)
        #expect(v(h, "shell-editing") == .bool(false))
    }
}

@MainActor
@Suite("VM test findings: introduction window")
struct IntroWindowTests {
    @Test("titlebar=#false lets the content reach the top edge")
    func mask() {
        let s = SurfaceWindowSpec(kind: "window", property: { $0 == "titlebar" ? .bool(false) : .null })
        #expect(s.styleMask.contains(.fullSizeContentView) && s.styleMask.contains(.titled))
        #expect(!SurfaceWindowSpec(kind: "window", property: { _ in .null }).styleMask.contains(.fullSizeContentView))
    }

    @Test("the default config's introduction has no title bar and the 0.2 wording")
    func onboarding() throws {
        let t = try String(contentsOf: DefaultConfigTests.defaultFolder.appendingPathComponent("onboarding.kdl"), encoding: .utf8)
        #expect(t.contains("window \"onboarding\" title=\"Introduction\" titlebar=#false"))
        #expect(t.contains("everything can be set up from its icon in the menu bar."))
        #expect(t.contains("title=\"Control Centre\" text=\"Keep Awake"))
    }

    @Test("a window without a stored frame opens centred horizontally and a quarter from the top like NSWindow.center")
    func centred() throws {
        let fx = try HostFixture("window \"w\" { }")
        fx.assembly.runtime.open("w", screenKey: HostFixture.screen.key)
        fx.flush()
        let w = try #require(fx.window("w"))
        let v = HostFixture.screen.visible
        #expect(abs(w.frame.minY - (v.minY + (v.height - w.frame.height) * 0.75)) < 1)
        #expect(abs(w.frame.midX - v.midX) < 1)
    }
}

@MainActor
@Suite("VM test findings: Wi-Fi switch", .serialized)
struct WifiSwitchTests {
    func lum(_ s: Snapshot) -> Double {
        var t = 0.0
        let w = Int(s.size.width), h = Int(s.size.height)
        for y in stride(from: 0, to: h, by: 2) { for x in stride(from: 0, to: w, by: 2) { let p = s.pixel(CGFloat(x), CGFloat(y)); t += Double(p.r) + Double(p.g) + Double(p.b) } }
        return t
    }

    @Test("The Wi-Fi quick toggle is dimmed when the Mac has no Wi-Fi interface")
    func dimmed() throws {
        let off = try DefaultRenderTests.shot("utilities", state: "utilities-wifi-off")
        let none = try DefaultRenderTests.shot("utilities", state: "utilities-wifi-none")
        #expect(lum(none) != lum(off))
    }
}

@MainActor
@Suite("VM test findings: own status item", .serialized)
struct OwnItemTests {
    @Test("the ApolloShell status item sits on a light tile with a dark mark")
    func tile() throws {
        let s = try DefaultRenderTests.shot("menubar", state: "menubar-own-tile")
        let t = try #require(s.bounds { $0.r > 250 && $0.g > 250 && $0.b > 250 })
        #expect(t.width >= 20 && t.width <= 24 && t.height >= 16 && t.height <= 20, "\(t)")
        let mark = try #require(s.bounds { $0.r < 60 && $0.g < 60 && $0.b < 60 && $0.a > 200 })
        #expect(mark.width > 4)
    }
}

@Suite("VM test findings: menu bar popout")
struct MenuBarPopoutConfigTests {
    @Test("the menu bar popout does not close on focus loss, so activation by its own click cannot close it")
    func closeOn() throws {
        let ir = try #require(PackageResources.load(DefaultConfigTests.defaultFolder, id: "apolloshell-default").ir)
        let p = try #require(ir.surfaces.first { $0.id == "menubar-status-popout" })
        let d = String(describing: p.properties["close-on"])
        #expect(d.contains("outside-click") && d.contains("escape") && !d.contains("focus-loss"))
    }
}
