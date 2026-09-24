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

    static let nodesResult = RegistryBuilder.dictionary(allNodes, name: { $0.name })

    static var nodeNameDuplicates: [String] { nodesResult.duplicates }

    static func make() -> SchemaRegistry {
        SchemaRegistry(
            nodes: nodesResult.dict,
            actions: [:],
            providers: [:],
            filters: [:],
            events: [:],
            menuSources: [:],
            contextRoots: [:],
            features: [:],
            reservedProviderNames: [],
            fixedRoots: []
        )
    }
}
