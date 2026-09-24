enum Layout {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "row",
            category: .layout,
            properties: CommonProperties.elementProperties,
            handlers: CommonProperties.elementHandlers,
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "ordnet Kinder nebeneinander an, Flexbox-Richtung Zeile.",
            example: "row class=\"toolbar\" { text \"Left\" }"
        ),
        NodeSchema(
            name: "column",
            category: .layout,
            properties: CommonProperties.elementProperties,
            handlers: CommonProperties.elementHandlers,
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "ordnet Kinder untereinander an, Flexbox-Richtung Spalte.",
            example: "column class=\"stack\" { text \"Top\" }"
        ),
        NodeSchema(
            name: "grid",
            category: .layout,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "columns", type: .number, defaultValue: .null, doc: "Anzahl der Spalten."),
            ],
            handlers: CommonProperties.elementHandlers,
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "ordnet Kinder in einem Raster an.",
            example: "grid columns=3 { text \"1\" }"
        ),
        NodeSchema(
            name: "stack",
            category: .layout,
            properties: CommonProperties.elementProperties,
            handlers: CommonProperties.elementHandlers,
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "ordnet Kinder auf der z-Achse übereinander, darf leer sein.",
            example: "stack class=\"divider\" { }"
        ),
        NodeSchema(
            name: "scroll",
            category: .layout,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "axis", type: .enumeration(["vertical", "horizontal", "both"]), defaultValue: .string("vertical"), doc: "Scrollrichtung."),
                PropertySchema(name: "reveal", type: .value, defaultValue: .null, doc: "Schlüssel oder id, die sichtbar gescrollt wird, sobald sich der Wert ändert."),
                PropertySchema(name: "indicators", type: .bool, defaultValue: .bool(false), doc: "ob Scrollbalken sichtbar sind."),
                PropertySchema(name: "lazy", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "Kinder werden erst gebaut, wenn sie sichtbar werden."),
            ],
            handlers: CommonProperties.elementHandlers,
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "scrollbarer Bereich.",
            example: "scroll axis=\"vertical\" { column { } }"
        ),
        NodeSchema(
            name: "spacer",
            category: .layout,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "size", type: .number, defaultValue: .null, doc: "fester Abstand in pt, sonst füllt der spacer den freien Platz."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "füllt freien Platz in row/column, oder ein fester Abstand.",
            example: "spacer"
        ),
    ]
}
