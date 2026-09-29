enum Features {
    static let all: [FeatureSchema] = [
        FeatureSchema(name: "core", since: "0.2.0"),
        FeatureSchema(name: "wm", since: "0.2.0"),
        FeatureSchema(name: "marketplace", since: "0.2.0"),
        FeatureSchema(name: "script-sources", since: "0.2.0"),
        FeatureSchema(name: "ipc", since: "0.2.0"),
    ] + MenuBarRegistry.features

    static let reservedProviderNames: Set<String> = [
        "fusion", "timer", "clipboard", "files", "drives", "photos",
        "network-info", "display", "wallpaper", "calendar-events", "reminders", "notifications",
        "focus", "location", "lua", "plugins", "windows", "input", "camera", "microphone", "canvas",
    ]

    static let fixedRoots: Set<String> = [
        "var", "self", "surface", "surfaces", "screen", "theme", "shell", "event", "toast",
    ]
}
