enum MenuNodes {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "item",
            category: .menuItem,
            arguments: [ArgumentSchema(name: "title", type: .string, doc: "Titel des Eintrags.")],
            properties: [
                PropertySchema(name: "icon", type: .string, defaultValue: .null, doc: "Symbol des Eintrags."),
                PropertySchema(name: "checked", type: .bool, defaultValue: .bool(false), doc: "Häkchen am Eintrag."),
                PropertySchema(name: "disabled", type: .bool, defaultValue: .bool(false), doc: "Eintrag nicht auswählbar."),
                PropertySchema(name: "shortcut", type: .string, defaultValue: .null, allowsExpression: false, doc: "nur zur Anzeige, kein aktives Tastenkürzel."),
                PropertySchema(name: "alternate", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "erscheint nur bei gehaltener Wahltaste anstelle des vorigen Eintrags."),
            ],
            childContext: .actions,
            contexts: [.menu, .commandCenterItems],
            doc: "ein Eintrag in einem nativen Menü.",
            example: "item \"Copy\" { clipboard.copy \"{system.full-name}\" }"
        ),
        NodeSchema(
            name: "separator",
            category: .menuItem,
            contexts: [.menu, .commandCenterItems],
            doc: "eine Trennlinie in einem nativen Menü.",
            example: "separator"
        ),
        NodeSchema(
            name: "section",
            category: .menuItem,
            arguments: [ArgumentSchema(name: "title", type: .string, doc: "Überschrift des Abschnitts.")],
            contexts: [.menu],
            doc: "eine Überschrift in einem nativen Menü.",
            example: "section \"Recent\""
        ),
        NodeSchema(
            name: "submenu",
            category: .menuItem,
            arguments: [ArgumentSchema(name: "title", type: .string, doc: "Titel des Untermenüs.")],
            childContext: .menu,
            contexts: [.menu, .commandCenterItems],
            doc: "ein Untermenü mit eigenen Einträgen.",
            example: "submenu \"More\" { item \"Details\" { } }"
        ),
        NodeSchema(
            name: "source",
            category: .menuItem,
            arguments: [ArgumentSchema(name: "kind", type: .identifier, allowsExpression: false, doc: "Name der Menü-Quelle aus der Registry.")],
            contexts: [.menu],
            doc: "fügt Einträge ein, die eine Menü-Quelle der Registry liefert.",
            example: "source \"app-dock\" app=\"{app}\""
        ),
    ]
}
