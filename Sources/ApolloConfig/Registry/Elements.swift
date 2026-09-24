enum Elements {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "text",
            category: .element,
            arguments: [ArgumentSchema(name: "content", type: .string, doc: "Inhalt, Vorlage erlaubt.")],
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "lines", type: .number, defaultValue: .number(1), allowsExpression: false, doc: "Zeilen, 0 = unbegrenzt."),
                PropertySchema(name: "truncate", type: .enumeration(["tail", "middle", "head"]), defaultValue: .null, allowsExpression: false, doc: "wo abgeschnitten wird."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "zeichnet Text.",
            example: "text \"{clock.now | date 'HH:mm'}\""
        ),
        NodeSchema(
            name: "icon",
            category: .element,
            arguments: [ArgumentSchema(name: "name", type: .string, doc: "Name aus dem Theme oder SF-Symbol.")],
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "fallback", type: .string, defaultValue: .null, doc: "SF Symbol, falls der Name nicht gefunden wird."),
                PropertySchema(name: "variable", type: .number, defaultValue: .null, doc: "Wert 0…1 für SF-Symbole mit Stufen."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "zeichnet ein Symbol.",
            example: "icon \"bar-power\" fallback=\"power\""
        ),
        NodeSchema(
            name: "image",
            category: .element,
            arguments: [ArgumentSchema(name: "source", type: .path, doc: "Pfad oder Bildwert eines Providers.")],
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "fit", type: .enumeration(["fill", "fit", "stretch", "center"]), defaultValue: .null, allowsExpression: false, doc: "wie das Bild in den Rahmen passt."),
                PropertySchema(name: "placeholder", type: .string, defaultValue: .null, doc: "Icon-Name, solange nichts da ist."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "zeichnet ein Bild.",
            example: "image \"{media.artwork}\""
        ),
        NodeSchema(
            name: "app-icon",
            category: .element,
            arguments: [ArgumentSchema(name: "app", type: .value, doc: "Bundle-ID oder App-Record.")],
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "badge", type: .value, defaultValue: .null, doc: "Plakette, String oder Zahl."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "zeichnet das Symbol einer App.",
            example: "app-icon \"{app}\""
        ),
        NodeSchema(
            name: "theme-preview",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "theme", type: .oneOf([.string, .record]), required: true, doc: "Theme-Kennung oder Record mit `css` (Marketplace-Eintrag, vorher wie ein installiertes Theme geprüft)."),
                PropertySchema(name: "appearance", type: .enumeration(["light", "dark"]), defaultValue: .null, doc: "erzwungenes Erscheinungsbild der Vorschau."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "zeichnet die feste Vorschau-Szene eines Themes.",
            example: "theme-preview theme=\"{item.slug}\""
        ),
        NodeSchema(
            name: "mark",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "state", type: .enumeration(["idle", "farewell", "sleep", "think"]), defaultValue: .null, allowsExpression: true, doc: "Grundstimmung des Emblems."),
                PropertySchema(name: "greet", type: .bool, defaultValue: .bool(true), doc: "spielt beim Erscheinen die Begrüssung."),
                PropertySchema(name: "color", type: .string, defaultValue: .null, doc: "Akzentfarbe."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "das animierte ApolloShell-Emblem.",
            example: "mark state=\"idle\""
        ),
        NodeSchema(
            name: "shape",
            category: .element,
            arguments: [ArgumentSchema(name: "kind", type: .enumeration(["circle", "capsule", "scallop"]), allowsExpression: false, doc: "Art der Form.")],
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "count", type: .number, defaultValue: .null, doc: "Anzahl Wellen bei scallop."),
                PropertySchema(name: "depth", type: .number, defaultValue: .null, doc: "Tiefe der Wellen 0…1 bei scallop."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "zeichnet eine einfache Form, Füllung und Grösse per CSS.",
            example: "shape \"circle\""
        ),
        NodeSchema(
            name: "button",
            category: .element,
            properties: CommonProperties.elementProperties,
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "auslösbarer Knopf, Leertaste und Return lösen on-click aus.",
            example: "button { on-click { toggle \"launcher\" } }"
        ),
        NodeSchema(
            name: "toggle",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "checked", type: .bool, required: true, doc: "Zustand des Schalters."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-change"],
            contexts: [.surfaceBody, .elementBody],
            doc: "An-/Aus-Schalter.",
            example: "toggle checked=\"{var.dark-mode}\""
        ),
        NodeSchema(
            name: "slider",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "value", type: .number, required: true, doc: "aktueller Wert."),
                PropertySchema(name: "min", type: .number, defaultValue: .number(0), doc: "unterer Rand."),
                PropertySchema(name: "max", type: .number, defaultValue: .number(1), doc: "oberer Rand."),
                PropertySchema(name: "step", type: .number, defaultValue: .number(0), doc: "Rasterung, 0 = stufenlos."),
                PropertySchema(name: "key-step", type: .number, defaultValue: .null, doc: "Schritt für Pfeiltasten und VoiceOver, Vorgabe step."),
                PropertySchema(name: "vertical", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "senkrechte Ausrichtung."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-change", "on-commit"],
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "Schieberegler, benannter Slot fill \"thumb\" zeichnet Inhalt im Griff.",
            example: "slider value=\"{audio.volume}\" { on-change { audio.set-volume \"{event.value}\" } }"
        ),
        NodeSchema(
            name: "input",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "value", type: .string, defaultValue: .null, doc: "Textinhalt."),
                PropertySchema(name: "bind", type: .string, defaultValue: .null, allowsExpression: false, doc: "var.<name>, liest und schreibt das var direkt."),
                PropertySchema(name: "placeholder", type: .string, defaultValue: .null, doc: "Platzhaltertext."),
                PropertySchema(name: "focus", type: .bool, defaultValue: .null, doc: "bekommt den Fokus, sobald der Ausdruck wahr wird."),
                PropertySchema(name: "secure", type: .bool, defaultValue: .bool(false), doc: "verdeckte Eingabe."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-change", "on-submit", "key"],
            contexts: [.surfaceBody, .elementBody],
            doc: "Texteingabe.",
            example: "input bind=\"var.launcher-query\" placeholder=\"Search\""
        ),
        NodeSchema(
            name: "key-recorder",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "value", type: .string, defaultValue: .null, doc: "aufgenommene Kombination als String."),
                PropertySchema(name: "placeholder", type: .string, defaultValue: .null, doc: "Platzhaltertext."),
                PropertySchema(name: "reject", type: .value, defaultValue: .null, doc: "Liste von Kombinationen, die abgelehnt werden."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-change"],
            contexts: [.surfaceBody, .elementBody],
            doc: "nimmt eine Tastenkombination auf.",
            example: "key-recorder value=\"{var.launcher-key}\""
        ),
        NodeSchema(
            name: "ring",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "value", type: .number, required: true, doc: "Füllstand 0…1."),
                PropertySchema(name: "gap", type: .number, defaultValue: .number(0), doc: "Anteil Abstand zwischen Füllung und Spur."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Kreisring oder Bogen.",
            example: "ring value=\"{perf.cpu}\""
        ),
        NodeSchema(
            name: "gauge",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "value", type: .number, required: true, doc: "Füllstand 0…1."),
                PropertySchema(name: "ticks", type: .number, defaultValue: .number(0), doc: "Anzahl Markierungen."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Bogen von -135° bis 135°.",
            example: "gauge value=\"{audio.volume}\""
        ),
        NodeSchema(
            name: "graph",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "values", type: .list, required: true, doc: "Liste von Zahlen."),
                PropertySchema(name: "min", type: .number, defaultValue: .number(0), doc: "unterer Rand."),
                PropertySchema(name: "max", type: .number, defaultValue: .null, doc: "oberer Rand, Vorgabe grösster Wert."),
                PropertySchema(name: "kind", type: .enumeration(["line", "area", "bars"]), defaultValue: .null, allowsExpression: false, doc: "Darstellung."),
                PropertySchema(name: "capacity", type: .number, defaultValue: .null, doc: "Anzahl Punkte, ältere fallen weg."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "zeichnet einen Verlauf, etwa CPU-Historie.",
            example: "graph values=\"{perf.live.cpu-history}\" kind=\"line\""
        ),
        NodeSchema(
            name: "progress",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "value", type: .number, defaultValue: .null, doc: "0…1 oder #null für unbestimmt."),
                PropertySchema(name: "vertical", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "senkrechte Ausrichtung."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Fortschrittsbalken.",
            example: "progress value=\"{weather.current.humidity}\""
        ),
        NodeSchema(
            name: "reorderable",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "axis", type: .enumeration(["vertical", "horizontal", "grid"]), defaultValue: .null, allowsExpression: false, doc: "Zieh-Richtung."),
                PropertySchema(name: "enabled", type: .bool, defaultValue: .null, doc: "nur dann ist Ziehen möglich."),
                PropertySchema(name: "accept", type: .enumeration(["apps", "files"]), defaultValue: .null, doc: "fremde Objekte, die hineingezogen werden dürfen."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-reorder", "on-drop", "on-drag-out"],
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "Container, dessen Kinder aus genau einem each per Ziehen umsortiert werden.",
            example: "reorderable axis=\"vertical\" { each item in=\"{var.items}\" { text \"{item.name}\" } }"
        ),
        NodeSchema(
            name: "flyout",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "anchor", type: .identifier, required: true, doc: "id des Elements, neben dem der Flyout wächst."),
                PropertySchema(name: "side", type: .enumeration(["right", "left", "top", "bottom"]), defaultValue: .null, allowsExpression: false, doc: "Wachstumsrichtung."),
                PropertySchema(name: "open", type: .bool, required: true, doc: "ob der Flyout offen ist."),
                PropertySchema(name: "join", type: .bool, defaultValue: .bool(true), doc: "wird bei shape=fused Teil der Form der Oberfläche."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-close"],
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "Bereich, der aus der eigenen Oberfläche neben einem Element herauswächst.",
            example: "flyout anchor=\"status-icon\" open=\"{var.popout-open}\" { text \"Details\" }"
        ),
        CommonProperties.elementHandlerNode,
        CommonProperties.accessibilityAction,
    ]
}
