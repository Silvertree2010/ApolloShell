enum ProvidersCore {
    private typealias S = ProviderSupport

    static let clock = ProviderSchema(
        id: "clock",
        fields: [
            S.field("now", .value, update: .tick, doc: "Current time."),
            S.field("hour", .number, update: .tick, doc: "Hour of the day, 0 to 23."),
            S.field("minute", .number, update: .tick, doc: "Minute, 0 to 59."),
            S.field("second", .number, update: .tick, doc: "Second, 0 to 59."),
            S.field("day", .number, update: .tick, doc: "Day of the month, from 1."),
            S.field("month", .number, update: .tick, doc: "Month, 1 to 12."),
            S.field("year", .number, update: .tick, doc: "Year, four digits."),
            S.field("weekday", .number, update: .tick, doc: "Day of the week, 1 = Monday."),
            S.field("time-zone", .string, update: .push, doc: "Active time zone."),
            S.field("time-zones", .list, update: .push, doc: "Known time zones sorted by offset and name, records id (IANA), name (city), offset (seconds from GMT now)."),
        ],
        settings: [
            PropertySchema(name: "first-weekday", type: .enumeration(["monday", "sunday", "system"]), defaultValue: .string("system"), allowsExpression: false, doc: "First day of the week in the calendar grid."),
        ],
        doc: "Time, date, calendar grid."
    )

    static let battery = ProviderSchema(
        id: "battery",
        fields: [
            S.field("present", .bool, update: .push, doc: "Whether a battery is present."),
            S.field("percent", .number, update: .push, doc: "Charge level 0…1."),
            S.field("charging", .bool, update: .push, doc: "Whether it is charging."),
            S.field("on-power", .bool, update: .push, doc: "Whether on power adapter."),
            S.field("full", .bool, update: .push, doc: "Whether full."),
            S.field("minutes-to-empty", .number, nullable: true, update: .push, doc: "Minutes until empty."),
            S.field("minutes-to-full", .number, nullable: true, update: .push, doc: "Minutes until full."),
            S.field("state-text", .string, update: .push, doc: "Text for the state."),
            S.field("time-text", .string, update: .push, doc: "Text for the remaining time."),
            S.field("health", .number, nullable: true, update: .poll(seconds: 2), doc: "Health 0…1."),
            S.field("cycles", .number, nullable: true, update: .poll(seconds: 2), doc: "Charge cycles."),
            S.field("low-power-mode", .bool, update: .poll(seconds: 2), doc: "Low power mode."),
            S.field("symbol", .string, update: .push, doc: "SF Symbol for the level."),
            S.field("tank-text", .string, update: .push, doc: "Text for the battery tank."),
        ],
        actions: ProvidersExtras.batteryActions,
        events: [
            S.event("battery.charger-connected", doc: "Charger connected."),
            S.event("battery.charger-disconnected", doc: "Charger disconnected."),
            S.event("battery.warning", [
                S.field("level", .string, update: .once, doc: "Warning level."),
                S.field("percent", .number, update: .once, doc: "Charge level."),
                S.field("title", .string, update: .once, doc: "Title of the notice."),
                S.field("body", .string, update: .once, doc: "Text of the notice."),
                S.field("critical", .bool, update: .once, doc: "Whether critical."),
            ], doc: "Battery below a threshold while on battery power."),
        ],
        doc: "Charge, charging state and time left."
    )

    static let network = ProviderSchema(
        id: "network",
        fields: [
            S.field("wifi.on", .bool, nullable: true, update: .poll(seconds: 5), doc: "Whether Wi-Fi is on."),
            S.field("wifi.connected", .bool, update: .poll(seconds: 5), doc: "Whether connected."),
            S.field("wifi.rssi", .number, nullable: true, update: .poll(seconds: 2), doc: "Signal strength in dBm."),
            S.field("wifi.noise", .number, nullable: true, update: .poll(seconds: 2), doc: "Noise in dBm."),
            S.field("wifi.snr", .number, nullable: true, update: .poll(seconds: 2), doc: "Signal-to-noise ratio."),
            S.field("wifi.bars", .number, update: .poll(seconds: 5), doc: "Bars 0…3."),
            S.field("wifi.quality", .string, update: .poll(seconds: 5), doc: "Quality as text."),
            S.field("wifi.tx-rate", .number, nullable: true, update: .poll(seconds: 2), doc: "Transmit rate in Mbit/s."),
            S.field("wifi.standard", .string, nullable: true, update: .poll(seconds: 2), doc: "Wi-Fi standard."),
            S.field("wifi.band", .string, nullable: true, update: .poll(seconds: 2), doc: "Frequency band."),
            S.field("wifi.channel", .string, nullable: true, update: .poll(seconds: 2), doc: "Wi-Fi channel number, #null when not connected."),
            S.field("wifi.interface", .string, nullable: true, update: .poll(seconds: 2), doc: "Interface name."),
            S.field("wifi.symbol", .string, update: .poll(seconds: 5), doc: "SF Symbol."),
        ],
        actions: [
            S.action("network.set-wifi", [S.arg("on", .bool, doc: "Desired state.")], doc: "Turns Wi-Fi on or off."),
            S.action("network.toggle-wifi", doc: "Toggles Wi-Fi."),
            S.action("network.open-settings", doc: "Opens System Settings."),
        ],
        events: [S.event("network.wifi-changed", doc: "Wi-Fi state changed.")],
        doc: "Wi-Fi, Ethernet."
    )

    static let bluetooth = ProviderSchema(
        id: "bluetooth",
        fields: [
            S.field("on", .bool, nullable: true, update: .poll(seconds: 30), doc: "Whether Bluetooth is on."),
            S.field("status", .string, update: .poll(seconds: 30), doc: "reading, ready or unavailable."),
            S.field("paired", .number, update: .poll(seconds: 30), doc: "Number of paired devices."),
            S.field("connected", .number, update: .poll(seconds: 30), doc: "Number of connected devices."),
            S.field("devices", .list, update: .poll(seconds: 10), doc: "Connected devices."),
        ],
        actions: [S.action("bluetooth.open-settings", doc: "Opens System Settings.")],
        events: [S.event("bluetooth.changed", doc: "State changed.")],
        doc: "Bluetooth and devices."
    )

    static let audio = ProviderSchema(
        id: "audio",
        fields: [
            S.field("volume", .number, update: .push, doc: "Volume 0…1."),
            S.field("muted", .bool, update: .push, doc: "Whether muted."),
            S.field("output", .record, update: .push, doc: "Output device."),
            S.field("input", .record, update: .push, doc: "Input device."),
            S.field("outputs", .list, update: .push, doc: "Available output devices."),
            S.field("inputs", .list, update: .push, doc: "Available input devices."),
            S.field("symbol", .string, update: .push, doc: "SF Symbol."),
        ],
        actions: [
            S.action("audio.set-volume", [S.arg("value", .number, doc: "Volume from 0 to 1.")], doc: "Sets the volume."),
            S.action("audio.change-volume", [S.arg("delta", .number, doc: "Added to the volume, such as 0.1 or -0.1; the result stays within 0 to 1.")], doc: "Changes the volume."),
            S.action("audio.set-muted", [S.arg("value", .bool, doc: "Muted or not.")], doc: "Sets mute."),
            S.action("audio.toggle-mute", doc: "Toggles mute."),
            S.action("audio.select-output", [S.arg("id", .string, doc: "Device ID.")], doc: "Selects the output device."),
            S.action("audio.select-input", [S.arg("id", .string, doc: "Device ID.")], doc: "Selects the input device."),
            S.action("audio.set-input-volume", [S.arg("value", .number, doc: "Input volume from 0 to 1.")], doc: "Sets the input volume."),
            S.action("audio.set-input-muted", [S.arg("value", .bool, doc: "Muted or not.")], doc: "Mutes the input."),
        ],
        events: [
            S.event("audio.volume-changed", [
                S.field("volume", .number, update: .once, doc: "New volume."),
                S.field("muted", .bool, update: .once, doc: "New mute state."),
            ], doc: "Volume or mute changed."),
            S.event("audio.output-changed", [S.field("name", .string, update: .once, doc: "New device.")], doc: "Output device changed."),
            S.event("audio.input-changed", [S.field("name", .string, update: .once, doc: "New device.")], doc: "Input device changed."),
        ],
        doc: "Volume, devices."
    )

    static let media = ProviderSchema(
        id: "media",
        fields: [
            S.field("available", .bool, update: .push, doc: "Whether the adapter is running."),
            S.field("playing", .bool, update: .push, doc: "Whether something is playing."),
            S.field("title", .string, nullable: true, update: .push, doc: "Title of the playing track, #null when nothing plays."),
            S.field("artist", .string, nullable: true, update: .push, doc: "Artist of the playing track."),
            S.field("album", .string, nullable: true, update: .push, doc: "Album of the playing track."),
            S.field("artwork", .value, nullable: true, update: .push, doc: "Cover image for image or background-image, #null without one."),
            S.field("duration", .number, nullable: true, update: .push, doc: "Duration in s."),
            S.field("elapsed", .number, nullable: true, update: .tick, doc: "Elapsed time in s."),
            S.field("progress", .number, nullable: true, update: .push, doc: "Progress 0…1."),
            S.field("unavailable", .string, nullable: true, update: .push, doc: "Reason for unavailability."),
            S.field("app", .string, nullable: true, update: .push, doc: "Bundle id of the app that plays."),
            S.field("app-name", .string, nullable: true, update: .push, doc: "Name of the source."),
            S.field("app-icon", .value, nullable: true, update: .push, doc: "Symbol of the source."),
            S.field("kind", .string, update: .push, doc: "music or video."),
        ],
        actions: [
            S.action("media.play-pause", doc: "Toggles playback."),
            S.action("media.next", doc: "Next track."),
            S.action("media.previous", doc: "Previous track."),
            S.action("media.seek", [S.arg("seconds", .number, doc: "Target time in s.")], doc: "Seeks to a position."),
            S.action("media.open-app", doc: "Opens the source."),
        ],
        events: [S.event("media.track-changed", doc: "Track changed.")],
        doc: "What is playing."
    )

    static let perf = ProviderSchema(
        id: "perf",
        fields: [
            S.field("cpu", .number, update: .poll(seconds: 2), doc: "CPU load 0…1."),
            S.field("memory", .number, update: .poll(seconds: 2), doc: "Memory load 0…1."),
            S.field("net-down", .number, update: .poll(seconds: 2), doc: "Bytes/s down."),
            S.field("net-up", .number, update: .poll(seconds: 2), doc: "Bytes/s up."),
            S.field("live.cpu", .number, update: .tick, doc: "Live CPU load."),
            S.field("live.gpu", .number, nullable: true, update: .tick, doc: "Live GPU load."),
            S.field("live.cpu-history", .list, update: .tick, doc: "Last 30 CPU values."),
            S.field("live.gpu-history", .list, update: .tick, doc: "Last 30 GPU values."),
            S.field("live.memory-used", .number, update: .tick, doc: "Used memory in bytes."),
            S.field("live.memory-total", .number, update: .tick, doc: "Total memory in bytes."),
            S.field("live.memory", .number, update: .tick, doc: "Memory load 0…1."),
            S.field("live.disk-used", .number, update: .tick, doc: "Used space in bytes."),
            S.field("live.disk-total", .number, update: .tick, doc: "Total space in bytes."),
            S.field("live.disk", .number, update: .tick, doc: "Disk usage 0…1."),
            S.field("live.net-down", .number, update: .tick, doc: "Bytes/s down."),
            S.field("live.net-up", .number, update: .tick, doc: "Bytes/s up."),
            S.field("live.net-history", .list, update: .tick, doc: "Last 30 network records."),
            S.field("live.net-total-down", .number, update: .tick, doc: "Bytes since the first request."),
            S.field("live.net-total-up", .number, update: .tick, doc: "Bytes since the first request."),
            S.field("chip", .string, update: .once, doc: "Chip name."),
            S.field("cores", .number, update: .once, doc: "Number of active CPU cores."),
            S.field("gpu-cores", .number, nullable: true, update: .once, doc: "GPU cores."),
        ],
        doc: "CPU, GPU, memory, disk, network speed."
    )
}
