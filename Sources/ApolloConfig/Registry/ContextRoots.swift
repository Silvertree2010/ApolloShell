enum ContextRoots {
    private typealias S = ProviderSupport

    static let all: [ContextRootSchema] = [
        ContextRootSchema(
            name: "self",
            fields: [
                S.field("hover", .bool, update: .push, doc: "Whether the pointer is over the element."),
                S.field("pressed", .bool, update: .push, doc: "Whether the element is pressed."),
                S.field("focused", .bool, update: .push, doc: "Whether the element has focus."),
            ],
            validIn: ["surfaceBody", "elementBody", "menu", "actions"]
        ),
        ContextRootSchema(
            name: "surface",
            fields: [
                S.field("id", .identifier, update: .once, doc: "Surface id."),
                S.field("open", .bool, update: .push, doc: "Whether the surface is open."),
                S.field("opening", .bool, update: .push, doc: "Whether it is opening."),
                S.field("closing", .bool, update: .push, doc: "Whether it is closing."),
            ],
            validIn: ["surfaceBody", "elementBody"]
        ),
        ContextRootSchema(
            name: "surfaces",
            fields: [
                S.field("open", .bool, update: .push, doc: "Whether another surface is open."),
                S.field("width", .number, update: .push, doc: "Its width."),
                S.field("height", .number, update: .push, doc: "Its height."),
            ],
            validIn: ["surfaceBody", "elementBody"]
        ),
        ContextRootSchema(
            name: "screen",
            fields: [
                S.field("id", .string, update: .push, doc: "Stable key of the screen."),
                S.field("name", .string, update: .push, doc: "Name."),
                S.field("main", .bool, update: .push, doc: "Whether it is the main screen."),
                S.field("width", .number, update: .push, doc: "Width."),
                S.field("height", .number, update: .push, doc: "Height."),
                S.field("usable-height", .number, update: .push, doc: "Height of the screen without Apple's menu bar and Dock."),
                S.field("notch", .bool, update: .push, doc: "Whether a notch is present."),
            ] + MenuBarRegistry.notchFields,
            validIn: ["surfaceBody", "elementBody"]
        ),
        ContextRootSchema(
            name: "theme",
            fields: [
                S.field("id", .string, update: .push, doc: "Id."),
                S.field("name", .string, update: .push, doc: "Name."),
                S.field("appearance", .string, update: .push, doc: "Light or dark."),
                S.field("dark", .bool, update: .push, doc: "Whether dark."),
                S.field("set", .record, update: .push, doc: "Which tokens the theme sets."),
            ],
            validIn: ["surfaceBody", "elementBody"]
        ),
        ContextRootSchema(
            name: "shell",
            fields: [
                S.field("version", .string, update: .once, doc: "Shell version."),
                S.field("features", .list, update: .once, doc: "Known features."),
                S.field("config", .string, update: .push, doc: "Id of the active config."),
                S.field("configs.id", .identifier, update: .push, doc: "Id of a selectable config."),
                S.field("configs.name", .string, update: .push, doc: "Name of a selectable config."),
                S.field("configs.source", .string, update: .push, doc: "Origin of a selectable config."),
                S.field("themes.id", .string, update: .push, doc: "Id of an available theme."),
                S.field("themes.name", .string, update: .push, doc: "Name of an available theme."),
                S.field("themes.author", .string, update: .push, doc: "Author of an available theme."),
                S.field("themes.description", .string, update: .push, doc: "Description of an available theme."),
                S.field("themes.issues", .list, update: .push, doc: "Notes on an available theme, as a list of texts."),
                S.field("hotkeys.chord", .string, update: .push, doc: "Key combination."),
                S.field("hotkeys.ok", .bool, update: .push, doc: "Whether the combination is free of conflicts."),
                S.field("install-kind", .string, update: .once, doc: "dmg or homebrew."),
                S.field("fresh-install", .bool, update: .once, doc: "Whether this is the first installation."),
                S.field("login-item", .bool, update: .push, doc: "Whether the shell runs as a login item."),
                S.field("login-item-available", .bool, update: .push, doc: "Whether the login item is available."),
                S.field("login-item-note", .string, nullable: true, update: .push, doc: "Hint text."),
                S.field("update.status", .enumeration(["idle", "checking", "available", "ready", "failed", "unavailable"]), update: .push, doc: "Update status."),
                S.field("update.version", .string, update: .push, doc: "Available version."),
                S.field("update.notes-url", .string, update: .push, doc: "URL of the release notes."),
                S.field("update.last-check", .value, nullable: true, update: .push, doc: "Time of the last check."),
                S.field("update.error", .string, nullable: true, update: .push, doc: "Last error message."),
            ],
            validIn: ["topLevel", "surfaceBody", "elementBody", "actions", "menu", "commandCenterItems", "wmBlock"]
        ),
        ContextRootSchema(
            name: "event",
            fields: [],
            validIn: ["actions"]
        ),
        ContextRootSchema(
            name: "toast",
            fields: [
                S.field("title", .string, update: .push, doc: "Title."),
                S.field("body", .string, update: .push, doc: "Text."),
                S.field("icon", .string, update: .push, doc: "Symbol."),
                S.field("kind", .string, update: .push, doc: "info, success, warning or error."),
                S.field("id", .identifier, update: .once, doc: "Id of the toast."),
                S.field("remaining", .number, update: .tick, doc: "Seconds until it disappears."),
                S.field("queued", .bool, update: .once, doc: "Whether it waited before appearing."),
            ],
            validIn: ["surfaceBody", "elementBody"]
        ),
    ]
}
