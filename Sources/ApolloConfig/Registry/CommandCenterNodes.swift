enum CommandCenterNodes {
    static let builtinNames: [String] = [
        "reload-config", "restart", "problems", "configs", "themes", "marketplace",
        "updates", "crash-reports", "login-item", "install-cli", "about", "quit",
    ]

    static let all: [NodeSchema] = [
        NodeSchema(
            name: "items",
            category: .commandCenterItem,
            childContext: .commandCenterItems,
            contexts: [.commandCenterItems],
            doc: "Replaces the whole command center list.",
            example: "items { builtin \"reload-config\" }"
        ),
        NodeSchema(
            name: "builtin",
            category: .commandCenterItem,
            arguments: [ArgumentSchema(name: "name", type: .enumeration(builtinNames), allowsExpression: false, doc: "Name of a built-in command center entry.")],
            contexts: [.commandCenterItems],
            doc: "Inserts a built-in command center entry.",
            example: "builtin \"reload-config\""
        ),
    ]
}
