import Foundation
import Testing
@testable import ApolloShellCore

@Suite struct SettingsIndexTests {
    let pages = [SettingsPage(id: "lyrics", title: "Lyrics"), SettingsPage(id: "desktop", title: "Desktop"),
                 SettingsPage(id: "bar", title: "Bar"), SettingsPage(id: "about", title: "About")]

    @Test func idsAreUniqueAndParentsExist() {
        let ids = SettingsIndex.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for d in SettingsIndex.all {
            if let p = d.parent { #expect(SettingsIndex.find(p)?.kind == .toggle) }
            #expect(!d.title.isEmpty && !d.group.isEmpty)
        }
    }

    @Test func togglesRoundTrip() {
        for d in SettingsIndex.all where d.kind == .toggle {
            var s = ShellSettings.firstLaunch
            let a = d.isOn(in: s)
            d.toggle(in: &s)
            #expect(d.isOn(in: s) == !a, "\(d.id)")
            #expect(d.modified(in: s))
            #expect(SettingsIndex.modified(in: s).map(\.id) == [d.id])
            d.reset(in: &s)
            #expect(s == ShellSettings.firstLaunch, "\(d.id)")
        }
    }

    @Test func choicesRoundTripAndRejectJunk() {
        for d in SettingsIndex.all {
            guard case .choice(let o) = d.kind else { continue }
            #expect(o.contains { $0.id == d.standard }, "\(d.id)")
            for x in o {
                var s = ShellSettings.firstLaunch
                d.write(x.id, to: &s)
                #expect(d.value(in: s) == x.id)
                #expect(d.label(in: s) == x.title)
            }
            var s = ShellSettings.firstLaunch
            d.write("nope", to: &s)
            #expect(s == ShellSettings.firstLaunch)
        }
    }

    @Test func parentGatesChild() throws {
        var s = ShellSettings.firstLaunch
        let d = try #require(SettingsIndex.find("lyrics.edge"))
        #expect(!d.enabled(in: s))
        s.lyrics.enabled = true
        #expect(!d.enabled(in: s))
        s.lyrics.desktop = true
        #expect(d.enabled(in: s))
    }

    @Test func searchRanksTitleFirstAndPageOnTies() {
        let s = ShellSettings.firstLaunch
        let h = SettingsIndex.search("lyrics", in: s, pages: pages)
        #expect(h.first?.id == "page:lyrics")
        #expect(h.dropFirst().first?.id == "lyrics.on")
        #expect(SettingsIndex.search("desk lyr", in: s, pages: pages).first?.id == "lyrics.desktop")
        #expect(SettingsIndex.search("airpods", in: s, pages: pages).map(\.id) == ["toast.out"])
        #expect(SettingsIndex.search("bar right", in: s, pages: pages).first?.id == "bar.side")
        #expect(SettingsIndex.search("zzzz", in: s, pages: pages).isEmpty)
        #expect(SettingsIndex.search("  ", in: s, pages: pages).isEmpty)
    }

    @Test func modifiedFilter() {
        var s = ShellSettings.firstLaunch
        #expect(SettingsIndex.search("@modified", in: s, pages: pages).isEmpty)
        s.lyrics.enabled = true
        s.toasts.batteryWarnings.toggle()
        #expect(Set(SettingsIndex.search("@mod", in: s, pages: pages).map(\.id)) == ["lyrics.on", "toast.battery"])
        #expect(SettingsIndex.search("@modified battery", in: s, pages: pages).map(\.id) == ["toast.battery"])
        let q = SettingsQuery("@modified  Foo")
        #expect(q.modified && q.words == ["foo"])
    }

    @Test func counts() {
        let h = SettingsIndex.search("on", in: .firstLaunch, pages: pages)
        let c = SettingsIndex.counts(h)
        #expect(c.values.reduce(0, +) == h.count)
    }

    @Test func nexusLookDecodesLeniently() {
        #expect(ShellSettings.load(from: Data(#"{"nexus":{"look":"glass"}}"#.utf8)).nexus.look == .glass)
        #expect(ShellSettings.load(from: Data(#"{"nexus":{"look":7}}"#.utf8)).nexus.look == .graphite)
    }
}

@Suite struct SettingsArgumentTests {
    @Test func target() {
        #expect(SingleInstance.settingsTarget(arguments: ["app"]) == nil)
        #expect(SingleInstance.settingsTarget(arguments: ["app", "--settings"]) == .some(nil))
        #expect(SingleInstance.settingsTarget(arguments: ["app", "--settings", "lyrics.desktop"]) == .some("lyrics.desktop"))
        #expect(SingleInstance.settingsTarget(arguments: ["app", "--settings", "--relaunch"]) == .some(nil))
    }
}

@Suite struct SettingsActionTests {
    @Test func launcherActions() {
        var s = ShellSettings.firstLaunch
        #expect(SettingsIndex.actions("desktop lyrics", in: s).isEmpty)
        s.lyrics.enabled = true
        let a = SettingsIndex.actions("desktop lyrics", in: s)
        #expect(a.first?.id == "lyrics.desktop")
        #expect(a.first?.action(in: s) == "Turn On Desktop Lyrics")
        s.lyrics.desktop = true
        #expect(SettingsIndex.find("lyrics.desktop")?.action(in: s) == "Turn Off Desktop Lyrics")
        #expect(SettingsIndex.find("bar.side")?.action(in: s) == "Position: Left")
        #expect(SettingsIndex.actions("ly", in: s).allSatisfy { $0.id.hasPrefix("lyrics") })
    }
}
