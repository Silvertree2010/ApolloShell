import Testing
@testable import ApolloConfig

@Suite("Schema-Registry: Aktionen, Provider, Filter, Ereignisse")
struct SchemaRegistryProvidersTests {
    static let providerIDs: Set<String> = [
        "clock", "battery", "network", "bluetooth", "audio", "media", "perf", "spaces", "apps",
        "weather", "keyboard", "window", "screens", "system", "session", "power", "permissions",
        "shortcuts", "marketplace", "wm",
        "timer", "clipboard", "files", "drives", "photos", "network-info", "display", "wallpaper",
    ]

    static let menuSourceNames: Set<String> = ["app-dock", "app-commands", "app-windows"]

    static let contextRootNames: Set<String> = ["self", "surface", "surfaces", "screen", "theme", "shell", "event", "toast"]

    static let featureNames: Set<String> = [
        "core", "wm", "marketplace", "script-sources", "ipc", "fusion",
        "timer", "clipboard", "recent-files", "drives", "photos", "network-info", "display", "system-extras", "calc", "wallpaper",
    ]

    static let reservedProviderNames: Set<String> = [
        "menubar", "status-items", "fusion", "calendar-events", "reminders", "notifications",
        "focus", "location", "lua", "plugins", "windows", "input", "camera", "microphone", "canvas",
    ]

    static let fixedRoots: Set<String> = ["var", "self", "surface", "surfaces", "screen", "theme", "shell", "event", "toast"]

    @Test("keine doppelten Namen in Aktionen, Providern, Filtern, Ereignissen, Menü-Quellen, Kontext-Wurzeln, Features")
    func noDuplicates() {
        #expect(BuiltinSchemaRegistry.actionNameDuplicates.isEmpty)
        #expect(BuiltinSchemaRegistry.providerNameDuplicates.isEmpty)
        #expect(BuiltinSchemaRegistry.filterNameDuplicates.isEmpty)
        #expect(BuiltinSchemaRegistry.eventNameDuplicates.isEmpty)
        #expect(BuiltinSchemaRegistry.menuSourceNameDuplicates.isEmpty)
        #expect(BuiltinSchemaRegistry.contextRootNameDuplicates.isEmpty)
        #expect(BuiltinSchemaRegistry.featureNameDuplicates.isEmpty)
    }

    @Test("Filter-Namen der Registry entsprechen FilterTable.builtin.names")
    func filterNamesMatchFilterTable() {
        let registryNames = Set(BuiltinSchemaRegistry.allFilters.map(\.name))
        let tableNames = Set(FilterTable.builtin.names)
        #expect(registryNames == tableNames)
        #expect(registryNames.count == 59)
    }

    @Test("Stellenzahl jedes Filters entspricht seiner FilterArity")
    func filterArgumentCountsMatchArity() {
        for filter in BuiltinSchemaRegistry.allFilters {
            guard let arity = FilterTable.builtin.arity(named: filter.name) else {
                Issue.record("no arity for filter '\(filter.name)'")
                continue
            }
            let requiredCount = filter.arguments.filter(\.required).count
            #expect(requiredCount == arity.minimum, "\(filter.name) required count")
            #expect(filter.arguments.count == arity.maximum, "\(filter.name) argument count")
        }
    }

    @Test("jeder Provider aus providers.md 2 ist vorhanden")
    func allProvidersPresent() {
        let ids = Set(BuiltinSchemaRegistry.allProviders.map(\.id))
        #expect(ids == Self.providerIDs)
    }

    @Test("jeder Provider hat mindestens ein Feld, eine Aktion oder ein Ereignis")
    func providersAreNotEmpty() {
        for provider in BuiltinSchemaRegistry.allProviders {
            let hasContent = !provider.fields.isEmpty || !provider.actions.isEmpty || !provider.events.isEmpty
            #expect(hasContent, "\(provider.id) has neither fields, actions nor events")
        }
    }

    @Test("Menü-Quellen decken genau die Namensliste ab")
    func menuSourceNames() {
        let names = Set(MenuSources.all.map(\.name))
        #expect(names == Self.menuSourceNames)
    }

    @Test("Kontext-Wurzeln decken genau die Namensliste ab")
    func contextRootNames() {
        let names = Set(ContextRoots.all.map(\.name))
        #expect(names == Self.contextRootNames)
    }

    @Test("Features decken genau die Namensliste ab")
    func featureNames() {
        let names = Set(Features.all.map(\.name))
        #expect(names == Self.featureNames)
    }

    @Test("fixedRoots sind exakt die neun Wurzeln")
    func fixedRootsAreExact() {
        #expect(SchemaRegistry.builtin.fixedRoots == Self.fixedRoots)
        #expect(SchemaRegistry.builtin.fixedRoots.count == 9)
    }

    @Test("reservierte Provider-Namen entsprechen der Empfehlungsliste")
    func reservedProviderNamesAreExact() {
        #expect(SchemaRegistry.builtin.reservedProviderNames == Self.reservedProviderNames)
    }

    @Test("toast ist feste Wurzel, kein reservierter Provider")
    func toastIsFixedNotReserved() {
        #expect(SchemaRegistry.builtin.fixedRoots.contains("toast"))
        #expect(!SchemaRegistry.builtin.reservedProviderNames.contains("toast"))
    }

    @Test("SchemaRegistry.builtin trägt alle Register")
    func builtinCarriesEverything() {
        let registry = SchemaRegistry.builtin
        #expect(!registry.nodes.isEmpty)
        #expect(!registry.actions.isEmpty)
        #expect(!registry.providers.isEmpty)
        #expect(!registry.filters.isEmpty)
        #expect(!registry.events.isEmpty)
        #expect(!registry.menuSources.isEmpty)
        #expect(!registry.contextRoots.isEmpty)
        #expect(!registry.features.isEmpty)
        #expect(registry.node("panel") != nil)
        #expect(registry.action("open") != nil)
    }

    @Test("provider-Aktionen tragen einen Punkt im Namen")
    func providerActionsHaveDot() {
        for provider in BuiltinSchemaRegistry.allProviders {
            for action in provider.actions {
                #expect(action.name.contains("."), "\(action.name) should be dotted for provider \(provider.id)")
            }
        }
    }

    @Test("shell.set-login-item ist eine globale Aktion, login-item steht nur unter shell")
    func loginItemLivesUnderShell() {
        let registry = SchemaRegistry.builtin
        #expect(registry.action("shell.set-login-item") != nil)
        #expect(registry.actions["shell.set-login-item"] != nil)
        let permissions = registry.providers["permissions"]
        #expect(permissions?.actions.contains { $0.name == "shell.set-login-item" } == false)
        #expect(permissions?.fields.contains { $0.path == ["shell", "login-item"] } == false)
        let shell = ContextRoots.all.first { $0.name == "shell" }
        #expect(shell?.fields.contains { $0.path == ["login-item"] } == true)
    }

    @Test("shell-Kontext-Wurzel beschreibt configs, themes und update mit verschachtelten Feldern statt opaker Listen/Records")
    func shellContextRootHasDetailedNestedFields() {
        guard let shell = ContextRoots.all.first(where: { $0.name == "shell" }) else {
            Issue.record("no 'shell' context root")
            return
        }
        let paths = Set(shell.fields.map { $0.path.joined(separator: ".") })

        #expect(!paths.contains("configs"))
        #expect(paths.contains("configs.id"))
        #expect(paths.contains("configs.name"))
        #expect(paths.contains("configs.source"))

        #expect(!paths.contains("themes"))
        #expect(paths.contains("themes.id"))
        #expect(paths.contains("themes.name"))
        #expect(paths.contains("themes.author"))
        #expect(paths.contains("themes.description"))
        #expect(paths.contains("themes.issues"))

        #expect(!paths.contains("update"))
        #expect(paths.contains("update.status"))
        #expect(paths.contains("update.version"))
        #expect(paths.contains("update.notes-url"))
        #expect(paths.contains("update.last-check"))
        #expect(paths.contains("update.error"))

        guard let status = shell.fields.first(where: { $0.path == ["update", "status"] }) else {
            Issue.record("missing 'update.status'")
            return
        }
        #expect(status.type == .enumeration(["idle", "checking", "available", "ready", "failed", "unavailable"]))

        #expect(!paths.contains("hotkeys"))
        #expect(paths.contains("hotkeys.chord"))
        #expect(paths.contains("hotkeys.ok"))
    }
}
