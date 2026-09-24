import Foundation

public enum Stability: String, Sendable, Hashable {
    case stable, experimental
}

public indirect enum ValueType: Sendable, Hashable {
    case any, string, number, bool, duration, keyChord, path, identifier, value, actions, list, record
    case enumeration([String])
}

public struct PropertySchema: Sendable, Hashable {
    public var name: String
    public var type: ValueType
    public var required: Bool
    public var defaultValue: Value?
    public var allowsExpression: Bool
    public var doc: String
    public var stability: Stability
    public var feature: String

    public init(
        name: String,
        type: ValueType,
        required: Bool = false,
        defaultValue: Value? = nil,
        allowsExpression: Bool = true,
        doc: String,
        stability: Stability = .stable,
        feature: String = "core"
    ) {
        self.name = name
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
        self.allowsExpression = allowsExpression
        self.doc = doc
        self.stability = stability
        self.feature = feature
    }
}

public struct ArgumentSchema: Sendable, Hashable {
    public var name: String
    public var type: ValueType
    public var required: Bool
    public var variadic: Bool
    public var allowsExpression: Bool
    public var doc: String

    public init(
        name: String,
        type: ValueType,
        required: Bool = true,
        variadic: Bool = false,
        allowsExpression: Bool = true,
        doc: String
    ) {
        self.name = name
        self.type = type
        self.required = required
        self.variadic = variadic
        self.allowsExpression = allowsExpression
        self.doc = doc
    }
}

public enum NodeContext: String, Sendable, Hashable {
    case topLevel, surfaceBody, elementBody, actions, menu, commandCenterItems, wmBlock, settingsFile, stateFile
}

public struct NodeSchema: Sendable, Hashable {
    public var name: String
    public var category: NodeCategory
    public var feature: String
    public var stability: Stability
    public var arguments: [ArgumentSchema]
    public var properties: [PropertySchema]
    public var handlers: [String]
    public var childContext: NodeContext?
    public var contexts: Set<NodeContext>
    public var doc: String
    public var example: String

    public init(
        name: String,
        category: NodeCategory,
        feature: String = "core",
        stability: Stability = .stable,
        arguments: [ArgumentSchema] = [],
        properties: [PropertySchema] = [],
        handlers: [String] = [],
        childContext: NodeContext? = nil,
        contexts: Set<NodeContext>,
        doc: String,
        example: String
    ) {
        self.name = name
        self.category = category
        self.feature = feature
        self.stability = stability
        self.arguments = arguments
        self.properties = properties
        self.handlers = handlers
        self.childContext = childContext
        self.contexts = contexts
        self.doc = doc
        self.example = example
    }
}

public enum NodeCategory: String, Sendable, Hashable {
    case language, surface, layout, element, action, topLevelBlock, menuItem, commandCenterItem, wmSetting, providerSettings
}

public enum UpdateKind: Sendable, Hashable {
    case push, poll(seconds: Double), tick, once
}

public struct FieldSchema: Sendable, Hashable {
    public var path: [String]
    public var type: ValueType
    public var nullable: Bool
    public var update: UpdateKind
    public var doc: String

    public init(path: [String], type: ValueType, nullable: Bool = false, update: UpdateKind, doc: String) {
        self.path = path
        self.type = type
        self.nullable = nullable
        self.update = update
        self.doc = doc
    }
}

public struct ActionSchema: Sendable, Hashable {
    public var name: String
    public var arguments: [ArgumentSchema]
    public var properties: [PropertySchema]
    public var acceptsChildren: Bool
    public var waits: Bool
    public var startsProgramsOrControlsApps: Bool
    public var feature: String
    public var stability: Stability
    public var doc: String

    public init(
        name: String,
        arguments: [ArgumentSchema] = [],
        properties: [PropertySchema] = [],
        acceptsChildren: Bool = false,
        waits: Bool = false,
        startsProgramsOrControlsApps: Bool = false,
        feature: String = "core",
        stability: Stability = .stable,
        doc: String
    ) {
        self.name = name
        self.arguments = arguments
        self.properties = properties
        self.acceptsChildren = acceptsChildren
        self.waits = waits
        self.startsProgramsOrControlsApps = startsProgramsOrControlsApps
        self.feature = feature
        self.stability = stability
        self.doc = doc
    }
}

public struct EventSchema: Sendable, Hashable {
    public var name: String
    public var fields: [FieldSchema]
    public var feature: String
    public var doc: String

    public init(name: String, fields: [FieldSchema] = [], feature: String = "core", doc: String) {
        self.name = name
        self.fields = fields
        self.feature = feature
        self.doc = doc
    }
}

public struct ProviderSchema: Sendable, Hashable {
    public var id: String
    public var feature: String
    public var stability: Stability
    public var fields: [FieldSchema]
    public var actions: [ActionSchema]
    public var events: [EventSchema]
    public var settings: [PropertySchema]
    public var permissions: [String]
    public var doc: String

    public init(
        id: String,
        feature: String = "core",
        stability: Stability = .stable,
        fields: [FieldSchema] = [],
        actions: [ActionSchema] = [],
        events: [EventSchema] = [],
        settings: [PropertySchema] = [],
        permissions: [String] = [],
        doc: String
    ) {
        self.id = id
        self.feature = feature
        self.stability = stability
        self.fields = fields
        self.actions = actions
        self.events = events
        self.settings = settings
        self.permissions = permissions
        self.doc = doc
    }
}

public struct FilterSchema: Sendable, Hashable {
    public var name: String
    public var arguments: [ArgumentSchema]
    public var feature: String
    public var stability: Stability
    public var doc: String

    public init(name: String, arguments: [ArgumentSchema] = [], feature: String = "core", stability: Stability = .stable, doc: String) {
        self.name = name
        self.arguments = arguments
        self.feature = feature
        self.stability = stability
        self.doc = doc
    }
}

public struct FeatureSchema: Sendable, Hashable {
    public var name: String
    public var since: String

    public init(name: String, since: String) {
        self.name = name
        self.since = since
    }
}

public struct ContextRootSchema: Sendable, Hashable {
    public var name: String
    public var fields: [FieldSchema]
    public var validIn: Set<String>

    public init(name: String, fields: [FieldSchema] = [], validIn: Set<String>) {
        self.name = name
        self.fields = fields
        self.validIn = validIn
    }
}

public struct SchemaRegistry: Sendable {
    public var nodes: [String: NodeSchema]
    public var actions: [String: ActionSchema]
    public var providers: [String: ProviderSchema]
    public var filters: [String: FilterSchema]
    public var events: [String: EventSchema]
    public var menuSources: [String: NodeSchema]
    public var contextRoots: [String: ContextRootSchema]
    public var features: [String: FeatureSchema]
    public var reservedProviderNames: Set<String>
    public var fixedRoots: Set<String>

    public init(
        nodes: [String: NodeSchema] = [:],
        actions: [String: ActionSchema] = [:],
        providers: [String: ProviderSchema] = [:],
        filters: [String: FilterSchema] = [:],
        events: [String: EventSchema] = [:],
        menuSources: [String: NodeSchema] = [:],
        contextRoots: [String: ContextRootSchema] = [:],
        features: [String: FeatureSchema] = [:],
        reservedProviderNames: Set<String> = [],
        fixedRoots: Set<String> = []
    ) {
        self.nodes = nodes
        self.actions = actions
        self.providers = providers
        self.filters = filters
        self.events = events
        self.menuSources = menuSources
        self.contextRoots = contextRoots
        self.features = features
        self.reservedProviderNames = reservedProviderNames
        self.fixedRoots = fixedRoots
    }

    public static let builtin = BuiltinSchemaRegistry.make()

    public func node(_ name: String) -> NodeSchema? {
        nodes[name]
    }

    public func action(_ name: String) -> ActionSchema? {
        actions[name]
    }

    public func merging(_ other: SchemaRegistry) -> SchemaRegistry {
        SchemaRegistry(
            nodes: nodes.merging(other.nodes, uniquingKeysWith: { _, new in new }),
            actions: actions.merging(other.actions, uniquingKeysWith: { _, new in new }),
            providers: providers.merging(other.providers, uniquingKeysWith: { _, new in new }),
            filters: filters.merging(other.filters, uniquingKeysWith: { _, new in new }),
            events: events.merging(other.events, uniquingKeysWith: { _, new in new }),
            menuSources: menuSources.merging(other.menuSources, uniquingKeysWith: { _, new in new }),
            contextRoots: contextRoots.merging(other.contextRoots, uniquingKeysWith: { _, new in new }),
            features: features.merging(other.features, uniquingKeysWith: { _, new in new }),
            reservedProviderNames: reservedProviderNames.union(other.reservedProviderNames),
            fixedRoots: fixedRoots.union(other.fixedRoots)
        )
    }
}

enum RegistryBuilder {
    static func dictionary<T>(_ items: [T], name: (T) -> String) -> (dict: [String: T], duplicates: [String]) {
        var dict: [String: T] = [:]
        var duplicates: [String] = []
        for item in items {
            let key = name(item)
            if dict[key] != nil {
                duplicates.append(key)
            }
            dict[key] = item
        }
        return (dict, duplicates)
    }
}
