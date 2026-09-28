enum WMSettings {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "layout",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "kind", type: .enumeration(["dwindle", "canvas"]), allowsExpression: false, doc: "Default layout.")],
            contexts: [.wmBlock],
            doc: "Selects the default layout of the window manager.",
            example: "layout \"dwindle\""
        ),
        NodeSchema(
            name: "gaps",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "inner", type: .number, defaultValue: .number(10), allowsExpression: false, doc: "Spacing between windows in pt.", feature: "wm"),
                PropertySchema(name: "outer", type: .number, defaultValue: .number(12), allowsExpression: false, doc: "Spacing to the screen edge in pt.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Spacing between and around tiled windows.",
            example: "gaps inner=10 outer=12"
        ),
        NodeSchema(
            name: "focus-follows-mouse",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "enabled", type: .bool, allowsExpression: false, doc: "Whether focus follows the pointer.")],
            properties: [
                PropertySchema(name: "delay", type: .duration, defaultValue: .string("25ms"), allowsExpression: false, doc: "Delay before focus follows.", feature: "wm"),
                PropertySchema(name: "suspend-with", type: .string, defaultValue: .null, allowsExpression: false, doc: "Modifiers that temporarily disable the feature.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Whether and how focus follows the mouse pointer.",
            example: "focus-follows-mouse #true delay=\"25ms\""
        ),
        NodeSchema(
            name: "drag",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "super", type: .string, defaultValue: .string("hyper"), allowsExpression: false, doc: "Modifiers for dragging and resizing.", feature: "wm"),
                PropertySchema(name: "scroll-pans", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "Scrolling pans the canvas strip.", feature: "wm"),
                PropertySchema(name: "scroll-speed", type: .number, defaultValue: .number(1.5), allowsExpression: false, doc: "Speed of canvas panning.", feature: "wm"),
                PropertySchema(name: "invert-scroll", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "Reverses the scroll direction.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Mouse control of the window manager.",
            example: "drag super=\"hyper\" scroll-pans=#true"
        ),
        NodeSchema(
            name: "resize-animation",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "kind", type: .enumeration(["smooth", "snap", "proxy"]), allowsExpression: false, doc: "Kind of resize animation.")],
            contexts: [.wmBlock],
            doc: "How windows change their size.",
            example: "resize-animation \"smooth\""
        ),
        NodeSchema(
            name: "spring",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "response", type: .number, defaultValue: .number(0.28), allowsExpression: false, doc: "Spring response time in s.", feature: "wm"),
                PropertySchema(name: "frame-rate", type: .number, defaultValue: .number(120), allowsExpression: false, doc: "Frame rate of the animation.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Spring parameters of the tiling animations.",
            example: "spring response=0.28"
        ),
        NodeSchema(
            name: "tab-bar",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "height", type: .number, defaultValue: .number(30), allowsExpression: false, doc: "Height of the tab bar in pt.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Size of the tab bar of grouped windows.",
            example: "tab-bar height=30"
        ),
        NodeSchema(
            name: "canvas",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "column-width", type: .number, defaultValue: .number(0.5), allowsExpression: false, doc: "Share 0…1 of the column width.", feature: "wm"),
                PropertySchema(name: "center-focused", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "Centers the focused window.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Settings of the canvas layout.",
            example: "canvas column-width=0.5"
        ),
        NodeSchema(
            name: "scratchpad",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "share", type: .number, defaultValue: .number(0.7), allowsExpression: false, doc: "Share 0…1 of the screen.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Size of the scratchpad.",
            example: "scratchpad share=0.7"
        ),
        NodeSchema(
            name: "terminal",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "bundle-ids", type: .string, variadic: true, allowsExpression: false, doc: "Bundle IDs, the first installed one wins.")],
            contexts: [.wmBlock],
            doc: "Selects the terminal for wm.terminal.",
            example: "terminal \"com.mitchellh.ghostty\" \"com.apple.Terminal\""
        ),
        NodeSchema(
            name: "apple-desktops",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "enabled", type: .bool, allowsExpression: false, doc: "Whether wm.desktop switches Apple's Spaces.")],
            contexts: [.wmBlock],
            doc: "Whether the window manager uses Apple's Spaces or its own workspaces.",
            example: "apple-desktops #true"
        ),
        NodeSchema(
            name: "rule",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "kind", type: .enumeration(["float", "tile", "ignore"]), allowsExpression: false, doc: "How matching windows are treated.")],
            properties: [
                PropertySchema(name: "app", type: .string, defaultValue: .null, allowsExpression: false, doc: "Bundle ID or app name, case-insensitive.", feature: "wm"),
                PropertySchema(name: "title", type: .string, defaultValue: .null, allowsExpression: false, doc: "Part of the window title.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Rule for individual windows by app or title.",
            example: "rule \"float\" app=\"com.apple.calculator\""
        ),
        NodeSchema(
            name: "reserve-panels",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "enabled", type: .bool, allowsExpression: false, doc: "Whether strips of panel reserve=#true are kept free.")],
            contexts: [.wmBlock],
            doc: "Whether panels with reserve shrink the tiling area.",
            example: "reserve-panels #true"
        ),
        NodeSchema(
            name: "reserve",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "top", type: .number, defaultValue: .null, allowsExpression: false, doc: "Reserved strip at the top in pt.", feature: "wm"),
                PropertySchema(name: "left", type: .number, defaultValue: .null, allowsExpression: false, doc: "Reserved strip on the left in pt.", feature: "wm"),
                PropertySchema(name: "bottom", type: .number, defaultValue: .null, allowsExpression: false, doc: "Reserved strip at the bottom in pt.", feature: "wm"),
                PropertySchema(name: "right", type: .number, defaultValue: .null, allowsExpression: false, doc: "Reserved strip on the right in pt.", feature: "wm"),
                PropertySchema(name: "screen", type: .string, defaultValue: .null, allowsExpression: false, doc: "Which screen the reservation applies to.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Additional reserved strip for third-party bars, allowed more than once.",
            example: "reserve top=24"
        ),
    ]
}
