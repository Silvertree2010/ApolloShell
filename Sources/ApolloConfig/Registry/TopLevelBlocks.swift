enum TopLevelBlocks {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "bind",
            category: .topLevelBlock,
            arguments: [ArgumentSchema(name: "chord", type: .keyChord, doc: "Tastenkombination, darf ein Ausdruck sein.")],
            properties: [
                PropertySchema(name: "id", type: .identifier, defaultValue: .null, doc: "Kennung für disable, override und Konfliktmeldungen, Vorgabe die Kombination."),
                PropertySchema(name: "repeat", type: .bool, defaultValue: .bool(false), doc: "löst aus, solange die Kombination gehalten wird."),
                PropertySchema(name: "when", type: .bool, defaultValue: .null, doc: "bind ist nur aktiv, solange der Ausdruck wahr ist."),
                PropertySchema(name: "override", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "erlaubt eine zweite statisch gleiche Kombination."),
            ],
            childContext: .actions,
            contexts: [.topLevel],
            doc: "meldet ein globales Tastenkürzel an.",
            example: "bind \"alt+space\" { toggle \"launcher\" }"
        ),
        NodeSchema(
            name: "on",
            category: .topLevelBlock,
            arguments: [ArgumentSchema(name: "event", type: .identifier, allowsExpression: false, doc: "Name des Ereignisses.")],
            properties: [PropertySchema(name: "when", type: .bool, defaultValue: .null, doc: "filtert, wann der Handler läuft.")],
            childContext: .actions,
            contexts: [.topLevel],
            doc: "reagiert auf ein Ereignis der Shell oder eines Providers.",
            example: "on \"audio.volume-changed\" { osd.show \"volume\" }"
        ),
        NodeSchema(
            name: "poll",
            category: .topLevelBlock,
            feature: "script-sources",
            arguments: [ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name der Quelle unter poll.<name>.")],
            properties: [
                PropertySchema(name: "command", type: .string, required: true, allowsExpression: false, doc: "Befehl, ausgeführt über /bin/sh -c.", stability: .stable, feature: "script-sources"),
                PropertySchema(name: "interval", type: .duration, defaultValue: .string("5s"), allowsExpression: false, doc: "Abstand zwischen zwei Läufen.", feature: "script-sources"),
                PropertySchema(name: "format", type: .enumeration(["text", "json", "lines"]), defaultValue: .string("text"), allowsExpression: false, doc: "wie die Ausgabe gelesen wird.", feature: "script-sources"),
                PropertySchema(name: "initial", type: .value, defaultValue: .null, doc: "Wert bis zum ersten Ergebnis.", feature: "script-sources"),
                PropertySchema(name: "when", type: .bool, defaultValue: .null, doc: "die Quelle läuft nur, solange der Ausdruck wahr ist.", feature: "script-sources"),
                PropertySchema(name: "timeout", type: .duration, defaultValue: .string("10s"), allowsExpression: false, doc: "danach wird der Prozess beendet.", feature: "script-sources"),
            ],
            contexts: [.topLevel],
            doc: "liest wiederholt die Ausgabe eines Befehls als Datenquelle.",
            example: "poll \"vpn\" command=\"scutil --nc status Mullvad | head -1\""
        ),
        NodeSchema(
            name: "listen",
            category: .topLevelBlock,
            feature: "script-sources",
            arguments: [ArgumentSchema(name: "name", type: .identifier, allowsExpression: false, doc: "Name der Quelle unter listen.<name>.")],
            properties: [
                PropertySchema(name: "command", type: .string, required: true, allowsExpression: false, doc: "Befehl, dessen Ausgabe zeilenweise gelesen wird.", feature: "script-sources"),
                PropertySchema(name: "format", type: .enumeration(["text", "json", "lines"]), defaultValue: .string("text"), allowsExpression: false, doc: "wie jede Zeile gelesen wird.", feature: "script-sources"),
                PropertySchema(name: "initial", type: .value, defaultValue: .null, doc: "Wert bis zum ersten Ergebnis.", feature: "script-sources"),
                PropertySchema(name: "when", type: .bool, defaultValue: .null, doc: "die Quelle läuft nur, solange der Ausdruck wahr ist.", feature: "script-sources"),
            ],
            contexts: [.topLevel],
            doc: "liest eine dauerhaft laufende Datenquelle aus einem Prozess.",
            example: "listen \"watch-space\" command=\"~/bin/watch-space.sh\" format=\"json\""
        ),
        NodeSchema(
            name: "wm",
            category: .topLevelBlock,
            feature: "wm",
            properties: [PropertySchema(name: "enabled", type: .bool, defaultValue: .bool(false), doc: "schaltet den Fenstermanager ein.")],
            childContext: .wmBlock,
            contexts: [.topLevel],
            doc: "beschreibt den Tiling-Fenstermanager.",
            example: "wm enabled=#true { layout \"dwindle\" }"
        ),
        NodeSchema(
            name: "command-center",
            category: .topLevelBlock,
            properties: [PropertySchema(name: "visible", type: .bool, defaultValue: .bool(true), doc: "versteckt das Symbol der Kommandozentrale.")],
            childContext: .commandCenterItems,
            contexts: [.topLevel],
            doc: "passt die Einträge des nativen Statusmenüs an.",
            example: "command-center { builtin \"reload-config\" }"
        ),
        NodeSchema(
            name: "marketplace",
            category: .topLevelBlock,
            properties: [PropertySchema(name: "enabled", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "schaltet den Marketplace ein oder aus.")],
            contexts: [.topLevel],
            doc: "schaltet den eingebauten Marketplace ein oder aus.",
            example: "marketplace enabled=#false"
        ),
    ]
}
