enum CommonProperties {
    static let idArgument = ArgumentSchema(
        name: "id",
        type: .identifier,
        doc: "Id, unique per surface; target for flyout, popup and each."
    )

    static let baseline: [PropertySchema] = [
        PropertySchema(name: "id", type: .identifier, defaultValue: .null, doc: "Id, unique per surface, template allowed."),
        PropertySchema(name: "class", type: .string, defaultValue: .null, doc: "CSS classes, separated by spaces."),
        PropertySchema(name: "style", type: .string, defaultValue: .null, doc: "CSS declarations for this node only."),
        PropertySchema(name: "visible", type: .bool, defaultValue: .bool(true), doc: "Hides the node without losing state."),
        PropertySchema(name: "tooltip", type: .string, defaultValue: .null, doc: "Help text on hover."),
        PropertySchema(name: "label", type: .string, defaultValue: .null, doc: "Text for VoiceOver, default from tooltip or content."),
        PropertySchema(name: "checked", type: .bool, defaultValue: .bool(false), doc: "Sets the :checked pseudo-class."),
        PropertySchema(name: "disabled", type: .bool, defaultValue: .bool(false), doc: "No input, :disabled pseudo-class."),
        PropertySchema(name: "match-id", type: .string, defaultValue: .null, doc: "Elements with the same match-id glide into each other when they appear."),
        PropertySchema(name: "menu-on", type: .string, defaultValue: .string("right-click"), doc: "What opens the context menu, several separated by spaces."),
    ]

    static let dragValue = PropertySchema(
        name: "drag-value",
        type: .value,
        defaultValue: .null,
        allowsExpression: true,
        doc: "Makes the element a drag source carrying this value; on-drop accept=\"value\" and reorderable accept=\"value\" receive it as event.value.",
        feature: "drag-values"
    )

    static let fuseGroup = PropertySchema(
        name: "fuse-group",
        type: .string,
        defaultValue: .null,
        doc: "Surfaces of the same group that touch are drawn as one shape by a skin behind them; the join comes from the theme (--apollo-fusion-style) or, without one, from --fuse-style, --fuse-inner-radius, --fuse-screen-edge and --fuse-jelly in the config's :root.",
        feature: "fusion"
    )

    static let fuseFill = PropertySchema(
        name: "fuse-fill",
        type: .bool,
        defaultValue: .bool(false),
        doc: "The skin of the fuse group takes this surface's background; without one, the first surface's.",
        feature: "fusion"
    )

    static let elementProperties: [PropertySchema] = baseline + [dragValue]

    static let surfaceCommon: [PropertySchema] = [
        PropertySchema(name: "override", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "Replaces a surface of the same name from an included file."),
        PropertySchema(name: "screen", type: .string, defaultValue: .null, allowsExpression: true, doc: "Which screens get instances."),
        PropertySchema(name: "anchor", type: .enumeration(["top", "bottom", "left", "right", "top-left", "top-right", "bottom-left", "bottom-right", "center", "fill"]), defaultValue: .string("center"), doc: "What the surface sticks to."),
        PropertySchema(name: "area", type: .enumeration(["full", "below-menubar", "visible"]), defaultValue: .string("below-menubar"), doc: "Reference rectangle for anchoring."),
        PropertySchema(name: "layer", type: .string, defaultValue: .null, doc: "Window level, default per surface kind."),
        PropertySchema(name: "keyboard", type: .bool, defaultValue: .bool(false), doc: "Whether the surface accepts keyboard input."),
        PropertySchema(name: "click-through", type: .oneOf([.bool, .enumeration(["auto"])]), defaultValue: .bool(false), doc: "Whether mouse events pass through; bool or \"auto\" (only not where an element with a handler or visible background lies)."),
        PropertySchema(name: "offset-x", type: .number, defaultValue: .number(0), doc: "Offset along x from the anchored position, away from the anchored edge; for anchors without a left or right edge (top, bottom, center) it counts from the horizontal middle, positive to the right."),
        PropertySchema(name: "offset-y", type: .number, defaultValue: .number(0), doc: "Offset along y from the anchored position, away from the anchored edge; for anchors without a top or bottom edge (left, right, center) it counts from the vertical middle, positive downwards. Use top-left or top-right to count from the top."),
        PropertySchema(name: "sticky", type: .bool, defaultValue: .bool(true), doc: "On all Spaces and in its own Space."),
        PropertySchema(name: "fullscreen", type: .enumeration(["hide", "show"]), defaultValue: .null, doc: "Behavior on a screen with a full-screen app."),
        PropertySchema(name: "overhang", type: .bool, defaultValue: .bool(false), doc: "Extends past the anchored edges by the corner radius and lets the window leave the screen; popups sit above the macOS menu bar, so a drawer from the top edge can hang from a 1 pt row moved off screen with offset-y=-1."),
        PropertySchema(name: "safe-area", type: .bool, defaultValue: .bool(true), doc: "Content starts below the menu bar and notch."),
        PropertySchema(name: "shape", type: .enumeration(["rect", "fused"]), defaultValue: .string("rect"), doc: "Whether open flyouts form one shape with the background."),
        fuseGroup,
        fuseFill,
    ]

    static let surfaceProperties: [PropertySchema] = baseline + surfaceCommon

    static let surfaceHandlers: [String] = ["on-open", "on-close", "on-closed", "key"]

    static let elementHandlers: [String] = [
        "on-click", "on-right-click", "on-middle-click", "on-double-click", "on-long-press",
        "on-scroll", "on-hover", "on-hover-end", "on-drop", "on-appear", "on-disappear",
    ]

    static let elementHandlerNode = NodeSchema(
        name: "menu",
        category: .element,
        arguments: [],
        properties: [
            PropertySchema(name: "side", type: .enumeration(["pointer", "right", "left", "below"]), defaultValue: .string("pointer"), doc: "Where the menu opens."),
            PropertySchema(name: "offset", type: .number, defaultValue: .number(6), doc: "Distance in pt when opening next to the element."),
        ],
        childContext: .menu,
        contexts: [.elementBody],
        doc: "Gives an element a native context menu.",
        example: "menu { item \"Copy\" { clipboard.copy \"{system.full-name}\" } }"
    )

    static let accessibilityAction = NodeSchema(
        name: "accessibility-action",
        category: .element,
        arguments: [ArgumentSchema(name: "title", type: .string, doc: "Title of the VoiceOver action.")],
        childContext: .actions,
        contexts: [.elementBody],
        doc: "Gives an element a named VoiceOver action.",
        example: "accessibility-action \"Move Up\" { list.move \"items\" from=1 to=0 }"
    )
}
