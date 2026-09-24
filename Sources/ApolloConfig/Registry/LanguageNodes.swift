enum LanguageNodes {
    private static let structural: Set<NodeContext> = [.surfaceBody, .elementBody, .actions, .menu, .commandCenterItems]

    static let all: [NodeSchema] = [
        NodeSchema(
            name: "include",
            category: .language,
            arguments: [ArgumentSchema(name: "path", type: .path, allowsExpression: false, doc: "Pfad relativ zur einbindenden Datei, oder builtin:/pkg:.")],
            properties: [PropertySchema(name: "optional", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "fehlende Datei ist kein Fehler.")],
            contexts: [.topLevel, .surfaceBody, .elementBody],
            doc: "bindet die obersten Knoten einer anderen Datei an dieser Stelle ein.",
            example: "include \"sidebar-modules.kdl\""
        ),
        NodeSchema(
            name: "let",
            category: .language,
            arguments: [],
            properties: [],
            contexts: [.topLevel, .surfaceBody, .elementBody],
            doc: "deklariert eine oder mehrere zur Ladezeit ausgewertete Konstanten.",
            example: "let gap=8 radius=12"
        ),
        NodeSchema(
            name: "var",
            category: .language,
            arguments: [
                ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name des Zustands."),
                ArgumentSchema(name: "default", type: .value, required: false, doc: "Vorgabewert."),
            ],
            properties: [
                PropertySchema(name: "persist", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "speichert den Wert in der Statusdatei der Config."),
                PropertySchema(name: "type", type: .enumeration(["string", "number", "bool", "list", "record", "any"]), defaultValue: .null, allowsExpression: false, doc: "Typ des Werts, Vorgabe aus dem Vorgabewert."),
                PropertySchema(name: "from", type: .value, defaultValue: .null, doc: "macht das var abgeleitet, nicht setzbar."),
            ],
            contexts: [.topLevel],
            doc: "deklariert Laufzeitzustand, auf Wunsch gespeichert.",
            example: "var launcher-query \"\""
        ),
        NodeSchema(
            name: "define",
            category: .language,
            arguments: [ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name des eigenen Bausteins, kebab-case, global eindeutig.")],
            properties: [PropertySchema(name: "override", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "ersetzt ein gleichnamiges define aus einer eingebundenen Datei.")],
            childContext: .elementBody,
            contexts: [.topLevel],
            doc: "beschreibt einen wiederverwendbaren Baustein.",
            example: "define \"labeled-icon\" { param \"icon\"; icon \"{icon}\" }"
        ),
        NodeSchema(
            name: "param",
            category: .language,
            arguments: [ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name des Parameters, im Rumpf als Ausdruck sichtbar.")],
            properties: [
                PropertySchema(name: "default", type: .value, defaultValue: .null, doc: "macht den Parameter optional."),
                PropertySchema(name: "type", type: .enumeration(["string", "number", "bool", "list", "record", "any"]), defaultValue: .null, allowsExpression: false, doc: "Typ des Parameters, Vorgabe any."),
            ],
            contexts: [.elementBody],
            doc: "deklariert einen Parameter eines define.",
            example: "param \"icon\""
        ),
        NodeSchema(
            name: "slot",
            category: .language,
            arguments: [ArgumentSchema(name: "name", type: .identifier, required: false, allowsExpression: false, doc: "Name des benannten Slots, sonst der unbenannte Slot.")],
            contexts: [.elementBody],
            doc: "Stelle, an der die Kinder eines use eingesetzt werden.",
            example: "slot"
        ),
        NodeSchema(
            name: "fill",
            category: .language,
            arguments: [ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name des Slots, der beim use befüllt wird.")],
            childContext: .elementBody,
            contexts: [.elementBody],
            doc: "füllt einen benannten Slot eines use.",
            example: "fill \"header\" { text \"Title\" }"
        ),
        NodeSchema(
            name: "use",
            category: .language,
            arguments: [ArgumentSchema(name: "name", type: .identifier, doc: "Name eines define, statisch oder als Ausdruck zur Laufzeit.")],
            properties: [],
            childContext: .elementBody,
            contexts: [.topLevel, .surfaceBody, .elementBody, .actions, .menu],
            doc: "setzt einen mit define beschriebenen Baustein ein.",
            example: "use \"labeled-icon\" icon=\"bar-power\""
        ),
        NodeSchema(
            name: "each",
            category: .language,
            arguments: [ArgumentSchema(name: "variable", type: .identifier, allowsExpression: false, doc: "Name der Schleifenvariable.")],
            properties: [
                PropertySchema(name: "in", type: .list, required: true, doc: "Ausdruck, der eine Liste liefert."),
                PropertySchema(name: "key", type: .value, defaultValue: .null, doc: "Schlüssel eines Eintrags, Vorgabe id oder Stelle."),
                PropertySchema(name: "index", type: .identifier, defaultValue: .null, allowsExpression: false, doc: "Name der Index-Schleifenvariable."),
            ],
            childContext: .elementBody,
            contexts: structural,
            doc: "erzeugt Kinder je Eintrag einer Liste.",
            example: "each app in=\"{apps.running}\" { text \"{app.name}\" }"
        ),
        NodeSchema(
            name: "when",
            category: .language,
            arguments: [ArgumentSchema(name: "condition", type: .bool, doc: "Bedingung, der Rumpf existiert nur, solange sie wahr ist.")],
            childContext: .elementBody,
            contexts: structural,
            doc: "erzeugt Kinder, solange eine Bedingung wahr ist.",
            example: "when \"{battery.present}\" { text \"{battery.percent}\" }"
        ),
        NodeSchema(
            name: "else",
            category: .language,
            childContext: .elementBody,
            contexts: structural,
            doc: "Gegenzweig eines direkt vorangehenden when oder feature.",
            example: "else { text \"No battery\" }"
        ),
        NodeSchema(
            name: "switch",
            category: .language,
            arguments: [ArgumentSchema(name: "subject", type: .value, doc: "Ausdruck, dessen Wert die Zweige auswählt.")],
            childContext: .elementBody,
            contexts: structural,
            doc: "wählt einen von mehreren Zweigen nach Gleichheit aus.",
            example: "switch \"{var.tab}\" { case \"a\" { text \"A\" } }"
        ),
        NodeSchema(
            name: "case",
            category: .language,
            arguments: [ArgumentSchema(name: "values", type: .value, variadic: true, doc: "ein oder mehrere Werte, die diesen Zweig auswählen.")],
            childContext: .elementBody,
            contexts: [.elementBody],
            doc: "Zweig eines switch, gilt beim ersten passenden Wert.",
            example: "case \"a\" \"b\" { text \"A or B\" }"
        ),
        NodeSchema(
            name: "default",
            category: .language,
            childContext: .elementBody,
            contexts: [.elementBody],
            doc: "Zweig eines switch, der greift, wenn kein case passt.",
            example: "default { text \"Unknown\" }"
        ),
        NodeSchema(
            name: "feature",
            category: .language,
            arguments: [ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name des benötigten Features.")],
            childContext: .elementBody,
            contexts: [.topLevel, .surfaceBody, .elementBody, .actions, .menu, .commandCenterItems],
            doc: "beschränkt den Rumpf auf Shells, die dieses Feature kennen.",
            example: "feature \"status-items\" { text \"New\" }"
        ),
        NodeSchema(
            name: "disable",
            category: .language,
            properties: [
                PropertySchema(name: "surface", type: .identifier, defaultValue: .null, allowsExpression: false, doc: "Kennung einer Oberfläche, die abgeschaltet wird."),
                PropertySchema(name: "bind", type: .keyChord, defaultValue: .null, allowsExpression: false, doc: "Tastenkombination, die abgeschaltet wird."),
                PropertySchema(name: "on", type: .identifier, defaultValue: .null, allowsExpression: false, doc: "Ereignisname, dessen Handler abgeschaltet werden."),
            ],
            contexts: [.topLevel],
            doc: "schaltet eine eingebundene Oberfläche, ein bind oder einen Handler ab.",
            example: "disable bind=\"alt+space\""
        ),
        NodeSchema(
            name: "require",
            category: .language,
            arguments: [ArgumentSchema(name: "version", type: .string, required: false, allowsExpression: false, doc: "Mindestversion der Shell.")],
            properties: [PropertySchema(name: "feature", type: .identifier, defaultValue: .null, allowsExpression: false, doc: "Name eines benötigten Features.")],
            contexts: [.topLevel],
            doc: "bricht das Laden sauber ab, wenn die Shell zu alt ist oder ein Feature fehlt.",
            example: "require \"0.2.0\""
        ),
        NodeSchema(
            name: "style",
            category: .language,
            arguments: [ArgumentSchema(name: "path", type: .path, allowsExpression: false, doc: "Pfad zu einer Stylesheet-Datei.")],
            contexts: [.topLevel],
            doc: "bindet ein Stylesheet ein.",
            example: "style \"theme.css\""
        ),
    ]
}
