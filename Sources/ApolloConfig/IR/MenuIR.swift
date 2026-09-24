public struct MenuIR: Sendable, Hashable {
    public var properties: [String: CompiledValue]
    public var items: [MenuItemIR]

    public init(properties: [String: CompiledValue] = [:], items: [MenuItemIR]) {
        self.properties = properties
        self.items = items
    }
}

public indirect enum MenuItemIR: Sendable, Hashable {
    case item(title: CompiledValue, properties: [String: CompiledValue], actions: [ActionIR])
    case separator
    case section(CompiledValue)
    case submenu(title: CompiledValue, items: [MenuItemIR])
    case source(kind: String, properties: [String: CompiledValue])
    case each(variable: String, index: String?, list: CompiledValue, key: CompiledValue?, body: [MenuItemIR])
    case when(condition: CompiledValue, then: [MenuItemIR], otherwise: [MenuItemIR])
}
