enum ProvidersMore {
    private typealias S = ProviderSupport

    static let spaces = ProviderSchema(
        id: "spaces",
        fields: [
            S.field("list", .list, update: .push, doc: "Desktops of the context."),
            S.field("current", .number, update: .push, doc: "Index of the active desktop."),
            S.field("count", .number, update: .push, doc: "Number of desktops."),
        ],
        actions: [
            S.action("spaces.switch", [S.arg("index", .number, doc: "Target index.")], doc: "Switches to a desktop."),
            S.action("spaces.next", doc: "Next desktop."),
            S.action("spaces.previous", doc: "Previous desktop."),
            S.action("spaces.mission-control", doc: "Opens Mission Control."),
        ],
        events: [S.event("spaces.changed", doc: "Desktop changed.")],
        permissions: ["accessibility"],
        doc: "Desktops per screen."
    )

    static let apps = ProviderSchema(
        id: "apps",
        fields: [
            S.field("all", .list, update: .push, doc: "Installed apps."),
            S.field("running", .list, update: .push, doc: "Running apps."),
            S.field("dock", .list, update: .push, doc: "Dock list."),
            S.field("favorites", .list, update: .push, doc: "Launcher favorites."),
            S.field("frontmost", .record, nullable: true, update: .push, doc: "Frontmost app."),
            S.field("file-manager", .record, update: .push, doc: "Resolved file manager."),
            S.field("file-managers", .list, update: .push, doc: "Detected file managers."),
        ],
        actions: [
            S.action("apps.click", [S.arg("app", .value, doc: "App record or bundle ID.")], properties: [PropertySchema(name: "modifiers", type: .list, defaultValue: .list([]), doc: "Held modifiers.")], doc: "Click as in the Dock.", startsProgramsOrControlsApps: true),
            S.action("apps.launch", [S.arg("app", .value, doc: "App record or bundle ID.")], doc: "Launches or brings to the front.", startsProgramsOrControlsApps: true),
            S.action("apps.new-window", [S.arg("app", .value, doc: "App record or bundle ID.")], doc: "New window.", startsProgramsOrControlsApps: true),
            S.action("apps.cycle-windows", [S.arg("app", .value, doc: "App record or bundle ID."), S.arg("direction", .enumeration(["up", "down"]), doc: "up for the next window, down for the previous.")], doc: "Cycles through windows.", startsProgramsOrControlsApps: true),
            S.action("apps.open-files", [S.arg("app", .value, doc: "App record or bundle ID."), S.arg("files", .list, doc: "List of file paths.")], doc: "Opens files with the app.", startsProgramsOrControlsApps: true),
            S.action("apps.show-all-windows", [S.arg("app", .value, doc: "App record or bundle ID.")], doc: "App Exposé.", startsProgramsOrControlsApps: true),
            S.action("apps.hide", [S.arg("app", .value, doc: "App record or bundle ID.")], doc: "Hides the app.", startsProgramsOrControlsApps: true),
            S.action("apps.unhide", [S.arg("app", .value, doc: "App record or bundle ID.")], doc: "Unhides the app.", startsProgramsOrControlsApps: true),
            S.action("apps.quit", [S.arg("app", .value, doc: "App record or bundle ID.")], doc: "Quits the app.", startsProgramsOrControlsApps: true),
            S.action("apps.force-quit", [S.arg("app", .value, doc: "App record or bundle ID.")], doc: "Force quits the app.", startsProgramsOrControlsApps: true),
            S.action("apps.reveal", [S.arg("app", .value, doc: "App record or bundle ID.")], properties: [PropertySchema(name: "in", type: .enumeration(["file-manager", "finder"]), defaultValue: .string("file-manager"), doc: "Where to show the app: file-manager or finder.")], doc: "Reveals the app in the file manager."),
            S.action("apps.refresh", doc: "Rereads catalog, usage and favorites."),
            S.action("apps.dock-move", [S.arg("from", .string, doc: "Source key."), S.arg("to", .string, doc: "Target key.")], doc: "Drags in the Dock."),
            S.action("apps.dock-pin", [S.arg("app", .value, doc: "App record or bundle ID.")], doc: "Keeps in the Dock."),
            S.action("apps.dock-unpin", [S.arg("app", .value, doc: "App record or bundle ID.")], doc: "Removes from the Dock."),
            S.action("apps.favorite-add", [S.arg("app", .value, doc: "App record or bundle ID.")], doc: "Adds to favorites."),
            S.action("apps.favorite-remove", [S.arg("app", .value, doc: "App record or bundle ID.")], doc: "Removes from favorites."),
            S.action("apps.favorite-move", [S.arg("from", .number, doc: "Source position."), S.arg("to", .number, doc: "Target position.")], doc: "Reorders a favorite."),
            S.action("apps.run-command", [S.arg("app", .value, doc: "App record or bundle ID."), S.arg("command", .string, doc: "Menu command.")], doc: "Runs a menu command via Accessibility.", startsProgramsOrControlsApps: true),
        ],
        events: [
            S.event("apps.launched", [S.field("app", .value, update: .once, doc: "Launched app.")], doc: "App launched."),
            S.event("apps.terminated", [S.field("app", .value, update: .once, doc: "Quit app.")], doc: "App quit."),
            S.event("apps.activated", [S.field("app", .value, update: .once, doc: "Activated app.")], doc: "App activated."),
        ],
        settings: [
            PropertySchema(name: "file-manager", type: .string, defaultValue: .null, doc: "Preferred file manager, #null for automatic."),
        ],
        doc: "Installed, running and pinned apps, Dock behavior."
    )

    static let weather = ProviderSchema(
        id: "weather",
        fields: [
            S.field("status", .string, update: .push, doc: "no-place, loading, ready or failed."),
            S.field("place", .record, nullable: true, update: .push, doc: "Selected place."),
            S.field("current", .record, nullable: true, update: .push, doc: "Current weather."),
            S.field("today", .record, nullable: true, update: .push, doc: "Daily values."),
            S.field("hourly-strip", .list, update: .push, doc: "12 entries 2 h apart."),
            S.field("days", .list, update: .push, doc: "Next 7 days."),
            S.field("updated", .value, nullable: true, update: .push, doc: "Last fetch."),
            S.field("time-zone", .string, nullable: true, update: .push, doc: "Time zone of the place, for the zone argument of the date filter."),
            S.field("stale", .bool, update: .push, doc: "Whether the data is stale."),
            S.field("attribution", .record, update: .push, doc: "Data source to credit, with text and url."),
            S.field("capabilities", .record, update: .push, doc: "What the provider supplies."),
            S.field("search-results", .list, update: .push, doc: "Places found."),
            S.field("search-status", .string, update: .push, doc: "idle, searching, done or failed."),
        ],
        actions: [
            S.action("weather.refresh", doc: "Fetches again."),
            S.action("weather.search", [S.arg("text", .string, doc: "Search text.")], doc: "Searches for a place."),
            S.action("weather.clear-search", doc: "Resets the search."),
        ],
        settings: [
            PropertySchema(name: "source", type: .enumeration(["open-meteo", "met-norway", "wttr"]), defaultValue: .string("open-meteo"), doc: "Weather provider."),
            PropertySchema(name: "place", type: .record, defaultValue: .null, doc: "Record name/latitude/longitude or #null."),
        ],
        doc: "Weather from three providers, place search."
    )

    static let keyboard = ProviderSchema(
        id: "keyboard",
        fields: [
            S.field("source", .record, update: .push, doc: "Active input source."),
            S.field("sources", .list, update: .push, doc: "Available input sources."),
            S.field("caps-lock", .bool, update: .push, doc: "Whether Caps Lock is on."),
        ],
        actions: [
            S.action("keyboard.next-source", doc: "Next input source."),
            S.action("keyboard.select", [S.arg("id", .string, doc: "Id of the source.")], doc: "Selects an input source."),
        ],
        events: [S.event("keyboard.source-changed", doc: "Input source changed.")],
        doc: "Input source."
    )

    static let window = ProviderSchema(
        id: "window",
        fields: [
            S.field("app", .record, nullable: true, update: .push, doc: "App of the frontmost window."),
            S.field("title", .string, nullable: true, update: .push, doc: "Window title."),
            S.field("fullscreen", .bool, update: .push, doc: "Whether full screen is active."),
        ],
        permissions: ["accessibility"],
        doc: "Frontmost window."
    )

    static let screens = ProviderSchema(
        id: "screens",
        fields: [
            S.field("list", .list, update: .push, doc: "One record per screen: id, name, main, index, frame and visible frame, scale."),
            S.field("main", .record, update: .push, doc: "Main screen."),
        ],
        events: [S.event("screens.changed", [S.field("screens", .list, update: .once, doc: "New screen list.")], doc: "Screens changed.")],
        doc: "Connected screens and their frames."
    )

    static let system = ProviderSchema(
        id: "system",
        fields: [
            S.field("dark-mode", .bool, update: .push, doc: "Whether dark mode is on."),
            S.field("night-shift", .bool, nullable: true, update: .push, doc: "Night Shift."),
            S.field("microphone-muted", .bool, nullable: true, update: .push, doc: "Whether the microphone is muted."),
            S.field("show-desktop-available", .bool, update: .push, doc: "Whether the shortcut is active."),
            S.field("accent-color", .string, update: .push, doc: "System accent color as hex."),
            S.field("reduce-motion", .bool, update: .push, doc: "Reduce motion."),
            S.field("reduce-transparency", .bool, update: .push, doc: "Reduce transparency."),
            S.field("user-name", .string, update: .once, doc: "Short name."),
            S.field("full-name", .string, update: .once, doc: "Full name."),
            S.field("user-image", .value, nullable: true, update: .once, doc: "Profile picture."),
            S.field("host-name", .string, update: .once, doc: "Computer name."),
            S.field("model", .string, update: .once, doc: "Product name of the Mac, such as MacBook Pro."),
            S.field("chip", .string, update: .once, doc: "Name of the processor, such as Apple M3."),
            S.field("macos-version", .string, update: .once, doc: "macOS version."),
            S.field("kernel-version", .string, update: .once, doc: "Kernel version."),
            S.field("uptime", .number, update: .tick, doc: "Uptime in s."),
            S.field("apple-dock-hidden", .bool, update: .push, doc: "Whether Apple's Dock is hidden."),
            MenuBarRegistry.appleMenuBarHidden,
        ] + ProvidersExtras.systemFields,
        actions: [
            S.action("system.set-dark-mode", [S.arg("value", .bool, doc: "#true for dark, #false for light.")], doc: "Sets the appearance."),
            S.action("system.toggle-dark-mode", doc: "Toggles the appearance."),
            S.action("system.set-night-shift", [S.arg("value", .bool, doc: "#true turns Night Shift on.")], doc: "Sets Night Shift."),
            S.action("system.toggle-night-shift", doc: "Toggles Night Shift."),
            S.action("system.set-microphone-muted", [S.arg("value", .bool, doc: "#true mutes the microphone.")], doc: "Mutes the microphone."),
            S.action("system.toggle-microphone", doc: "Toggles the microphone."),
            S.action("system.screenshot", doc: "Opens the screenshot toolbar."),
            S.action("system.color-picker", doc: "Opens the color picker."),
            S.action("system.show-desktop", doc: "Shows the desktop."),
            S.action("system.lock", doc: "Locks the screen."),
            S.action("system.display-sleep", doc: "Turns the display off."),
            S.action("system.hide-apps", properties: [PropertySchema(name: "keep-frontmost", type: .bool, defaultValue: .bool(false), doc: "Keeps the frontmost app.")], doc: "Hides other apps.", startsProgramsOrControlsApps: true),
            S.action("system.open-settings", [S.arg("pane", .string, required: false, doc: "Pane such as wifi, sound or battery; without it the app opens.")], doc: "Opens System Settings."),
            S.action("system.hide-apple-dock", [S.arg("value", .bool, doc: "#true hides the Dock.")], doc: "Hides Apple's Dock."),
            MenuBarRegistry.hideAppleMenuBar,
        ] + ProvidersExtras.systemActions,
        events: [
            S.event("system.appearance-changed", doc: "Appearance changed."),
            S.event("system.color-copied", [S.field("hex", .string, update: .once, doc: "Copied color.")], doc: "Color copied."),
            S.event("shortcuts.failed", [S.field("name", .string, update: .once, doc: "Name of the shortcut.")], doc: "run-shortcut failed."),
        ],
        doc: "Appearance, Night Shift, microphone, user, computer, system actions."
    )

    static let session = ProviderSchema(
        id: "session",
        actions: [
            S.action("session.logout", doc: "Signs out.", startsProgramsOrControlsApps: true),
            S.action("session.restart", doc: "Restarts the Mac.", startsProgramsOrControlsApps: true),
            S.action("session.shutdown", doc: "Shuts down.", startsProgramsOrControlsApps: true),
            S.action("session.sleep", doc: "Puts the Mac to sleep."),
            S.action("session.lock", doc: "Locks the screen."),
        ],
        permissions: ["automation"],
        doc: "Log out, sleep, restart, shut down, lock."
    )

    static let power = ProviderSchema(
        id: "power",
        fields: [
            S.field("keep-awake", .bool, update: .push, doc: "Whether the Mac is kept awake."),
            S.field("keep-awake-since", .value, nullable: true, update: .push, doc: "Since when."),
            S.field("lid", .string, update: .push, doc: "off, on, pending or declined."),
            S.field("keep-awake-text", .string, update: .tick, doc: "Subtitle as in 0.1.4.2."),
            S.field("lid-rule-installed", .bool, update: .poll(seconds: 2), doc: "Whether the sudoers rule is installed."),
        ],
        actions: [
            S.action("power.set-keep-awake", [S.arg("value", .bool, doc: "#true keeps the Mac awake.")], doc: "Sets keep-awake."),
            S.action("power.toggle-keep-awake", doc: "Toggles keep-awake."),
            S.action("power.remove-lid-rule", doc: "Removes the sudoers rule."),
        ],
        events: [
            S.event("power.keep-awake-stopped", [S.field("reason", .string, update: .once, doc: "Reason, e.g. battery.")], doc: "Keep-awake ended."),
            S.event("power.lid-still-awake", doc: "Closed-lid mode declined."),
        ],
        settings: [
            PropertySchema(name: "lid-closed", type: .bool, defaultValue: .null, doc: "Keep awake with the lid closed too."),
        ],
        doc: "Keep-awake, also with the lid closed."
    )

    static let permissions = ProviderSchema(
        id: "permissions",
        fields: [
            S.field("accessibility", .bool, update: .poll(seconds: 2), doc: "Accessibility allowed."),
            S.field("automation", .bool, nullable: true, update: .poll(seconds: 2), doc: "Automation allowed."),
            S.field("screen-recording", .bool, update: .poll(seconds: 2), doc: "Screen recording allowed."),
            MenuBarRegistry.screenCaptureBypass,
        ],
        actions: [
            S.action("permissions.request-accessibility", doc: "Requests Accessibility access."),
            S.action("permissions.open", [S.arg("kind", .enumeration(["accessibility", "automation", "screen-recording"]), doc: "Permission whose settings page opens.")], doc: "Opens System Settings for the permission."),
        ],
        doc: "Which macOS permissions the shell has."
    )

    static let shortcuts = ProviderSchema(
        id: "shortcuts",
        fields: [S.field("list", .list, update: .poll(seconds: 5), doc: "Shortcuts from the Shortcuts app.")],
        doc: "Shortcuts from the Shortcuts app."
    )

    static let marketplace = ProviderSchema(
        id: "marketplace",
        fields: [
            S.field("status", .string, update: .push, doc: "idle, loading, loaded or failed."),
            S.field("error", .string, nullable: true, update: .push, doc: "Last error of an action, until marketplace.dismiss."),
            S.field("load-error", .string, nullable: true, update: .push, doc: "Why the list could not be loaded, only with status failed."),
            S.field("offline", .bool, update: .push, doc: "True while error is the note that a refresh failed and the loaded list may be outdated."),
            S.field("items", .list, update: .push, doc: "Available entries."),
            S.field("user", .record, nullable: true, update: .push, doc: "Signed-in user."),
            S.field("sign-in", .record, update: .push, doc: "Sign-in status."),
            S.field("mine", .list, update: .push, doc: "Own submissions."),
            S.field("queue", .list, update: .push, doc: "Queue for admins."),
            S.field("message", .string, nullable: true, update: .push, doc: "Last message."),
            S.field("local", .list, update: .push, doc: "Local themes to submit: id, name, problem, css."),
        ],
        actions: [
            S.action("marketplace.refresh", doc: "Reloads the catalog from the server."),
            S.action("marketplace.get", [S.arg("id", .string, doc: "Id of the catalog entry.")], doc: "Installs a theme from the catalog."),
            S.action("marketplace.update", [S.arg("id", .string, doc: "Id of the catalog entry.")], doc: "Installs the newest version of an installed theme."),
            S.action("marketplace.use", [S.arg("id", .string, doc: "Id of the catalog entry.")], doc: "Switches to an installed theme."),
            S.action("marketplace.remove", [S.arg("id", .string, doc: "Id of the catalog entry.")], doc: "Uninstalls a theme."),
            S.action("marketplace.sign-in", doc: "Signs in."),
            S.action("marketplace.cancel-sign-in", doc: "Cancels sign-in."),
            S.action("marketplace.copy-code", doc: "Copies the sign-in code."),
            S.action("marketplace.sign-out", doc: "Signs out."),
            S.action("marketplace.delete-account", doc: "Deletes the account."),
            S.action("marketplace.submit", [S.arg("theme-id", .string, doc: "Id of a local theme.")], properties: [PropertySchema(name: "accept-terms", type: .bool, defaultValue: .bool(false), doc: "Accepts CC0 and the terms of use.")], doc: "Submits a local theme for review."),
            S.action("marketplace.new-version", [S.arg("id", .string, doc: "Id of your catalog entry."), S.arg("source", .string, doc: "Id of the local theme with the new version.")], properties: [PropertySchema(name: "accept-terms", type: .bool, defaultValue: .bool(false), doc: "Accepts CC0 and the terms of use.")], doc: "Submits a new version."),
            S.action("marketplace.delete", [S.arg("id", .string, doc: "Id of your catalog entry.")], doc: "Deletes your own entry from the catalog."),
            S.action("marketplace.report", [S.arg("id", .string, doc: "Id of the catalog entry."), S.arg("reason", .string, doc: "Why the entry is reported.")], doc: "Reports an entry to the moderators."),
            S.action("marketplace.approve", [S.arg("id", .string, doc: "Id of the catalog entry."), S.arg("version", .string, doc: "Version under review.")], doc: "Moderators: publishes a version under review."),
            S.action("marketplace.reject", [S.arg("id", .string, doc: "Id of the catalog entry."), S.arg("version", .string, doc: "Version under review."), S.arg("reason", .string, doc: "Why, shown to the author.")], doc: "Moderators: declines a version under review."),
            S.action("marketplace.hide", [S.arg("id", .string, doc: "Id of the catalog entry."), S.arg("reason", .string, doc: "Why, shown to the author.")], doc: "Moderators: hides an entry from the catalog."),
            S.action("marketplace.unhide", [S.arg("id", .string, doc: "Id of the catalog entry.")], doc: "Makes visible."),
            S.action("marketplace.ban", [S.arg("user-id", .string, doc: "Id of the user."), S.arg("reason", .string, doc: "Why the user is banned.")], doc: "Bans the user."),
            S.action("marketplace.dismiss", doc: "Dismisses message and error."),
            S.action("marketplace.open", doc: "Opens the Marketplace window."),
        ],
        settings: [PropertySchema(name: "enabled", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "Turns the Marketplace on or off.")],
        doc: "Themes, configs and packages from the Marketplace."
    )

    static let wm = ProviderSchema(
        id: "wm",
        feature: "wm",
        fields: [
            S.field("enabled", .bool, update: .push, doc: "Whether the window manager is running."),
            S.field("layout", .string, update: .push, doc: "Active layout."),
            S.field("focused", .record, nullable: true, update: .push, doc: "Focused window."),
            S.field("windows", .list, update: .push, doc: "All windows."),
            S.field("desktop", .number, update: .push, doc: "Current desktop."),
            S.field("workspace", .number, update: .push, doc: "Current workspace."),
            S.field("workspaces", .list, update: .push, doc: "Workspaces, only with apple-desktops=#false."),
            S.field("tab-bars", .list, update: .push, doc: "Tab bars."),
        ],
        actions: [
            S.action("wm.focus", [S.arg("direction", .string, doc: "left, right, up, down or next.")], doc: "Moves focus."),
            S.action("wm.swap", [S.arg("direction", .string, doc: "left, right, up or down.")], doc: "Swaps windows."),
            S.action("wm.split", doc: "Switches the split direction of the focused window."),
            S.action("wm.equalize", doc: "Balances sizes."),
            S.action("wm.grow", [S.arg("width", .number, doc: "Change of the width as a fraction, -1 to 1."), S.arg("height", .number, doc: "Change of the height as a fraction, -1 to 1.")], doc: "Resizes the focused window."),
            S.action("wm.terminal", doc: "Opens a terminal.", startsProgramsOrControlsApps: true),
            S.action("wm.group", doc: "Groups the focused window with its neighbor, or takes it out of its group."),
            S.action("wm.tab", [S.arg("direction", .string, doc: "next or prev.")], doc: "Switches tab."),
            S.action("wm.tab-move", [S.arg("direction", .string, doc: "next or prev.")], doc: "Moves a tab."),
            S.action("wm.group-app", doc: "Groups an app."),
            S.action("wm.float", doc: "Makes floating."),
            S.action("wm.fullscreen", doc: "Full screen."),
            S.action("wm.close", doc: "Closes a window."),
            S.action("wm.desktop", [S.arg("index", .number, doc: "Target desktop.")], doc: "Switches desktop."),
            S.action("wm.send", [S.arg("index", .number, doc: "Target desktop.")], doc: "Sends a window."),
            S.action("wm.scratchpad", doc: "Opens the scratchpad."),
            S.action("wm.display", [S.arg("direction", .string, doc: "next or prev.")], doc: "Switches screen."),
            S.action("wm.move-display", [S.arg("direction", .string, doc: "next or prev.")], doc: "Moves a window to another screen."),
            S.action("wm.layout", [S.arg("kind", .enumeration(["dwindle", "canvas"]), doc: "Layout to switch to: dwindle or canvas.")], doc: "Toggles the layout."),
            S.action("wm.toggle", doc: "Window manager on/off."),
            S.action("wm.focus-window", [S.arg("id", .string, doc: "Window ID.")], doc: "Focuses a window."),
        ],
        events: [
            S.event("wm.focus-changed", doc: "Focus changed."),
            S.event("wm.layout-changed", doc: "Layout changed."),
            S.event("wm.window-opened", doc: "Window opened."),
            S.event("wm.window-closed", doc: "Window closed."),
            S.event("wm.workspace-changed", doc: "Workspace changed."),
        ],
        permissions: ["accessibility"],
        doc: "Tiling window manager."
    )
}
