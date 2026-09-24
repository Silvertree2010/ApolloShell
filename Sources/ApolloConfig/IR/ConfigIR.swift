import ApolloBase
import ApolloKDL
import Foundation

public struct SurfaceIR: Sendable, Hashable {
    public var kind: String
    public var id: String
    public var properties: [String: CompiledValue]
    public var handlers: [HandlerIR]
    public var keyHandlers: [KeyHandlerIR]
    public var children: [ChildIR]
    public var span: SourceSpan

    public init(kind: String, id: String, properties: [String: CompiledValue] = [:], handlers: [HandlerIR] = [], keyHandlers: [KeyHandlerIR] = [], children: [ChildIR] = [], span: SourceSpan) {
        self.kind = kind
        self.id = id
        self.properties = properties
        self.handlers = handlers
        self.keyHandlers = keyHandlers
        self.children = children
        self.span = span
    }
}

public struct BindIR: Sendable, Hashable {
    public var id: String
    public var chord: CompiledValue
    public var when: CompiledValue?
    public var repeats: Bool
    public var actions: [ActionIR]
    public var span: SourceSpan

    public init(id: String, chord: CompiledValue, when: CompiledValue? = nil, repeats: Bool = false, actions: [ActionIR], span: SourceSpan) {
        self.id = id
        self.chord = chord
        self.when = when
        self.repeats = repeats
        self.actions = actions
        self.span = span
    }
}

public struct EventHandlerIR: Sendable, Hashable {
    public var event: String
    public var when: CompiledValue?
    public var actions: [ActionIR]
    public var span: SourceSpan

    public init(event: String, when: CompiledValue? = nil, actions: [ActionIR], span: SourceSpan) {
        self.event = event
        self.when = when
        self.actions = actions
        self.span = span
    }
}

public struct StyleRef: Sendable, Hashable {
    public var url: URL
    public var span: SourceSpan

    public init(url: URL, span: SourceSpan) {
        self.url = url
        self.span = span
    }
}

public struct BlockIR: Sendable, Hashable {
    public var name: String
    public var nodes: [KDLNode]
    public var compiled: [String: CompiledValue]

    public init(name: String, nodes: [KDLNode], compiled: [String: CompiledValue] = [:]) {
        self.name = name
        self.nodes = nodes
        self.compiled = compiled
    }
}

public struct ConfigIR: Sendable, Hashable {
    public var id: String
    public var root: URL
    public var files: [URL]
    public var styleSheets: [StyleRef]
    public var requiredVersion: String?
    public var requiredFeatures: [String]
    public var vars: [VarDecl]
    public var surfaces: [SurfaceIR]
    public var binds: [BindIR]
    public var events: [EventHandlerIR]
    public var defines: [String: DefineIR]
    public var blocks: [String: [BlockIR]]

    public init(
        id: String,
        root: URL,
        files: [URL] = [],
        styleSheets: [StyleRef] = [],
        requiredVersion: String? = nil,
        requiredFeatures: [String] = [],
        vars: [VarDecl] = [],
        surfaces: [SurfaceIR] = [],
        binds: [BindIR] = [],
        events: [EventHandlerIR] = [],
        defines: [String: DefineIR] = [:],
        blocks: [String: [BlockIR]] = [:]
    ) {
        self.id = id
        self.root = root
        self.files = files
        self.styleSheets = styleSheets
        self.requiredVersion = requiredVersion
        self.requiredFeatures = requiredFeatures
        self.vars = vars
        self.surfaces = surfaces
        self.binds = binds
        self.events = events
        self.defines = defines
        self.blocks = blocks
    }

    public func surface(_ id: String) -> SurfaceIR? {
        surfaces.first { $0.id == id }
    }
}

public struct SurfaceChange: Sendable, Hashable {
    public var added: [SurfaceIR]
    public var removed: [String]
    public var changed: [SurfaceIR]
    public var unchanged: [String]

    public init(added: [SurfaceIR] = [], removed: [String] = [], changed: [SurfaceIR] = [], unchanged: [String] = []) {
        self.added = added
        self.removed = removed
        self.changed = changed
        self.unchanged = unchanged
    }
}
