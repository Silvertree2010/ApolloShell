enum Features {
    static let all: [FeatureSchema] = [
        FeatureSchema(name: "core", since: "0.2.0"),
        FeatureSchema(name: "wm", since: "0.2.0"),
        FeatureSchema(name: "marketplace", since: "0.2.0"),
        FeatureSchema(name: "script-sources", since: "0.2.0"),
        FeatureSchema(name: "ipc", since: "0.2.0"),
        FeatureSchema(name: "fusion", since: "0.2.1"),
        FeatureSchema(name: "timer", since: "0.2.1"),
        FeatureSchema(name: "clipboard", since: "0.2.1"),
        FeatureSchema(name: "recent-files", since: "0.2.1"),
        FeatureSchema(name: "drives", since: "0.2.1"),
        FeatureSchema(name: "photos", since: "0.2.1"),
        FeatureSchema(name: "network-info", since: "0.2.1"),
        FeatureSchema(name: "display", since: "0.2.1"),
        FeatureSchema(name: "system-extras", since: "0.2.1"),
        FeatureSchema(name: "calc", since: "0.2.1"),
        FeatureSchema(name: "wallpaper", since: "0.2.1"),
    ] + MenuBarRegistry.features

    static let reservedProviderNames: Set<String> = [
        "fusion", "calendar-events", "reminders", "notifications",
        "focus", "location", "lua", "plugins", "windows", "input", "camera", "microphone", "canvas",
    ]

    static let fixedRoots: Set<String> = [
        "var", "self", "surface", "surfaces", "screen", "theme", "shell", "event", "toast",
    ]
}
