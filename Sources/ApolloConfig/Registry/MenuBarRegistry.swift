enum MenuBarRegistry {
    private typealias S = ProviderSupport

    static let menubar = ProviderSchema(
        id: "menubar",
        feature: "menu-mirror",
        stability: .stable,
        fields: [
            S.field("app-name", .string, update: .push, doc: "Name the frontmost app gives its own menu, such as Finder."),
            S.field("bundle-id", .string, nullable: true, update: .push, doc: "Bundle ID of the frontmost app, #null without one."),
            S.field("menus", .list, update: .push, doc: "Top-level menus of the frontmost app, each with index, title, apple and app; entries come from the app-menubar menu source."),
            S.field("trusted", .bool, update: .push, doc: "Whether the shell may read other apps' menus (Accessibility)."),
        ],
        actions: [
            ActionSchema(name: "menubar.press", arguments: [
                ArgumentSchema(name: "path", type: .string, variadic: true, doc: "Menu title, then entry titles down to the entry to press."),
            ], startsProgramsOrControlsApps: true, feature: "menu-mirror", stability: .stable, doc: "Presses an entry in the frontmost app's menu bar through Accessibility, like choosing it."),
        ],
        permissions: ["accessibility"],
        doc: "The frontmost app's menu bar, read through Accessibility on a queue of its own."
    )

    static let statusItems = ProviderSchema(
        id: "status-items",
        feature: "status-items",
        stability: .stable,
        fields: [
            S.field("list", .list, update: .poll(seconds: 4), doc: "Other apps' status items in Apple's order, each with id, app, name, title, image, kind (menu or popover, #null until known), monochrome and symbol (SF Symbol stand-in, only from fixtures)."),
        ],
        actions: [
            ActionSchema(name: "status-items.click", arguments: [
                ArgumentSchema(name: "id", type: .string, doc: "Id of the status item from status-items.list."),
            ], startsProgramsOrControlsApps: true, feature: "status-items", stability: .stable, doc: "Clicks the original status item where Apple's menu bar has it, so its menu, popover or window opens."),
        ],
        permissions: ["accessibility", "screen-recording"],
        doc: "Status items of other apps, their pictures captured with ScreenCaptureKit."
    )

    static let runs = FilterSchema(
        name: "runs",
        arguments: [ArgumentSchema(name: "field", type: .string, doc: "Field of each item; a new run starts at every item where it is false.")],
        feature: "runs",
        stability: .stable,
        doc: "Splits a list into runs, a list of lists."
    )

    static let appMenus = NodeSchema(
        name: "app-menus",
        category: .element,
        feature: "menu-mirror",
        stability: .stable,
        properties: CommonProperties.elementProperties,
        handlers: CommonProperties.elementHandlers,
        childContext: .elementBody,
        contexts: [.surfaceBody, .elementBody],
        doc: "Row that keeps its first child, shows as many of the middle children as fit and shows its last child, the overflow button, only when some did not fit.",
        example: "app-menus { text \"{menubar.app-name}\"; text \"File\"; text \"…\" }"
    )

    static let menuSources: [NodeSchema] = [
        NodeSchema(
            name: "app-menubar",
            category: .menuItem,
            feature: "menu-mirror",
            stability: .stable,
            properties: [
                PropertySchema(name: "index", type: .number, defaultValue: .null, doc: "Top-level menu to list, 0 is the Apple menu, 1 the app menu."),
                PropertySchema(name: "overflow", type: .bool, defaultValue: .bool(false), doc: "Lists the menus an app-menus element folded away, each as a submenu."),
            ],
            contexts: [.menu],
            doc: "Entries of the frontmost app's menu, read fresh on opening, with shortcuts, ticks, submenus and Option alternates.",
            example: "source \"app-menubar\" index=2"
        ),
        NodeSchema(
            name: "status-item",
            category: .menuItem,
            feature: "status-items",
            stability: .stable,
            properties: [
                PropertySchema(name: "item", type: .value, required: true, doc: "Status item record or its id."),
            ],
            contexts: [.menu],
            doc: "Menu of another app's status item, read without opening it; empty for items with a popover.",
            example: "source \"status-item\" item=\"12-0\""
        ),
    ]

    static let notchFields: [FieldSchema] = [
        S.field("menubar-height", .number, update: .push, doc: "Height of Apple's menu bar on this screen in pt, 0 while it is hidden."),
        S.field("notch-left", .record, nullable: true, update: .push, doc: "Room left of the notch with x, y, width and height in pt, #null without a notch."),
        S.field("notch-right", .record, nullable: true, update: .push, doc: "Room right of the notch with x, y, width and height in pt, #null without a notch."),
    ]

    static let rowNotch = PropertySchema(
        name: "notch",
        type: .enumeration(["ignore", "avoid"]),
        defaultValue: .string("ignore"),
        doc: "avoid keeps start children left of the notch and puts centered and end children right of it.",
        stability: .stable,
        feature: "notch-area"
    )

    static let hideAppleMenuBar = ActionSchema(name: "system.hide-apple-menubar", arguments: [
        ArgumentSchema(name: "value", type: .bool, doc: "#true hides Apple's menu bar, #false restores the setting from before."),
    ], feature: "menu-mirror", stability: .stable, doc: "Hides Apple's menu bar; restored when the shell quits, and at the next start after a crash.")

    static let appleMenuBarHidden = S.field("apple-menubar-hidden", .bool, update: .push, doc: "Whether the shell keeps Apple's menu bar hidden right now.")

    static let screenCaptureBypass = S.field("screen-capture-bypass", .bool, update: .poll(seconds: 2), doc: "Whether macOS lets the shell capture single windows without asking each time.")

    static let features: [FeatureSchema] = [
        FeatureSchema(name: "menu-mirror", since: "0.2.1"),
        FeatureSchema(name: "status-items", since: "0.2.1"),
        FeatureSchema(name: "notch-area", since: "0.2.1"),
        FeatureSchema(name: "runs", since: "0.2.1"),
    ]
}
