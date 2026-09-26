import Testing
import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
@Suite("Provider apps")
struct AppsProviderTests {
    func make(_ configure: (FakeAppsSource) -> Void = { _ in }) -> (ProviderHarness, FakeAppsSource, AppsProvider) {
        let harness = ProviderHarness()
        let source = FakeAppsSource(clock: harness.clock)
        configure(source)
        let provider = AppsProvider(source: source, clock: harness.clock)
        harness.register(provider)
        return (harness, source, provider)
    }

    func list(_ harness: ProviderHarness, _ field: String) -> [Record] {
        guard case .list(let items) = harness.value("apps", field) else { return [] }
        return items.compactMap { if case .record(let record) = $0 { record } else { nil } }
    }

    @Test("Liefert jedes Registry-Feld mit vollständigen App-Records")
    func deliversAllFields() {
        let (harness, _, _) = make()
        harness.demand("apps")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("apps")).isEmpty)
        #expect(list(harness, "all").count == 5)
        #expect(list(harness, "running").map { $0["bundle-id"] } == [.string("com.apple.finder"), .string("com.apple.Safari"), .string("com.apple.Notes")])
        let keys = ["bundle-id", "name", "path", "icon", "installed", "usage", "favorite-index", "running", "launching", "active", "hidden", "badge", "windows", "minimized", "dock-pinned", "favorite"]
        for record in list(harness, "all") + list(harness, "dock") + list(harness, "favorites") + list(harness, "running") {
            #expect(Set(record.keys).isSuperset(of: keys))
        }
        guard case .record(let front) = harness.value("apps", "frontmost") else {
            Issue.record("frontmost fehlt")
            return
        }
        #expect(front["bundle-id"] == .string("com.apple.Safari"))
        #expect(harness.value("apps", "file-manager.bundle-id") == .string("com.binarynights.ForkLift"))
        #expect(list(harness, "file-managers").map { $0["bundle-id"] } == [.string("com.apple.finder"), .string("com.binarynights.ForkLift")])
    }

    @Test("Dock wie 0.1.4.2: Dateimanager, angeheftet, laufend; Finder ausgeblendet neben ForkLift")
    func dockLayout() {
        let (harness, _, _) = make()
        harness.demand("apps", "dock")
        let dock = list(harness, "dock")
        #expect(dock.map { $0["bundle-id"] } == [.string("com.binarynights.ForkLift"), .string("com.apple.Safari"), .string("com.apple.mail"), .string("com.apple.Notes")])
        #expect(dock.map { $0["section"] } == [.string("file-manager"), .string("pinned"), .string("pinned"), .string("running")])
        #expect(dock[0]["icon"] == .image(ImageRef(source: "builtin", id: "file-manager-folder")))
        #expect(dock[0]["dock-pinned"] == .bool(false))
        #expect(dock[1]["dock-pinned"] == .bool(true))
        #expect(dock[2]["badge"] == .string("3"))
        #expect(dock[3]["hidden"] == .bool(true))
        #expect(dock[3]["minimized"] == .number(1))
    }

    @Test("Einstellung file-manager: Finder erzwingen, unbekannt heisst automatisch")
    func fileManagerSetting() {
        let (harness, _, provider) = make()
        provider.configure(Record([("file-manager", .string("com.apple.finder"))]))
        harness.demand("apps", "dock", "file-manager")
        #expect(list(harness, "dock").first?["bundle-id"] == .string("com.apple.finder"))
        #expect(list(harness, "dock").first?["icon"] == .image(ImageRef(source: "app-icon", id: "com.apple.finder")))
        provider.configure(Record([("file-manager", .null)]))
        harness.flush()
        #expect(harness.value("apps", "file-manager.bundle-id") == .string("com.binarynights.ForkLift"))
    }

    @Test("Favoriten: Reihenfolge, fehlende App bleibt mit installed=false, Hinzufügen, Verschieben, Grenze")
    func favorites() async throws {
        let (harness, source, _) = make()
        harness.demand("apps", "favorites")
        var favorites = list(harness, "favorites")
        #expect(favorites.map { $0["bundle-id"] } == [.string("com.apple.mail"), .string("org.gone.App")])
        #expect(favorites[1]["installed"] == .bool(false))
        #expect(favorites[1]["name"] == .string("org.gone.App"))
        #expect(favorites[0]["favorite-index"] == .number(0))
        _ = try await harness.perform("apps", "apps.favorite-add", [.string("com.apple.Safari")])
        _ = try await harness.perform("apps", "apps.favorite-move", [.number(2), .number(0)])
        _ = try await harness.perform("apps", "apps.favorite-remove", [.record(Record([("bundle-id", .string("org.gone.App"))]))])
        favorites = list(harness, "favorites")
        #expect(favorites.map { $0["bundle-id"] } == [.string("com.apple.Safari"), .string("com.apple.mail")])
        #expect(PinnedList.load(from: source.favoritesData).ids == ["com.apple.Safari", "com.apple.mail"])
        for index in 0..<10 {
            _ = try await harness.perform("apps", "apps.favorite-add", [.string("app.\(index)")])
        }
        #expect(PinnedList.load(from: source.favoritesData).ids.count == 10)
        #expect(harness.warnings.filter { $0.severity == .warning }.count == 2)
    }

    @Test("favorite-move nimmt die Einfügestelle wie list.move: Move Down (+2) und Ziehen nach unten verschieben um genau die gezeigte Stelle")
    func favoriteMoveDown() async throws {
        let (harness, source, _) = make { $0.favoritesData = PinnedList(["a", "b", "c", "d"]).encoded() }
        harness.demand("apps", "favorites")
        _ = try await harness.perform("apps", "apps.favorite-move", [.number(0), .number(2)])
        #expect(PinnedList.load(from: source.favoritesData).ids == ["b", "a", "c", "d"])
        _ = try await harness.perform("apps", "apps.favorite-move", [.number(0), .number(3)])
        #expect(PinnedList.load(from: source.favoritesData).ids == ["a", "c", "b", "d"])
        _ = try await harness.perform("apps", "apps.favorite-move", [.number(3), .number(1)])
        #expect(PinnedList.load(from: source.favoritesData).ids == ["a", "d", "c", "b"])
    }

    @Test("Unlesbare pinned.json wird gesichert und als leer gelesen")
    func unreadableFavorites() {
        let (harness, source, _) = make { $0.favoritesData = Data("{kaputt".utf8) }
        harness.demand("apps", "favorites")
        #expect(source.preservedUnreadable == 1)
        #expect(list(harness, "favorites").isEmpty)
    }

    @Test("Plaketten alle 3 s, nur solange das Dock gefragt ist")
    func badgesFollowDemand() {
        let (harness, source, _) = make()
        harness.demand("apps", "running")
        harness.advance(10)
        #expect(source.badgeReads == 0)
        let dock = harness.demand("apps", "dock")
        #expect(source.badgeReads == 1)
        harness.advance(3)
        #expect(source.badgeReads == 2)
        source.badges = [:]
        harness.advance(3)
        #expect(list(harness, "dock")[2]["badge"] == .null)
        harness.release(dock)
        harness.advance(30)
        #expect(source.badgeReads == 3)
    }

    @Test("Katalog wird bei jeder neuen Nachfrage nach all und bei apps.refresh gelesen")
    func catalogRescans() async throws {
        let (harness, source, _) = make()
        harness.demand("apps", "running")
        #expect(source.scans == 0)
        let token = harness.demand("apps", "all")
        #expect(source.scans == 1)
        harness.release(token)
        harness.demand("apps", "all")
        #expect(source.scans == 2)
        _ = try await harness.perform("apps", "apps.refresh")
        #expect(source.scans == 3)
    }

    @Test("Ereignisse launched, terminated, activated mit App-Record")
    func events() {
        let (harness, source, _) = make()
        let awake = harness.keepAwake("apps")
        source.running.append(RunningApp(bundleID: "com.apple.mail", name: "Mail"))
        source.send(.launched("com.apple.mail"))
        source.send(.activated("com.apple.mail"))
        source.running.removeLast()
        source.send(.terminated("com.apple.mail"))
        #expect(harness.eventNames() == ["apps.launched", "apps.activated", "apps.terminated"])
        guard case .record(let app) = harness.events[0].fields["app"] ?? .null else {
            Issue.record("event.app fehlt")
            return
        }
        #expect(app["name"] == .string("Mail"))
        harness.releaseAwake(awake)
        #expect(!source.observing)
    }

    @Test("Nutzung: fremde Starts zählen, eigener Start nur einmal innerhalb von 10 s")
    func usageCounting() async throws {
        let (harness, source, _) = make()
        harness.demand("apps", "all")
        source.send(.launched("com.apple.Notes"))
        _ = try await harness.perform("apps", "apps.launch", [.string("com.apple.mail")])
        harness.advance(5)
        source.send(.launched("com.apple.mail"))
        harness.advance(11)
        source.send(.launched("com.apple.mail"))
        let usage = try JSONDecoder().decode(UsageStats.self, from: source.usageData ?? Data())
        #expect(usage.weight(for: "com.apple.Notes", at: source.now) > 0.99)
        #expect(usage.weight(for: "com.apple.mail", at: source.now) > 1.99)
        #expect(usage.weight(for: "com.apple.mail", at: source.now) < 2.01)
        let mail = list(harness, "all").first { $0["bundle-id"] == .string("com.apple.mail") }
        guard case .number(let weight) = mail?["usage"] ?? .null else {
            Issue.record("usage fehlt")
            return
        }
        #expect(weight > 1.99)
    }

    @Test("Klick: starten mit launching, Klicks beim Start zählen nicht, cmd zeigt, alt blendet vorherige aus")
    func click() async throws {
        let (harness, source, _) = make()
        harness.demand("apps", "dock")
        _ = try await harness.perform("apps", "apps.click", [.string("com.apple.mail")])
        #expect(source.launches == ["com.apple.mail"])
        #expect(list(harness, "dock")[2]["launching"] == .bool(true))
        _ = try await harness.perform("apps", "apps.click", [.string("com.apple.mail")])
        #expect(source.launches == ["com.apple.mail"])
        source.running.append(RunningApp(bundleID: "com.apple.mail", name: "Mail"))
        source.send(.launched("com.apple.mail"))
        #expect(list(harness, "dock")[2]["launching"] == .bool(false))

        _ = try await harness.perform("apps", "apps.click", [.string("com.apple.Notes")], properties: Record([("modifiers", .list([.string("alt")]))]))
        #expect(source.performed.map(\.0) == [
            .click(.unhide, previous: "com.apple.Safari"),
            .click(.raiseWindowOnActiveSpace, previous: "com.apple.Safari"),
            .click(.hidePrevious, previous: "com.apple.Safari"),
        ])
        _ = try await harness.perform("apps", "apps.click", [.string("com.apple.Safari"), .list([.string("cmd")])])
        #expect(source.revealed.count == 1)
        #expect(source.revealed.first?.1 == .fileManager(.openFolder(bundleID: "com.binarynights.ForkLift")))
    }

    @Test("dock-move nach DK-24, anheften und lösen")
    func dockMove() async throws {
        let (harness, source, _) = make()
        harness.demand("apps", "dock")
        _ = try await harness.perform("apps", "apps.dock-move", [.string("com.apple.mail"), .string("com.binarynights.ForkLift")])
        _ = try await harness.perform("apps", "apps.dock-move", [.string("com.apple.Safari"), .string("com.apple.mail")])
        _ = try await harness.perform("apps", "apps.dock-move", [.string("com.apple.mail"), .string("com.apple.Safari")])
        _ = try await harness.perform("apps", "apps.dock-move", [.string("com.apple.Notes"), .string("com.apple.mail")])
        _ = try await harness.perform("apps", "apps.dock-move", [.string("com.apple.Safari"), .string("com.apple.Notes")])
        _ = try await harness.perform("apps", "apps.dock-move", [.string("com.binarynights.ForkLift"), .string("com.apple.mail")])
        #expect(source.placed.map(\.1) == [.start, .after("com.apple.mail"), .before("com.apple.Safari"), .before("com.apple.mail"), .end])
        _ = try await harness.perform("apps", "apps.dock-unpin", [.string("com.apple.mail")])
        _ = try await harness.perform("apps", "apps.dock-unpin", [.string("com.binarynights.ForkLift")])
        _ = try await harness.perform("apps", "apps.dock-pin", [.string("com.apple.Notes")])
        #expect(source.removed == ["com.apple.mail"])
        #expect(source.placed.last?.1 == .end)
    }

    @Test("Fensteraktionen gehen an die Quelle; ohne Bedienungshilfen warnen sie")
    func windowActionsNeedAccessibility() async throws {
        let (harness, source, _) = make()
        harness.demand("apps", "running")
        _ = try await harness.perform("apps", "apps.new-window", [.string("com.apple.Safari")])
        _ = try await harness.perform("apps", "apps.cycle-windows", [.string("com.apple.Safari"), .string("up")])
        _ = try await harness.perform("apps", "apps.hide", [.string("com.apple.Safari")])
        _ = try await harness.perform("apps", "apps.open-files", [.string("com.apple.Safari"), .list([.string("/tmp/a.html")])])
        _ = try await harness.perform("apps", "apps.reveal", [.string("com.apple.Safari")], properties: Record([("in", .string("finder"))]))
        _ = try await harness.perform("apps", "apps.run-command", [.string("com.apple.Safari"), .string("New Tab")])
        #expect(source.performed.map(\.0) == [.newWindow, .cycleWindows(up: true), .hide, .openFiles(["/tmp/a.html"])])
        #expect(source.revealed.first?.1 == .finder)
        #expect(source.commands.count == 1)

        source.accessibilityTrusted = false
        _ = try await harness.perform("apps", "apps.run-command", [.string("com.apple.Safari"), .string("New Tab")])
        _ = try await harness.perform("apps", "apps.new-window", [.string("com.apple.Safari")])
        #expect(source.commands.count == 1)
        #expect(source.performed.count == 4)
        #expect(harness.warnings.filter { $0.severity == .warning }.count == 2)
        await #expect(throws: ProviderActionError.self) {
            try await harness.perform("apps", "apps.hide", [.number(3)])
        }
    }

    @Test("Schreibfehler warnt einmal je Datei mit dem Text aus NX-30")
    func saveFailureWarnsOnce() async throws {
        let (harness, source, _) = make()
        harness.demand("apps", "favorites")
        source.savesFail = true
        _ = try await harness.perform("apps", "apps.favorite-add", [.string("com.apple.Safari")])
        _ = try await harness.perform("apps", "apps.favorite-remove", [.string("com.apple.Safari")])
        let warnings = harness.warnings.filter { $0.severity == .warning }
        #expect(warnings.map(\.message) == ["pinned.json could not be saved. The change only applies until the next restart."])
    }

    @Test("launching endet spätestens nach 15 s")
    func launchingTimesOut() async throws {
        let (harness, _, _) = make()
        harness.demand("apps", "dock")
        _ = try await harness.perform("apps", "apps.launch", [.string("com.apple.mail")])
        #expect(list(harness, "dock")[2]["launching"] == .bool(true))
        harness.advance(14.75)
        #expect(list(harness, "dock")[2]["launching"] == .bool(true))
        harness.advance(0.5)
        #expect(list(harness, "dock")[2]["launching"] == .bool(false))
    }

    @Test("cycle-windows: sonst wie Klick, startet nie eine App")
    func cycleFallsBackToClick() async throws {
        let (harness, source, _) = make()
        harness.demand("apps", "running")
        source.cycles = false
        _ = try await harness.perform("apps", "apps.cycle-windows", [.string("com.apple.Notes"), .string("down")])
        #expect(source.performed.map(\.0) == [
            .cycleWindows(up: false),
            .click(.unhide, previous: "com.apple.Safari"),
            .click(.raiseWindowOnActiveSpace, previous: "com.apple.Safari"),
        ])
        _ = try await harness.perform("apps", "apps.cycle-windows", [.string("com.apple.mail"), .string("down")])
        #expect(source.launches.isEmpty)
        #expect(source.performed.count == 3)
    }
}
