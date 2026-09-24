import ApolloBase

public struct ElementIR: Sendable, Hashable {
    public var kind: String
    public var key: String
    public var arguments: [CompiledValue]
    public var properties: [String: CompiledValue]
    public var handlers: [HandlerIR]
    public var keyHandlers: [KeyHandlerIR]
    public var accessibilityActions: [AccessibilityActionIR]
    public var menu: MenuIR?
    public var slots: [String: [ChildIR]]
    public var children: [ChildIR]
    public var span: SourceSpan

    public init(
        kind: String,
        key: String,
        arguments: [CompiledValue] = [],
        properties: [String: CompiledValue] = [:],
        handlers: [HandlerIR] = [],
        keyHandlers: [KeyHandlerIR] = [],
        accessibilityActions: [AccessibilityActionIR] = [],
        menu: MenuIR? = nil,
        slots: [String: [ChildIR]] = [:],
        children: [ChildIR] = [],
        span: SourceSpan
    ) {
        self.kind = kind
        self.key = key
        self.arguments = arguments
        self.properties = properties
        self.handlers = handlers
        self.keyHandlers = keyHandlers
        self.accessibilityActions = accessibilityActions
        self.menu = menu
        self.slots = slots
        self.children = children
        self.span = span
    }

    public var idTemplate: CompiledValue? {
        properties["id"]
    }
}

public indirect enum ChildIR: Sendable, Hashable {
    case element(ElementIR)
    case each(EachIR)
    case when(WhenIR)
    case switchOn(SwitchIR)
    case dynamicUse(DynamicUseIR)

    public var key: String {
        switch self {
        case .element(let element): return element.key
        case .each(let each): return each.key
        case .when(let when): return when.key
        case .switchOn(let switchIR): return switchIR.key
        case .dynamicUse(let use): return use.key
        }
    }
}

public struct EachIR: Sendable, Hashable {
    public var key: String
    public var variable: String
    public var indexVariable: String?
    public var list: CompiledValue
    public var itemKey: CompiledValue?
    public var body: [ChildIR]

    public init(key: String, variable: String, indexVariable: String? = nil, list: CompiledValue, itemKey: CompiledValue? = nil, body: [ChildIR]) {
        self.key = key
        self.variable = variable
        self.indexVariable = indexVariable
        self.list = list
        self.itemKey = itemKey
        self.body = body
    }
}

public struct WhenIR: Sendable, Hashable {
    public var key: String
    public var condition: CompiledValue
    public var then: [ChildIR]
    public var otherwise: [ChildIR]

    public init(key: String, condition: CompiledValue, then: [ChildIR], otherwise: [ChildIR] = []) {
        self.key = key
        self.condition = condition
        self.then = then
        self.otherwise = otherwise
    }
}

public struct SwitchIR: Sendable, Hashable {
    public var key: String
    public var subject: CompiledValue
    public var cases: [SwitchCaseIR]
    public var otherwise: [ChildIR]

    public init(key: String, subject: CompiledValue, cases: [SwitchCaseIR], otherwise: [ChildIR] = []) {
        self.key = key
        self.subject = subject
        self.cases = cases
        self.otherwise = otherwise
    }
}

public struct SwitchCaseIR: Sendable, Hashable {
    public var values: [CompiledValue]
    public var body: [ChildIR]

    public init(values: [CompiledValue], body: [ChildIR]) {
        self.values = values
        self.body = body
    }
}

public struct DynamicUseIR: Sendable, Hashable {
    public var key: String
    public var name: CompiledValue
    public var arguments: [String: CompiledValue]
    public var slots: [String: [ChildIR]]

    public init(key: String, name: CompiledValue, arguments: [String: CompiledValue] = [:], slots: [String: [ChildIR]] = [:]) {
        self.key = key
        self.name = name
        self.arguments = arguments
        self.slots = slots
    }
}

public struct DefineIR: Sendable, Hashable {
    public var name: String
    public var parameters: [ParameterIR]
    public var body: [ChildIR]
    public var span: SourceSpan

    public init(name: String, parameters: [ParameterIR] = [], body: [ChildIR], span: SourceSpan) {
        self.name = name
        self.parameters = parameters
        self.body = body
        self.span = span
    }
}

public struct ParameterIR: Sendable, Hashable {
    public var name: String
    public var type: ValueType
    public var defaultValue: ValueTemplate?

    public init(name: String, type: ValueType = .any, defaultValue: ValueTemplate? = nil) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
    }
}
