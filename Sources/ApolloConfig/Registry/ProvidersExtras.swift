enum ProvidersExtras {
    private typealias S = ProviderSupport

    static let all: [ProviderSchema] = [timer, clipboard, files, drives, photos, networkInfo, display, wallpaper]

    static func tagged(_ schema: ProviderSchema) -> ProviderSchema {
        var copy = schema
        copy.actions = copy.actions.map { action in
            var action = action
            action.feature = schema.feature
            return action
        }
        copy.events = copy.events.map { event in
            var event = event
            event.feature = schema.feature
            return event
        }
        copy.settings = copy.settings.map { setting in
            var setting = setting
            setting.feature = schema.feature
            return setting
        }
        return copy
    }

    static let timerModes = ["standard", "stopwatch", "pomodoro"]
    static let timerPhases = ["focus", "short-break", "long-break"]

    static let timer = tagged(ProviderSchema(
        id: "timer",
        feature: "timer",
        fields: [
            S.field("mode", .enumeration(timerModes), update: .push, doc: "standard, stopwatch or pomodoro."),
            S.field("running", .bool, update: .push, doc: "Whether the time runs."),
            S.field("remaining", .number, nullable: true, update: .tick, doc: "Seconds left, #null for the stopwatch."),
            S.field("elapsed", .number, update: .tick, doc: "Seconds run since the start, pauses left out."),
            S.field("duration", .number, nullable: true, update: .push, doc: "Length of the running phase in s, #null for the stopwatch."),
            S.field("phase", .enumeration(timerPhases), update: .push, doc: "Pomodoro phase: focus, short-break or long-break."),
            S.field("round", .number, update: .push, doc: "Focus round within four, from 1."),
        ],
        actions: [
            S.action("timer.start", [S.arg("minutes", .number, required: false, doc: "Length from 1 to 600; switches to the standard timer and starts over.")], doc: "Starts the timer, or goes on after a pause."),
            S.action("timer.pause", doc: "Pauses the timer."),
            S.action("timer.resume", doc: "Goes on after a pause."),
            S.action("timer.reset", doc: "Back to the start of the phase."),
            S.action("timer.set-mode", [
                S.arg("mode", .enumeration(timerModes), doc: "standard, stopwatch or pomodoro."),
                S.arg("minutes", .number, required: false, doc: "Length of the standard timer, 1 to 600."),
            ], doc: "Switches the mode; ignored while the same mode runs or is paused."),
        ],
        events: [
            S.event("timer.finished", [
                S.field("mode", .string, update: .once, doc: "Mode that finished."),
                S.field("phase", .string, update: .once, doc: "Phase that finished."),
                S.field("duration", .number, update: .once, doc: "Length of the finished phase in s."),
            ], doc: "The timer or a pomodoro phase reached zero, also with every surface closed."),
        ],
        doc: "One timer for the whole shell: timer, stopwatch, pomodoro."
    ))

    static let clipboard = tagged(ProviderSchema(
        id: "clipboard",
        feature: "clipboard",
        fields: [
            S.field("history", .list, update: .push, doc: "Copied texts, newest first, at most 20: text, date. Kept in memory only, without what password managers mark as secret."),
        ],
        actions: [
            S.action("clipboard.remove", [S.arg("text", .string, doc: "Entry to drop.")], doc: "Removes an entry from the history."),
            S.action("clipboard.clear", doc: "Empties the history."),
        ],
        doc: "Clipboard history."
    ))

    static let files = tagged(ProviderSchema(
        id: "files",
        feature: "recent-files",
        fields: [
            S.field("recent", .list, update: .push, doc: "Files and folders used in the last 7 days, newest first: path, name, icon, date. Read when first asked for."),
        ],
        doc: "Recently used files from Spotlight."
    ))

    static let drives = tagged(ProviderSchema(
        id: "drives",
        feature: "drives",
        fields: [
            S.field("list", .list, update: .push, doc: "Mounted volumes: name, path, icon, ejectable, total, free, used."),
        ],
        actions: [
            S.action("drives.eject", [S.arg("path", .path, doc: "Mount point of the volume.")], doc: "Unmounts and ejects a volume."),
        ],
        events: [S.event("drives.changed", doc: "A volume was mounted or ejected.")],
        doc: "Mounted drives."
    ))

    static let photos = tagged(ProviderSchema(
        id: "photos",
        feature: "photos",
        fields: [
            S.field("by-folder", .record, update: .push, doc: "Folder as written in folders= to its pictures: path, name, image."),
        ],
        settings: [
            PropertySchema(name: "folders", type: .list, defaultValue: .list([.string("~/Pictures")]), doc: "Folders whose pictures are read, first level only."),
        ],
        doc: "Pictures of folders for photo frames."
    ))

    static let networkInfo = tagged(ProviderSchema(
        id: "network-info",
        feature: "network-info",
        fields: [
            S.field("kind", .enumeration(["wifi", "wired", "none"]), update: .push, doc: "wifi, wired or none."),
            S.field("name", .string, nullable: true, update: .push, doc: "Wi-Fi name, #null without the location permission."),
            S.field("local-address", .string, nullable: true, update: .push, doc: "Local IPv4 address."),
            S.field("public-address", .string, nullable: true, update: .push, doc: "Public address, #null while public-address=#false."),
            S.field("latency", .number, nullable: true, update: .push, doc: "Milliseconds to open a connection to 1.1.1.1:443."),
        ],
        settings: [
            PropertySchema(name: "public-address", type: .bool, defaultValue: .bool(true), doc: "Asks api.ipify.org for the public address, at most every 10 minutes."),
        ],
        doc: "Connection kind, addresses and latency, read when first asked for."
    ))

    static let display = tagged(ProviderSchema(
        id: "display",
        feature: "display",
        fields: [
            S.field("brightness", .number, nullable: true, update: .poll(seconds: 2), doc: "Brightness of the main display 0…1, #null without a display that supports it."),
        ],
        actions: [
            S.action("display.set-brightness", [S.arg("value", .number, doc: "Brightness from 0 to 1.")], doc: "Sets the brightness of every display that supports it."),
        ],
        doc: "Display brightness."
    ))

    static let wallpaper = tagged(ProviderSchema(
        id: "wallpaper",
        feature: "wallpaper",
        fields: [
            S.field("apple", .list, update: .push, doc: "Apple's wallpapers: name, path (#null while not downloaded), thumbnail."),
            S.field("current", .string, nullable: true, update: .push, doc: "Path of the wallpaper on the main screen."),
        ],
        actions: [
            S.action("wallpaper.set", [S.arg("path", .path, doc: "Picture to set.")], properties: [
                PropertySchema(name: "screen", type: .string, defaultValue: .null, doc: "Screen id; all screens without it."),
            ], doc: "Sets the wallpaper."),
            S.action("wallpaper.random", doc: "Sets a random downloaded Apple wallpaper."),
        ],
        events: [
            S.event("wallpaper.failed", [S.field("path", .string, update: .once, doc: "Picture that was not set.")], doc: "A wallpaper could not be set."),
        ],
        doc: "Apple wallpapers and the current one."
    ))

    static let systemActions: [ActionSchema] = [
        ActionSchema(name: "system.toggle-hidden-files", feature: "system-extras", doc: "Shows or hides hidden files in the Finder and relaunches it."),
        ActionSchema(name: "system.empty-trash", startsProgramsOrControlsApps: true, feature: "system-extras", doc: "Empties the trash through the Finder."),
        ActionSchema(name: "system.mission-control", feature: "system-extras", doc: "Opens Mission Control."),
        ActionSchema(name: "system.launchpad", feature: "system-extras", doc: "Opens Launchpad, or Apps on macOS 26."),
        ActionSchema(name: "system.airdrop", feature: "system-extras", doc: "Opens the AirDrop window."),
    ]

    static let systemFields: [FieldSchema] = [
        S.field("hidden-files", .bool, nullable: true, update: .poll(seconds: 30), doc: "Whether the Finder shows hidden files, #null while unknown."),
    ]

    static let batteryActions: [ActionSchema] = [
        ActionSchema(name: "battery.set-low-power", arguments: [S.arg("on", .bool, doc: "#true turns Low Power Mode on.")], feature: "system-extras", doc: "Switches Low Power Mode, asks for an administrator password."),
    ]
}
