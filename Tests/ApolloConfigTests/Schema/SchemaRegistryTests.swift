import Testing
@testable import ApolloConfig

@Suite("Schema-Registry: Knoten-Beschreibungen")
struct SchemaRegistryTests {
    static func isKebabCase(_ name: String) -> Bool {
        guard let first = name.first, first.isLowercase || first.isNumber else { return false }
        let segments = name.split(separator: "-", omittingEmptySubsequences: false)
        guard !segments.contains(where: { $0.isEmpty }) else { return false }
        return segments.allSatisfy { segment in
            segment.allSatisfy { $0.isLowercase || $0.isNumber }
        }
    }

    static let languageNames: Set<String> = [
        "include", "var", "define", "param", "slot", "fill", "use",
        "each", "when", "else", "switch", "case", "default", "disable", "require", "style", "filter",
    ]

    static let topLevelBlockNames: Set<String> = ["bind", "on", "poll", "listen", "wm", "command-center", "marketplace"]

    static let surfaceNames: Set<String> = ["panel", "popup", "overlay", "toast", "osd", "window"]

    static let layoutNames: Set<String> = ["row", "column", "grid", "stack", "scroll", "spacer"]

    static let elementNames: Set<String> = [
        "text", "icon", "image", "app-icon", "theme-preview", "mark", "shape", "button", "toggle",
        "slider", "input", "key-recorder", "ring", "gauge", "graph", "progress", "reorderable",
        "flyout", "menu", "accessibility-action",
    ]

    static let menuItemNames: Set<String> = ["item", "separator", "section", "submenu", "source"]

    static let commandCenterItemNames: Set<String> = ["builtin", "items"]

    static let wmSettingNames: Set<String> = [
        "layout", "gaps", "focus-follows-mouse", "drag", "resize-animation", "spring", "tab-bar",
        "canvas", "scratchpad", "terminal", "apple-desktops", "rule", "reserve-panels", "reserve",
    ]

    static let settingsFileNames: Set<String> = ["config", "theme", "updates", "crash-reports", "editor"]

    static let nodesWithChildren: Set<String> = [
        "define", "fill", "use", "each", "when", "else", "switch", "case", "default",
        "bind", "on", "wm", "command-center", "items",
        "panel", "popup", "overlay", "toast", "osd", "window",
        "row", "column", "grid", "stack", "scroll",
        "slider", "reorderable", "flyout", "menu", "accessibility-action",
        "submenu", "item",
    ]

    func nodes(category: NodeCategory) -> [NodeSchema] {
        BuiltinSchemaRegistry.allNodes.filter { $0.category == category }
    }

    @Test("keine doppelt registrierten Knotennamen")
    func noDuplicateNames() {
        #expect(BuiltinSchemaRegistry.nodeNameDuplicates.isEmpty)
    }

    @Test("Sprachknoten decken genau die Namensliste der Spec ab")
    func languageNodeNames() {
        let names = Set(nodes(category: .language).map(\.name))
        #expect(names == Self.languageNames)
    }

    @Test("oberste Blöcke decken genau die Namensliste der Spec ab")
    func topLevelBlockNodeNames() {
        let names = Set(nodes(category: .topLevelBlock).map(\.name))
        #expect(names == Self.topLevelBlockNames)
    }

    @Test("Oberflächen decken genau die Namensliste der Spec ab")
    func surfaceNodeNames() {
        let names = Set(nodes(category: .surface).map(\.name))
        #expect(names == Self.surfaceNames)
    }

    @Test("Layout deckt genau die Namensliste der Spec ab")
    func layoutNodeNames() {
        let names = Set(nodes(category: .layout).map(\.name))
        #expect(names == Self.layoutNames)
    }

    @Test("Elemente decken genau die Namensliste der Spec ab")
    func elementNodeNames() {
        let names = Set(nodes(category: .element).map(\.name))
        #expect(names == Self.elementNames)
    }

    @Test("Menüeinträge decken genau die Namensliste der Spec ab")
    func menuItemNodeNames() {
        let names = Set(nodes(category: .menuItem).map(\.name))
        #expect(names == Self.menuItemNames)
    }

    @Test("Einträge der Kommandozentrale decken genau die Namensliste der Spec ab")
    func commandCenterNodeNames() {
        let names = Set(nodes(category: .commandCenterItem).map(\.name))
        #expect(names == Self.commandCenterItemNames)
    }

    @Test("wm-Einstellungen decken genau die Namensliste der Spec ab")
    func wmSettingNodeNames() {
        let names = Set(nodes(category: .wmSetting).map(\.name))
        #expect(names == Self.wmSettingNames)
    }

    @Test("settings.kdl-Knoten decken genau die Namensliste der Spec ab")
    func settingsFileNodeNames() {
        let names = Set(nodes(category: .providerSettings).map(\.name))
        #expect(names == Self.settingsFileNames)
    }

    @Test("jeder Knotenname ist kebab-case")
    func namesAreKebabCase() {
        for node in BuiltinSchemaRegistry.allNodes {
            #expect(Self.isKebabCase(node.name), "\(node.name) is not kebab-case")
        }
    }

    @Test("jedes Argument und jede Property von Knoten und Aktionen ist kebab-case")
    func argumentAndPropertyNamesAreKebabCase() {
        let nodeNames = BuiltinSchemaRegistry.allNodes.flatMap { node in
            node.arguments.map { "\(node.name) \($0.name)" } + node.properties.map { "\(node.name) \($0.name)" }
        }
        let actionNames = (BuiltinSchemaRegistry.allActions + BuiltinSchemaRegistry.allProviders.flatMap(\.actions)).flatMap { action in
            action.arguments.map { "\(action.name) \($0.name)" } + action.properties.map { "\(action.name) \($0.name)" }
        }
        for entry in nodeNames + actionNames {
            let name = String(entry.split(separator: " ").last!)
            #expect(Self.isKebabCase(name), "\(entry) is not kebab-case")
        }
    }

    @Test("jedes Filter-Argument und jedes Feld von Providern und Ereignissen ist kebab-case")
    func filterArgumentsAndFieldsAreKebabCase() {
        for filter in BuiltinSchemaRegistry.allFilters {
            for argument in filter.arguments {
                #expect(Self.isKebabCase(argument.name), "\(filter.name) \(argument.name) is not kebab-case")
            }
        }
        let fields = BuiltinSchemaRegistry.allProviders.flatMap { provider in provider.fields.map { (provider.id, $0.path) } }
            + BuiltinSchemaRegistry.allEvents.flatMap { event in event.fields.map { (event.name, $0.path) } }
        for (owner, path) in fields {
            for segment in path where segment != "*" {
                #expect(Self.isKebabCase(segment), "\(owner) \(path.joined(separator: ".")) is not kebab-case")
            }
        }
    }

    @Test("jede Beschreibung in der Registry sagt mehr als ein Wort")
    func docsSayMoreThanOneWord() {
        var docs: [(String, String)] = []
        func add(_ owner: String, _ arguments: [ArgumentSchema], _ properties: [PropertySchema]) {
            docs += arguments.map { ("\(owner) \($0.name)", $0.doc) } + properties.map { ("\(owner) \($0.name)", $0.doc) }
        }
        for node in BuiltinSchemaRegistry.allNodes {
            docs.append((node.name, node.doc))
            add(node.name, node.arguments, node.properties)
        }
        let providerActions = BuiltinSchemaRegistry.allProviders.flatMap(\.actions)
        for action in BuiltinSchemaRegistry.allActions + providerActions {
            docs.append((action.name, action.doc))
            add(action.name, action.arguments, action.properties)
        }
        for filter in BuiltinSchemaRegistry.allFilters {
            docs.append((filter.name, filter.doc))
            add(filter.name, filter.arguments, [])
        }
        for provider in BuiltinSchemaRegistry.allProviders {
            docs.append((provider.id, provider.doc))
            add(provider.id, [], provider.settings)
            docs += provider.fields.map { ("\(provider.id) \($0.path.joined(separator: "."))", $0.doc) }
        }
        for event in BuiltinSchemaRegistry.allEvents {
            docs.append((event.name, event.doc))
            docs += event.fields.map { ("\(event.name) \($0.path.joined(separator: "."))", $0.doc) }
        }
        for (owner, doc) in docs {
            #expect(doc.split(separator: " ").count >= 2, "\(owner): \"\(doc)\" says too little")
        }
    }

    @Test("Apps startet nur apps.launch, eine zweite Aktion open-app gibt es nicht")
    func appsLaunchIsTheOnlyLauncher() {
        #expect(!BuiltinSchemaRegistry.allActions.contains { $0.name == "open-app" })
        #expect(BuiltinSchemaRegistry.allProviders.flatMap(\.actions).contains { $0.name == "apps.launch" })
    }

    @Test("Toasts zeigt toast.show neben toast.dismiss und osd.show, notify gibt es nicht mehr")
    func toastShowPairsWithDismiss() {
        let names = Set(BuiltinSchemaRegistry.allActions.map(\.name))
        #expect(names.isSuperset(of: ["toast.show", "toast.dismiss", "osd.show"]))
        #expect(!names.contains("notify"))
    }

    @Test("jede Property hat Typ und Vorgabe oder ist required")
    func propertiesHaveTypeAndDefaultOrRequired() {
        for node in BuiltinSchemaRegistry.allNodes {
            for property in node.properties {
                #expect(property.required || property.defaultValue != nil, "\(node.name).\(property.name) has neither a default nor is required")
            }
        }
    }

    @Test("contexts ist nie leer")
    func contextsNeverEmpty() {
        for node in BuiltinSchemaRegistry.allNodes {
            #expect(!node.contexts.isEmpty, "\(node.name) has no contexts")
        }
    }

    @Test("childContext ist genau bei Knoten mit Kindern gesetzt")
    func childContextMatchesNodesWithChildren() {
        let withChildContext = Set(BuiltinSchemaRegistry.allNodes.filter { $0.childContext != nil }.map(\.name))
        #expect(withChildContext == Self.nodesWithChildren)
    }

    @Test("merging überschreibt nicht still")
    func mergingDoesNotSilentlyOverwrite() {
        let base = SchemaRegistry.builtin
        let merged = base.merging(base)
        #expect(merged.nodes.count == base.nodes.count)
        #expect(BuiltinSchemaRegistry.nodeNameDuplicates.isEmpty)
    }

    @Test("gemeinsame Properties kommen aus einer geteilten Quelle")
    func sharedPropertiesAreReused() {
        let button = BuiltinSchemaRegistry.allNodes.first { $0.name == "button" }
        let panel = BuiltinSchemaRegistry.allNodes.first { $0.name == "panel" }
        #expect(button?.properties.contains(where: { $0.name == "id" }) == true)
        #expect(panel?.properties.contains(where: { $0.name == "id" }) == true)
        #expect(button?.properties.contains(where: { $0.name == "screen" }) == false)
        #expect(panel?.properties.contains(where: { $0.name == "screen" }) == true)
    }

    @Test("drag-value bleibt reserviert, fuse-group und fuse-fill gehören seit 0.2.1 zum Feature fusion")
    func reservedPropertiesAreExperimental() {
        let panel = BuiltinSchemaRegistry.allNodes.first { $0.name == "panel" }
        let fuseGroup = panel?.properties.first { $0.name == "fuse-group" }
        let fuseFill = panel?.properties.first { $0.name == "fuse-fill" }
        #expect(fuseGroup?.stability == .stable)
        #expect(fuseGroup?.feature == "fusion")
        #expect(fuseFill?.feature == "fusion")
        let button = BuiltinSchemaRegistry.allNodes.first { $0.name == "button" }
        let dragValue = button?.properties.first { $0.name == "drag-value" }
        #expect(dragValue?.stability == .experimental)
    }

    @Test("click-through erlaubt Bool oder \"auto\" mit passender Bool-Vorgabe")
    func clickThroughTypeMatchesDefault() {
        let panel = BuiltinSchemaRegistry.allNodes.first { $0.name == "panel" }
        let clickThrough = panel?.properties.first { $0.name == "click-through" }
        #expect(clickThrough?.type == .oneOf([.bool, .enumeration(["auto"])]))
        #expect(clickThrough?.defaultValue == .bool(false))
    }

    @Test("items ist ein eigener Zwischenknoten unter command-center")
    func commandCenterItemsWrapperExists() {
        let items = BuiltinSchemaRegistry.allNodes.first { $0.name == "items" }
        #expect(items?.contexts.contains(.commandCenterItems) == true)
        #expect(items?.childContext == .commandCenterItems)
    }
}
