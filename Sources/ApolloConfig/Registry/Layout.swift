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
            name: "canvas",
            category: .layout,
            feature: "canvas-layout",
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "in", type: .list, defaultValue: .null, doc: "Items, records with x, y, width, height in pt and optional sizes (records min-width, max-width or width, and height) that limit resizing; default the items of the each."),
                PropertySchema(name: "key", type: .string, defaultValue: .string("id"), allowsExpression: false, doc: "Field that identifies an item, sent as event.key."),
                PropertySchema(name: "sizes", type: .list, defaultValue: .null, doc: "Catalogue for items without their own sizes: records whose sizes-by field matches the item's, each with a sizes list."),
                PropertySchema(name: "sizes-by", type: .string, defaultValue: .string("kind"), allowsExpression: false, doc: "Field that links an item to its entry in sizes."),
                PropertySchema(name: "enabled", type: .bool, defaultValue: .bool(false), doc: "Items can be moved and resized by dragging; a drag from the bottom-right 28 pt corner resizes."),
                PropertySchema(name: "gap", type: .number, defaultValue: .number(12), doc: "Minimum distance between two items."),
                PropertySchema(name: "snap", type: .number, defaultValue: .number(8), doc: "Distance at which an edge jumps onto the canvas edge or a neighbour."),
                PropertySchema(name: "scale", type: .number, defaultValue: .number(1), doc: "Factor for frames and content, for example the user's factor times (screen.width / 1512 | clamp 0.85 1.5)."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-move", "on-resize"],
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "Places the children of exactly one each at the x, y, width and height of their item. While enabled, dragging an item fires on-move, dragging its corner on-resize (event.key, x, y, width, height, valid, phase changed or ended); the item shows :invalid where it does not fit and springs back unless the handler takes the new frame.",
            example: "canvas gap=12 snap=8 { each s in=\"{screens.list}\" key=\"{s.id}\" { text \"{s.name}\" } }"
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
