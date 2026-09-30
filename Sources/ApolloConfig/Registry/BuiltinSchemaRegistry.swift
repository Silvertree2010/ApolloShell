enum BuiltinSchemaRegistry {
    static let allNodes: [NodeSchema] =
        LanguageNodes.all
            + TopLevelBlocks.all
            + Surfaces.all
            + Layout.all
            + Elements.all
            + MenuNodes.all
            + CommandCenterNodes.all
            + WMSettings.all
            + SettingsFileNodes.all
            + [MenuBarRegistry.appMenus, MenuBarRegistry.statusItemSurface]

    static let nodesResult = RegistryBuilder.dictionary(allNodes, name: { $0.name })

    static var nodeNameDuplicates: [String] { nodesResult.duplicates }

    static let allActions: [ActionSchema] = ActionsGlobal.all

    static let actionsResult = RegistryBuilder.dictionary(allActions, name: { $0.name })

    static var actionNameDuplicates: [String] { actionsResult.duplicates }

    static let allProviders: [ProviderSchema] = [
        ProvidersCore.clock, ProvidersCore.battery, ProvidersCore.network, ProvidersCore.bluetooth,
        ProvidersCore.audio, ProvidersCore.media, ProvidersCore.perf,
        ProvidersMore.spaces, ProvidersMore.apps, ProvidersMore.weather, ProvidersMore.keyboard,
        ProvidersMore.window, ProvidersMore.screens, ProvidersMore.system, ProvidersMore.session,
        ProvidersMore.power, ProvidersMore.permissions, ProvidersMore.shortcuts,
        ProvidersMore.marketplace, ProvidersMore.wm,
        MenuBarRegistry.menubar, MenuBarRegistry.statusItems,
    ] + ProvidersExtras.all

    static let providersResult = RegistryBuilder.dictionary(allProviders, name: { $0.id })

    static var providerNameDuplicates: [String] { providersResult.duplicates }

    static let allFilters: [FilterSchema] = Filters.all + [MenuBarRegistry.runs]

    static let filtersResult = RegistryBuilder.dictionary(allFilters, name: { $0.name })

    static var filterNameDuplicates: [String] { filtersResult.duplicates }

    static let allEvents: [EventSchema] = allProviders.flatMap(\.events) + [
        EventSchema(name: "shell.started", doc: "The shell is ready."),
        EventSchema(name: "config.loaded", fields: [ProviderSupport.field("warnings", .number, update: .once, doc: "Number of warnings.")], doc: "A config loaded without errors."),
        EventSchema(name: "config.failed", fields: [ProviderSupport.field("errors", .number, update: .once, doc: "Number of errors.")], doc: "A config failed to load."),
        EventSchema(name: "theme.changed", fields: [ProviderSupport.field("id", .string, update: .once, doc: "New theme id.")], doc: "The theme changed."),
        EventSchema(name: "system.will-sleep", doc: "The computer is about to sleep."),
        EventSchema(name: "system.did-wake", doc: "The computer woke up."),
        EventSchema(name: "fullscreen.changed", fields: [
            ProviderSupport.field("screen", .string, update: .once, doc: "Affected screen."),
            ProviderSupport.field("active", .bool, update: .once, doc: "Whether full screen is active."),
        ], doc: "A full-screen app was entered or left."),
        EventSchema(name: "system.session-inactive", doc: "Fast user switch away."),
        EventSchema(name: "system.session-active", doc: "Fast user switch back."),
    ]

    static let eventsResult = RegistryBuilder.dictionary(allEvents, name: { $0.name })

    static var eventNameDuplicates: [String] { eventsResult.duplicates }

    static let menuSourcesResult = RegistryBuilder.dictionary(MenuSources.all + MenuBarRegistry.menuSources, name: { $0.name })

    static var menuSourceNameDuplicates: [String] { menuSourcesResult.duplicates }

    static let contextRootsResult = RegistryBuilder.dictionary(ContextRoots.all, name: { $0.name })

    static var contextRootNameDuplicates: [String] { contextRootsResult.duplicates }

    static let featuresResult = RegistryBuilder.dictionary(Features.all, name: { $0.name })

    static var featureNameDuplicates: [String] { featuresResult.duplicates }

    static func make() -> SchemaRegistry {
        SchemaRegistry(
            nodes: nodesResult.dict,
            actions: actionsResult.dict,
            providers: providersResult.dict,
            filters: filtersResult.dict,
            events: eventsResult.dict,
            menuSources: menuSourcesResult.dict,
            contextRoots: contextRootsResult.dict,
            features: featuresResult.dict,
            reservedProviderNames: Features.reservedProviderNames,
            fixedRoots: Features.fixedRoots
        )
    }
}
