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
        "include", "let", "var", "define", "param", "slot", "fill", "use",
        "each", "when", "else", "switch", "case", "default", "feature", "disable", "require", "style", "filter",
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
        "define", "fill", "use", "each", "when", "else", "switch", "case", "default", "feature",
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

    @Test("reservierte Properties sind experimental markiert")
    func reservedPropertiesAreExperimental() {
        let panel = BuiltinSchemaRegistry.allNodes.first { $0.name == "panel" }
        let fuseGroup = panel?.properties.first { $0.name == "fuse-group" }
        #expect(fuseGroup?.stability == .experimental)
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
