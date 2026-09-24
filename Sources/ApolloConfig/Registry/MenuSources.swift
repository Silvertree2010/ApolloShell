enum MenuSources {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "app-dock",
            category: .menuItem,
            properties: [
                PropertySchema(name: "app", type: .value, required: true, doc: "App, für die das Menü gilt."),
                PropertySchema(name: "fallback", type: .enumeration(["full", "commands"]), defaultValue: .string("full"), allowsExpression: false, doc: "Rückfall, wenn Apples Dock die App nicht kennt."),
            ],
            contexts: [.menu],
            doc: "das Menü, das Apples Dock für diese App zeigt.",
            example: "source \"app-dock\" app=\"{app}\""
        ),
        NodeSchema(
            name: "app-commands",
            category: .menuItem,
            properties: [PropertySchema(name: "app", type: .value, required: true, doc: "App, deren Menübefehle gelistet werden.")],
            contexts: [.menu],
            doc: "Menübefehle einer App über ihre Tastenkürzel.",
            example: "source \"app-commands\" app=\"{app}\""
        ),
        NodeSchema(
            name: "app-windows",
            category: .menuItem,
            properties: [PropertySchema(name: "app", type: .value, required: true, doc: "App, deren Fenster gelistet werden.")],
            contexts: [.menu],
            doc: "Fensterliste einer App über alle Spaces.",
            example: "source \"app-windows\" app=\"{app}\""
        ),
    ]
}
