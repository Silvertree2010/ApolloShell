enum MenuNodes {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "item",
            category: .menuItem,
            arguments: [ArgumentSchema(name: "title", type: .string, doc: "Title of the item.")],
            properties: [
                PropertySchema(name: "icon", type: .string, defaultValue: .null, doc: "Symbol of the item."),
                PropertySchema(name: "checked", type: .bool, defaultValue: .bool(false), doc: "Checkmark on the item."),
                PropertySchema(name: "disabled", type: .bool, defaultValue: .bool(false), doc: "Item cannot be selected."),
                PropertySchema(name: "shortcut", type: .string, defaultValue: .null, allowsExpression: false, doc: "Display only, not an active keyboard shortcut."),
                PropertySchema(name: "alternate", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "Appears only while Option is held, in place of the previous item."),
            ],
            childContext: .actions,
            contexts: [.menu, .commandCenterItems],
            doc: "An item in a native menu.",
            example: "item \"Copy\" { clipboard.copy \"{system.full-name}\" }"
        ),
        NodeSchema(
            name: "separator",
            category: .menuItem,
            contexts: [.menu, .commandCenterItems],
            doc: "A separator in a native menu.",
            example: "separator"
        ),
        NodeSchema(
            name: "section",
            category: .menuItem,
            arguments: [ArgumentSchema(name: "title", type: .string, doc: "Heading of the section.")],
            contexts: [.menu],
            doc: "A heading in a native menu.",
            example: "section \"Recent\""
        ),
        NodeSchema(
            name: "submenu",
            category: .menuItem,
            arguments: [ArgumentSchema(name: "title", type: .string, doc: "Title of the submenu.")],
            childContext: .menu,
            contexts: [.menu, .commandCenterItems],
            doc: "A submenu with its own items.",
            example: "submenu \"More\" { item \"Details\" { } }"
        ),
        NodeSchema(
            name: "source",
            category: .menuItem,
            arguments: [ArgumentSchema(name: "kind", type: .identifier, allowsExpression: false, doc: "Name of the menu source from the registry.")],
            contexts: [.menu],
            doc: "Inserts items supplied by a menu source from the registry.",
            example: "source \"app-dock\" app=\"{app}\""
        ),
    ]
}
