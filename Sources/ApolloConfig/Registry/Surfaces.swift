enum Surfaces {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "panel",
            category: .surface,
            arguments: [CommonProperties.idArgument],
            properties: CommonProperties.surfaceProperties + [
                PropertySchema(name: "reserve", type: .bool, defaultValue: .bool(false), doc: "Keeps app windows out of the surface's strip, only with left/right/top/bottom."),
            ],
            handlers: CommonProperties.surfaceHandlers,
            childContext: .surfaceBody,
            contexts: [.topLevel],
            doc: "Always-visible surface such as bars, docks, desktop widgets.",
            example: "panel \"sidebar\" anchor=\"left\" { }"
        ),
        NodeSchema(
            name: "popup",
            category: .surface,
            arguments: [CommonProperties.idArgument],
            properties: CommonProperties.surfaceProperties + [
                PropertySchema(name: "motion", type: .enumeration(["slide", "grow", "fade", "none", "jelly"]), defaultValue: .null, doc: "Opening and closing."),
                PropertySchema(name: "scrim", type: .number, defaultValue: .null, doc: "Dims the screen behind it, 0…1."),
                PropertySchema(name: "close-on", type: .string, defaultValue: .string("outside-click escape focus-loss"), doc: "List of what closes the popup: outside-click, escape, focus-loss, mouse-leave, global-escape (Esc closes it without the popup taking the keyboard)."),
                PropertySchema(name: "hover-edge", type: .bool, defaultValue: .bool(false), doc: "Opens when the pointer touches the anchored edge."),
                PropertySchema(name: "hover-margin", type: .number, defaultValue: .number(0), allowsExpression: false, doc: "Edge zone in pt in which the popup stays open on hover."),
                PropertySchema(name: "hover-gap", type: .number, defaultValue: .number(0), allowsExpression: false, doc: "Distance from the corner without a trigger, only with corner anchors."),
                PropertySchema(name: "group", type: .string, defaultValue: .null, doc: "Closes other popups of the same group."),
                PropertySchema(name: "attach", type: .string, defaultValue: .null, doc: "Next to an element of another surface instead of at an edge."),
                PropertySchema(name: "side", type: .enumeration(["top", "bottom", "left", "right"]), defaultValue: .string("right"), doc: "Side for attach."),
                PropertySchema(name: "align", type: .enumeration(["start", "center", "end"]), defaultValue: .string("start"), doc: "Alignment along the element for attach; CSS margin keeps the surface off the screen edges."),
            ],
            handlers: CommonProperties.surfaceHandlers,
            childContext: .surfaceBody,
            contexts: [.topLevel],
            doc: "Opens and closes on an action, such as a dashboard or launcher.",
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
            doc: "Covers the whole screen, click-through by default.",
            example: "overlay \"screen-corners\" { }"
        ),
        NodeSchema(
            name: "toast",
            category: .surface,
            arguments: [ArgumentSchema(name: "style", type: .identifier, doc: "Style name, target of the toast.show action.")],
            properties: CommonProperties.surfaceProperties + [
                PropertySchema(name: "max", type: .number, defaultValue: .number(4), allowsExpression: false, doc: "Toasts visible at the same time."),
                PropertySchema(name: "duration", type: .duration, defaultValue: .string("5s"), doc: "Display duration."),
                PropertySchema(name: "newest", type: .enumeration(["last", "first"]), defaultValue: .string("last"), doc: "Where the newest toast appears."),
            ],
            handlers: CommonProperties.surfaceHandlers,
            childContext: .surfaceBody,
            contexts: [.topLevel],
            doc: "Defines how a notification from the toast.show action looks.",
            example: "toast \"default\" { }"
        ),
        NodeSchema(
            name: "osd",
            category: .surface,
            arguments: [CommonProperties.idArgument],
            properties: CommonProperties.surfaceProperties + [
                PropertySchema(name: "timeout", type: .duration, defaultValue: .string("2s"), doc: "Display duration."),
                PropertySchema(name: "motion", type: .enumeration(["slide", "grow", "fade", "none", "jelly"]), defaultValue: .string("slide"), doc: "Opening and closing."),
            ],
            handlers: CommonProperties.surfaceHandlers,
            childContext: .surfaceBody,
            contexts: [.topLevel],
            doc: "Short feedback such as a volume indicator.",
            example: "osd \"volume\" { }"
        ),
        NodeSchema(
            name: "window",
            category: .surface,
            arguments: [CommonProperties.idArgument],
            properties: CommonProperties.surfaceProperties + [
                PropertySchema(name: "title", type: .string, defaultValue: .string(""), doc: "Window title."),
                PropertySchema(name: "title-visible", type: .bool, defaultValue: .bool(true), doc: "Whether the title bar shows the title."),
                PropertySchema(name: "titlebar", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "Whether the window shows a title bar; without it the content reaches the top edge and the window moves by dragging its background."),
                PropertySchema(name: "resizable", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "Whether the window can be resized."),
                PropertySchema(name: "closable", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "Whether the window can be closed."),
                PropertySchema(name: "miniaturizable", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "Whether the window can be minimized."),
                PropertySchema(name: "autosave", type: .string, defaultValue: .null, allowsExpression: false, doc: "Remembers size and position under this name."),
            ],
            handlers: CommonProperties.surfaceHandlers,
            childContext: .surfaceBody,
            contexts: [.topLevel],
            doc: "A regular macOS window with a title bar.",
            example: "window \"settings\" { }"
        ),
    ]
}
