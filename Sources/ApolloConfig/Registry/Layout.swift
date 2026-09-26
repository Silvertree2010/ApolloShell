enum Layout {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "row",
            category: .layout,
            properties: CommonProperties.elementProperties,
            handlers: CommonProperties.elementHandlers,
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "Lays out children side by side, flexbox direction row.",
            example: "row class=\"toolbar\" { text \"Left\" }"
        ),
        NodeSchema(
            name: "column",
            category: .layout,
            properties: CommonProperties.elementProperties,
            handlers: CommonProperties.elementHandlers,
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "Lays out children top to bottom, flexbox direction column.",
            example: "column class=\"stack\" { text \"Top\" }"
        ),
        NodeSchema(
            name: "grid",
            category: .layout,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "columns", type: .number, defaultValue: .null, doc: "Number of columns."),
            ],
            handlers: CommonProperties.elementHandlers,
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "Lays out children in a grid.",
            example: "grid columns=3 { text \"1\" }"
        ),
        NodeSchema(
            name: "stack",
            category: .layout,
            properties: CommonProperties.elementProperties,
            handlers: CommonProperties.elementHandlers,
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "Stacks children on the z axis, may be empty.",
            example: "stack class=\"divider\" { }"
        ),
        NodeSchema(
            name: "scroll",
            category: .layout,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "axis", type: .enumeration(["vertical", "horizontal", "both"]), defaultValue: .string("vertical"), doc: "Scroll direction."),
                PropertySchema(name: "reveal", type: .value, defaultValue: .null, doc: "Key or id scrolled into view whenever the value changes."),
                PropertySchema(name: "indicators", type: .bool, defaultValue: .bool(false), doc: "Whether scroll bars are visible."),
                PropertySchema(name: "lazy", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "Reserved: children are currently all built at once, lazy building crashed on macOS 26."),
            ],
            handlers: CommonProperties.elementHandlers,
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "Scrollable area.",
            example: "scroll axis=\"vertical\" { column { } }"
        ),
        NodeSchema(
            name: "spacer",
            category: .layout,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "size", type: .number, defaultValue: .null, doc: "Fixed spacing in pt, otherwise the spacer fills the free space."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Fills free space in row/column, or a fixed spacing.",
            example: "spacer"
        ),
    ]
}
