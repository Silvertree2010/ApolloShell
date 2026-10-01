enum Elements {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "text",
            category: .element,
            arguments: [ArgumentSchema(name: "content", type: .string, doc: "Content, template allowed.")],
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "lines", type: .number, defaultValue: .number(1), allowsExpression: false, doc: "Lines, 0 = unlimited."),
                PropertySchema(name: "truncate", type: .enumeration(["tail", "middle", "head"]), defaultValue: .null, allowsExpression: false, doc: "Where text is truncated."),
                PropertySchema(name: "min-scale", type: .number, defaultValue: .number(1), allowsExpression: false, doc: "Smallest factor 0…1 the text shrinks to before it is truncated."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Draws text.",
            example: "text \"{clock.now | date 'HH:mm'}\""
        ),
        NodeSchema(
            name: "icon",
            category: .element,
            arguments: [ArgumentSchema(name: "name", type: .string, doc: "Name from the theme or SF Symbol.")],
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "fallback", type: .string, defaultValue: .null, doc: "SF Symbol if the name is not found."),
                PropertySchema(name: "variable", type: .number, defaultValue: .null, doc: "Value 0…1 for SF Symbols with levels."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Draws a symbol.",
            example: "icon \"bar-power\" fallback=\"power\""
        ),
        NodeSchema(
            name: "image",
            category: .element,
            arguments: [ArgumentSchema(name: "source", type: .path, doc: "Path or image value of a provider.")],
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "fit", type: .enumeration(["fill", "fit", "stretch", "center"]), defaultValue: .null, allowsExpression: false, doc: "How the image fits its frame."),
                PropertySchema(name: "placeholder", type: .string, defaultValue: .null, doc: "Icon name while nothing is loaded."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Draws an image.",
            example: "image \"{media.artwork}\""
        ),
        NodeSchema(
            name: "app-icon",
            category: .element,
            arguments: [ArgumentSchema(name: "app", type: .value, doc: "Bundle ID or app record.")],
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "badge", type: .value, defaultValue: .null, doc: "Badge, string or number."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Draws the icon of an app.",
            example: "app-icon \"{app}\""
        ),
        NodeSchema(
            name: "theme-preview",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "theme", type: .oneOf([.string, .record]), required: true, doc: "Theme id or record with `css` (Marketplace entry, checked like an installed theme first)."),
                PropertySchema(name: "appearance", type: .enumeration(["light", "dark"]), defaultValue: .null, doc: "Forced appearance of the preview."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Draws the fixed preview scene of a theme.",
            example: "theme-preview theme=\"{item.slug}\""
        ),
        NodeSchema(
            name: "mark",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "state", type: .enumeration(["idle", "farewell", "sleep", "think"]), defaultValue: .null, allowsExpression: true, doc: "Base mood of the emblem."),
                PropertySchema(name: "greet", type: .bool, defaultValue: .bool(true), doc: "Plays the greeting when it appears."),
                PropertySchema(name: "color", type: .string, defaultValue: .null, doc: "Accent color."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "The animated ApolloShell emblem.",
            example: "mark state=\"idle\""
        ),
        NodeSchema(
            name: "shape",
            category: .element,
            arguments: [ArgumentSchema(name: "kind", type: .enumeration(["circle", "capsule", "scallop"]), allowsExpression: false, doc: "Kind of shape.")],
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "count", type: .number, defaultValue: .null, doc: "Number of waves for scallop."),
                PropertySchema(name: "depth", type: .number, defaultValue: .null, doc: "Depth of the waves 0…1 for scallop."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Draws a simple shape, fill and size via CSS.",
            example: "shape \"circle\""
        ),
        NodeSchema(
            name: "button",
            category: .element,
            properties: CommonProperties.elementProperties,
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Clickable button, Space and Return trigger on-click.",
            example: "button { on-click { toggle \"launcher\" } }"
        ),
        NodeSchema(
            name: "toggle",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "checked", type: .bool, required: true, doc: "State of the switch."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-change"],
            contexts: [.surfaceBody, .elementBody],
            doc: "On/off switch.",
            example: "toggle checked=\"{var.dark-mode}\""
        ),
        NodeSchema(
            name: "slider",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "value", type: .number, required: true, doc: "Current value."),
                PropertySchema(name: "min", type: .number, defaultValue: .number(0), doc: "Lower bound."),
                PropertySchema(name: "max", type: .number, defaultValue: .number(1), doc: "Upper bound."),
                PropertySchema(name: "step", type: .number, defaultValue: .number(0), doc: "Step size, 0 = continuous."),
                PropertySchema(name: "key-step", type: .number, defaultValue: .null, doc: "Step for arrow keys and VoiceOver, default step."),
                PropertySchema(name: "vertical", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "Vertical orientation."),
                PropertySchema(name: "track-size", type: .number, defaultValue: .null, doc: "Thickness of the track in points, default the full cross size of the slider."),
                PropertySchema(name: "ticks", type: .bool, defaultValue: .bool(false), doc: "Draw a tick mark for every step below the track, needs step greater than 0."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-change", "on-commit"],
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "Slider, the named slot fill \"thumb\" draws content in the thumb.",
            example: "slider value=\"{audio.volume}\" { on-change { audio.set-volume \"{event.value}\" } }"
        ),
        NodeSchema(
            name: "input",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "value", type: .string, defaultValue: .null, doc: "Text content."),
                PropertySchema(name: "bind", type: .string, defaultValue: .null, allowsExpression: false, doc: "var.<name>, reads and writes the var directly."),
                PropertySchema(name: "placeholder", type: .string, defaultValue: .null, doc: "Placeholder text."),
                PropertySchema(name: "focus", type: .bool, defaultValue: .null, doc: "Takes focus as soon as the expression becomes true."),
                PropertySchema(name: "secure", type: .bool, defaultValue: .bool(false), doc: "Hidden input."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-change", "on-submit", "key"],
            contexts: [.surfaceBody, .elementBody],
            doc: "Text input.",
            example: "input bind=\"var.launcher-query\" placeholder=\"Search\""
        ),
        NodeSchema(
            name: "key-recorder",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "value", type: .string, defaultValue: .null, doc: "Recorded combination as a string."),
                PropertySchema(name: "placeholder", type: .string, defaultValue: .null, doc: "Placeholder text."),
                PropertySchema(name: "reject", type: .value, defaultValue: .null, doc: "List of combinations that are rejected."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-change"],
            contexts: [.surfaceBody, .elementBody],
            doc: "Records a key combination.",
            example: "key-recorder value=\"{var.launcher-key}\""
        ),
        NodeSchema(
            name: "ring",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "value", type: .number, required: true, doc: "Fill level 0…1."),
                PropertySchema(name: "gap", type: .number, defaultValue: .number(0), doc: "Share of spacing between fill and track."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Circular ring or arc.",
            example: "ring value=\"{perf.cpu}\""
        ),
        NodeSchema(
            name: "gauge",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "value", type: .number, required: true, doc: "Fill level 0…1."),
                PropertySchema(name: "ticks", type: .number, defaultValue: .number(0), doc: "Number of tick marks."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Arc from -135° to 135°.",
            example: "gauge value=\"{audio.volume}\""
        ),
        NodeSchema(
            name: "graph",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "values", type: .list, required: true, doc: "List of numbers."),
                PropertySchema(name: "min", type: .number, defaultValue: .number(0), doc: "Lower bound."),
                PropertySchema(name: "max", type: .number, defaultValue: .null, doc: "Upper bound, default largest value."),
                PropertySchema(name: "kind", type: .enumeration(["line", "area", "bars"]), defaultValue: .null, allowsExpression: false, doc: "How the values are drawn: line, area or bars."),
                PropertySchema(name: "capacity", type: .number, defaultValue: .null, doc: "Number of points, older ones drop out."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Draws a history, such as CPU history.",
            example: "graph values=\"{perf.live.cpu-history}\" kind=\"line\""
        ),
        NodeSchema(
            name: "progress",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "value", type: .number, defaultValue: .null, doc: "0…1 or #null for indeterminate."),
                PropertySchema(name: "vertical", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "Vertical orientation."),
            ],
            handlers: CommonProperties.elementHandlers,
            contexts: [.surfaceBody, .elementBody],
            doc: "Progress bar.",
            example: "progress value=\"{weather.current.humidity}\""
        ),
        NodeSchema(
            name: "reorderable",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "axis", type: .enumeration(["vertical", "horizontal", "grid"]), defaultValue: .null, allowsExpression: false, doc: "Drag direction."),
                PropertySchema(name: "enabled", type: .bool, defaultValue: .null, doc: "Dragging is only possible when set."),
                PropertySchema(name: "accept", type: .enumeration(["apps", "files", "value"]), defaultValue: .null, doc: "External objects that may be dragged in; value takes the drag-value of another element, with event.value and event.index in on-drop."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-reorder", "on-drop", "on-drag-out"],
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "Container whose children from exactly one each can be reordered by dragging.",
            example: "reorderable axis=\"vertical\" { each item in=\"{var.items}\" { text \"{item.name}\" } }"
        ),
        NodeSchema(
            name: "flyout",
            category: .element,
            properties: CommonProperties.elementProperties + [
                PropertySchema(name: "anchor", type: .identifier, required: true, doc: "Id of the element next to which the flyout grows."),
                PropertySchema(name: "side", type: .enumeration(["right", "left", "top", "bottom"]), defaultValue: .null, allowsExpression: false, doc: "Growth direction."),
                PropertySchema(name: "open", type: .bool, required: true, doc: "Whether the flyout is open."),
                PropertySchema(name: "join", type: .bool, defaultValue: .bool(true), doc: "With shape=fused, becomes part of the surface shape."),
            ],
            handlers: CommonProperties.elementHandlers + ["on-close"],
            childContext: .elementBody,
            contexts: [.surfaceBody, .elementBody],
            doc: "Area that grows out of its own surface next to an element.",
            example: "flyout anchor=\"status-icon\" open=\"{var.popout-open}\" { text \"Details\" }"
        ),
        CommonProperties.elementHandlerNode,
        CommonProperties.accessibilityAction,
    ]
}
