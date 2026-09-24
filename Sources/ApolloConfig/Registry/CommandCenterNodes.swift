enum CommandCenterNodes {
    static let builtinNames: [String] = [
        "reload-config", "restart", "problems", "configs", "themes", "marketplace",
        "updates", "crash-reports", "login-item", "install-cli", "about", "quit",
    ]

    static let all: [NodeSchema] = [
        NodeSchema(
            name: "builtin",
            category: .commandCenterItem,
            arguments: [ArgumentSchema(name: "name", type: .enumeration(builtinNames), allowsExpression: false, doc: "Name eines eingebauten Eintrags der Kommandozentrale.")],
            contexts: [.commandCenterItems],
            doc: "fügt einen eingebauten Eintrag der Kommandozentrale ein.",
            example: "builtin \"reload-config\""
        ),
    ]
}
