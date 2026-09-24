import ApolloBase

public struct VarDecl: Sendable, Hashable {
    public var name: String
    public var type: ValueType
    public var defaultValue: ValueTemplate
    public var persist: Bool
    public var derived: CompiledValue?
    public var span: SourceSpan

    public init(name: String, type: ValueType, defaultValue: ValueTemplate, persist: Bool, derived: CompiledValue?, span: SourceSpan) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.persist = persist
        self.derived = derived
        self.span = span
    }
}
