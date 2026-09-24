import ApolloBase

public struct HandlerIR: Sendable, Hashable {
    public var name: String
    public var properties: [String: CompiledValue]
    public var actions: [ActionIR]
    public var span: SourceSpan

    public init(name: String, properties: [String: CompiledValue] = [:], actions: [ActionIR], span: SourceSpan) {
        self.name = name
        self.properties = properties
        self.actions = actions
        self.span = span
    }
}

public indirect enum ActionIR: Sendable, Hashable {
    case call(ActionCallIR)
    case when(condition: CompiledValue, then: [ActionIR], otherwise: [ActionIR])
    case switchOn(subject: CompiledValue, cases: [ActionCaseIR], otherwise: [ActionIR])
    case each(variable: String, index: String?, list: CompiledValue, body: [ActionIR])
    case repeatBlock(count: CompiledValue, body: [ActionIR])
}

public struct ActionCallIR: Sendable, Hashable {
    public var name: String
    public var arguments: [CompiledValue]
    public var properties: [String: CompiledValue]
    public var children: [ValueTemplate]
    public var span: SourceSpan

    public init(name: String, arguments: [CompiledValue] = [], properties: [String: CompiledValue] = [:], children: [ValueTemplate] = [], span: SourceSpan) {
        self.name = name
        self.arguments = arguments
        self.properties = properties
        self.children = children
        self.span = span
    }
}

public struct ActionCaseIR: Sendable, Hashable {
    public var values: [CompiledValue]
    public var body: [ActionIR]

    public init(values: [CompiledValue], body: [ActionIR]) {
        self.values = values
        self.body = body
    }
}

public struct KeyHandlerIR: Sendable, Hashable {
    public var chord: String
    public var actions: [ActionIR]

    public init(chord: String, actions: [ActionIR]) {
        self.chord = chord
        self.actions = actions
    }
}

public struct AccessibilityActionIR: Sendable, Hashable {
    public var title: CompiledValue
    public var actions: [ActionIR]

    public init(title: CompiledValue, actions: [ActionIR]) {
        self.title = title
        self.actions = actions
    }
}
