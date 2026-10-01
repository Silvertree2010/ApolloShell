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
