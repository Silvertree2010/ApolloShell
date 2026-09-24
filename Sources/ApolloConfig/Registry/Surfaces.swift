enum Surfaces {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "panel",
            category: .surface,
            arguments: [CommonProperties.idArgument],
            properties: CommonProperties.surfaceProperties + [
                PropertySchema(name: "reserve", type: .bool, defaultValue: .bool(false), doc: "hält App-Fenster aus dem Streifen der Oberfläche, nur bei left/right/top/bottom."),
            ],
            handlers: CommonProperties.surfaceHandlers,
            childContext: .surfaceBody,
            contexts: [.topLevel],
            doc: "dauerhaft sichtbare Oberfläche wie Leisten, Docks, Desktop-Widgets.",
            example: "panel \"sidebar\" anchor=\"left\" { }"
        ),
        NodeSchema(
            name: "popup",
            category: .surface,
            arguments: [CommonProperties.idArgument],
            properties: CommonProperties.surfaceProperties + [
                PropertySchema(name: "motion", type: .enumeration(["slide", "grow", "fade", "none"]), defaultValue: .null, doc: "Auf- und Zugehen."),
                PropertySchema(name: "scrim", type: .number, defaultValue: .null, doc: "dunkelt den Bildschirm dahinter ab, 0…1."),
                PropertySchema(name: "close-on", type: .string, defaultValue: .string("outside-click escape focus-loss"), doc: "Liste, was das Popup schliesst."),
                PropertySchema(name: "hover-edge", type: .bool, defaultValue: .bool(false), doc: "öffnet, wenn der Zeiger die verankerte Kante berührt."),
                PropertySchema(name: "hover-margin", type: .number, defaultValue: .number(0), allowsExpression: false, doc: "Randzone in pt, in der das Popup beim Hover offen bleibt."),
                PropertySchema(name: "hover-gap", type: .number, defaultValue: .number(0), allowsExpression: false, doc: "Abstand zur Ecke ohne Auslöser, nur bei Eck-Ankern."),
                PropertySchema(name: "group", type: .string, defaultValue: .null, doc: "schliesst andere Popups derselben Gruppe."),
                PropertySchema(name: "attach", type: .string, defaultValue: .null, doc: "neben einem Element einer anderen Oberfläche statt an einer Kante."),
                PropertySchema(name: "side", type: .enumeration(["top", "bottom", "left", "right"]), defaultValue: .string("right"), doc: "Seite bei attach."),
            ],
            handlers: CommonProperties.surfaceHandlers,
            childContext: .surfaceBody,
            contexts: [.topLevel],
            doc: "geht auf Aktion auf und zu, etwa Dashboard oder Launcher.",
            example: "popup \"launcher\" anchor=\"center\" { }"
        ),
        NodeSchema(
            name: "overlay",
            category: .surface,
            arguments: [CommonProperties.idArgument],
            properties: CommonProperties.surfaceProperties,
            handlers: CommonProperties.surfaceHandlers,
            childContext: .surfaceBody,
            contexts: [.topLevel],
            doc: "deckt den ganzen Bildschirm ab, standardmässig durchklickbar.",
            example: "overlay \"screen-corners\" { }"
        ),
        NodeSchema(
            name: "toast",
            category: .surface,
            arguments: [ArgumentSchema(name: "style", type: .identifier, doc: "Stilname, Ziel der notify-Aktion.")],
            properties: CommonProperties.surfaceProperties + [
                PropertySchema(name: "max", type: .number, defaultValue: .number(4), allowsExpression: false, doc: "gleichzeitig sichtbare Meldungen."),
                PropertySchema(name: "duration", type: .duration, defaultValue: .string("5s"), doc: "Anzeigedauer."),
                PropertySchema(name: "newest", type: .enumeration(["last", "first"]), defaultValue: .string("last"), doc: "wo die neueste Meldung erscheint."),
            ],
            handlers: CommonProperties.surfaceHandlers,
            childContext: .surfaceBody,
            contexts: [.topLevel],
            doc: "legt fest, wie eine Benachrichtigung der Aktion notify aussieht.",
            example: "toast \"default\" { }"
        ),
        NodeSchema(
            name: "osd",
            category: .surface,
            arguments: [CommonProperties.idArgument],
            properties: CommonProperties.surfaceProperties + [
                PropertySchema(name: "timeout", type: .duration, defaultValue: .string("2s"), doc: "Anzeigedauer."),
                PropertySchema(name: "motion", type: .enumeration(["slide", "grow", "fade", "none"]), defaultValue: .string("slide"), doc: "Auf- und Zugehen."),
            ],
            handlers: CommonProperties.surfaceHandlers,
            childContext: .surfaceBody,
            contexts: [.topLevel],
            doc: "kurze Rückmeldung wie eine Lautstärkeanzeige.",
            example: "osd \"volume\" { }"
        ),
        NodeSchema(
            name: "window",
            category: .surface,
            arguments: [CommonProperties.idArgument],
            properties: CommonProperties.surfaceProperties + [
                PropertySchema(name: "title", type: .string, defaultValue: .string(""), doc: "Fenstertitel."),
                PropertySchema(name: "title-visible", type: .bool, defaultValue: .bool(true), doc: "ob die Titelleiste den Titel zeigt."),
                PropertySchema(name: "resizable", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "ob sich die Grösse ändern lässt."),
                PropertySchema(name: "closable", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "ob das Fenster schliessbar ist."),
                PropertySchema(name: "miniaturizable", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "ob das Fenster minimierbar ist."),
                PropertySchema(name: "autosave", type: .string, defaultValue: .null, allowsExpression: false, doc: "merkt sich Grösse und Lage unter diesem Namen."),
            ],
            handlers: CommonProperties.surfaceHandlers,
            childContext: .surfaceBody,
            contexts: [.topLevel],
            doc: "ein normales macOS-Fenster mit Titelleiste.",
            example: "window \"settings\" { }"
        ),
    ]
}
