enum MenuSources {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "app-dock",
            category: .menuItem,
            properties: [
                PropertySchema(name: "app", type: .value, required: true, doc: "App the menu is for."),
                PropertySchema(name: "fallback", type: .enumeration(["full", "commands"]), defaultValue: .string("full"), allowsExpression: false, doc: "Fallback when Apple's Dock does not know the app."),
            ],
            contexts: [.menu],
            doc: "The menu Apple's Dock shows for this app.",
            example: "source \"app-dock\" app=\"{app}\""
        ),
        NodeSchema(
            name: "app-commands",
            category: .menuItem,
            properties: [PropertySchema(name: "app", type: .value, required: true, doc: "App whose menu commands are listed.")],
            contexts: [.menu],
            doc: "Menu commands of an app via their keyboard shortcuts.",
            example: "source \"app-commands\" app=\"{app}\""
        ),
        NodeSchema(
            name: "app-windows",
            category: .menuItem,
            properties: [PropertySchema(name: "app", type: .value, required: true, doc: "App whose windows are listed.")],
            contexts: [.menu],
            doc: "Window list of an app across all Spaces.",
            example: "source \"app-windows\" app=\"{app}\""
        ),
    ]
}
