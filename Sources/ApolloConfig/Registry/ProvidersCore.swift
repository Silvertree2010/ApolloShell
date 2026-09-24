enum ProvidersCore {
    private typealias S = ProviderSupport

    static let clock = ProviderSchema(
        id: "clock",
        fields: [
            S.field("now", .value, update: .tick, doc: "aktueller Zeitpunkt."),
            S.field("hour", .number, update: .tick, doc: "Stunde."),
            S.field("minute", .number, update: .tick, doc: "Minute."),
            S.field("second", .number, update: .tick, doc: "Sekunde."),
            S.field("day", .number, update: .tick, doc: "Tag."),
            S.field("month", .number, update: .tick, doc: "Monat."),
            S.field("year", .number, update: .tick, doc: "Jahr."),
            S.field("weekday", .number, update: .tick, doc: "Wochentag, 1 = Montag."),
            S.field("time-zone", .string, update: .push, doc: "aktive Zeitzone."),
        ],
        settings: [
            PropertySchema(name: "first-weekday", type: .enumeration(["monday", "sunday", "system"]), defaultValue: .string("system"), allowsExpression: false, doc: "erster Wochentag des Kalenderrasters."),
        ],
        doc: "Zeit, Datum, Kalenderraster."
    )

    static let battery = ProviderSchema(
        id: "battery",
        fields: [
            S.field("present", .bool, update: .push, doc: "ob ein Akku vorhanden ist."),
            S.field("percent", .number, update: .push, doc: "Ladestand 0…1."),
            S.field("charging", .bool, update: .push, doc: "ob geladen wird."),
            S.field("on-power", .bool, update: .push, doc: "ob am Netz."),
            S.field("full", .bool, update: .push, doc: "ob voll."),
            S.field("minutes-to-empty", .number, nullable: true, update: .push, doc: "Minuten bis leer."),
            S.field("minutes-to-full", .number, nullable: true, update: .push, doc: "Minuten bis voll."),
            S.field("state-text", .string, update: .push, doc: "Text zum Zustand."),
            S.field("time-text", .string, update: .push, doc: "Text zur verbleibenden Zeit."),
            S.field("health", .number, nullable: true, update: .poll(seconds: 2), doc: "Gesundheit 0…1."),
            S.field("cycles", .number, nullable: true, update: .poll(seconds: 2), doc: "Ladezyklen."),
            S.field("low-power-mode", .bool, update: .poll(seconds: 2), doc: "Stromsparmodus."),
            S.field("symbol", .string, update: .push, doc: "SF-Symbol für den Stand."),
            S.field("tank-text", .string, update: .push, doc: "Text für den Akku-Tank."),
        ],
        events: [
            S.event("battery.charger-connected", doc: "Ladegerät angeschlossen."),
            S.event("battery.charger-disconnected", doc: "Ladegerät entfernt."),
            S.event("battery.warning", [
                S.field("level", .string, update: .once, doc: "Warnstufe."),
                S.field("percent", .number, update: .once, doc: "Ladestand."),
                S.field("title", .string, update: .once, doc: "Titel der Meldung."),
                S.field("body", .string, update: .once, doc: "Text der Meldung."),
                S.field("critical", .bool, update: .once, doc: "ob kritisch."),
            ], doc: "Akku unter einer Schwelle im Akkubetrieb."),
        ],
        doc: "Akku."
    )

    static let network = ProviderSchema(
        id: "network",
        fields: [
            S.field("wifi.on", .bool, nullable: true, update: .poll(seconds: 5), doc: "ob WLAN an ist."),
            S.field("wifi.connected", .bool, update: .poll(seconds: 5), doc: "ob verbunden."),
            S.field("wifi.rssi", .number, nullable: true, update: .poll(seconds: 2), doc: "Signalstärke in dBm."),
            S.field("wifi.noise", .number, nullable: true, update: .poll(seconds: 2), doc: "Rauschen in dBm."),
            S.field("wifi.snr", .number, nullable: true, update: .poll(seconds: 2), doc: "Signal-Rausch-Verhältnis."),
            S.field("wifi.bars", .number, update: .poll(seconds: 5), doc: "Balken 0…3."),
            S.field("wifi.quality", .string, update: .poll(seconds: 5), doc: "Qualität als Text."),
            S.field("wifi.tx-rate", .number, nullable: true, update: .poll(seconds: 2), doc: "Senderate in Mbit/s."),
            S.field("wifi.standard", .string, nullable: true, update: .poll(seconds: 2), doc: "WLAN-Standard."),
            S.field("wifi.band", .string, nullable: true, update: .poll(seconds: 2), doc: "Frequenzband."),
            S.field("wifi.channel", .string, nullable: true, update: .poll(seconds: 2), doc: "Kanal."),
            S.field("wifi.interface", .string, nullable: true, update: .poll(seconds: 2), doc: "Interface-Name."),
            S.field("wifi.symbol", .string, update: .poll(seconds: 5), doc: "SF-Symbol."),
        ],
        actions: [
            S.action("network.set-wifi", [S.arg("on", .bool, doc: "gewünschter Zustand.")], doc: "WLAN ein- oder ausschalten."),
            S.action("network.toggle-wifi", doc: "WLAN umschalten."),
            S.action("network.open-settings", doc: "Systemeinstellungen öffnen."),
        ],
        events: [S.event("network.wifi-changed", doc: "WLAN-Zustand geändert.")],
        doc: "WLAN, Kabel."
    )

    static let bluetooth = ProviderSchema(
        id: "bluetooth",
        fields: [
            S.field("on", .bool, nullable: true, update: .poll(seconds: 30), doc: "ob Bluetooth an ist."),
            S.field("status", .string, update: .poll(seconds: 30), doc: "reading, ready oder unavailable."),
            S.field("paired", .number, update: .poll(seconds: 30), doc: "Anzahl gekoppelter Geräte."),
            S.field("connected", .number, update: .poll(seconds: 30), doc: "Anzahl verbundener Geräte."),
            S.field("devices", .list, update: .poll(seconds: 10), doc: "verbundene Geräte."),
        ],
        actions: [S.action("bluetooth.open-settings", doc: "Systemeinstellungen öffnen.")],
        events: [S.event("bluetooth.changed", doc: "Zustand geändert.")],
        doc: "Bluetooth und Geräte."
    )

    static let audio = ProviderSchema(
        id: "audio",
        fields: [
            S.field("volume", .number, update: .push, doc: "Lautstärke 0…1."),
            S.field("muted", .bool, update: .push, doc: "ob stumm."),
            S.field("output", .record, update: .push, doc: "Ausgabegerät."),
            S.field("input", .record, update: .push, doc: "Eingabegerät."),
            S.field("outputs", .list, update: .push, doc: "verfügbare Ausgabegeräte."),
            S.field("inputs", .list, update: .push, doc: "verfügbare Eingabegeräte."),
            S.field("symbol", .string, update: .push, doc: "SF-Symbol."),
        ],
        actions: [
            S.action("audio.set-volume", [S.arg("value", .number, doc: "0…1.")], doc: "Lautstärke setzen."),
            S.action("audio.change-volume", [S.arg("delta", .number, doc: "Änderung.")], doc: "Lautstärke ändern."),
            S.action("audio.set-muted", [S.arg("value", .bool, doc: "stumm oder nicht.")], doc: "Stummschaltung setzen."),
            S.action("audio.toggle-mute", doc: "Stummschaltung umschalten."),
            S.action("audio.select-output", [S.arg("id", .string, doc: "Geräte-ID.")], doc: "Ausgabegerät wählen."),
            S.action("audio.select-input", [S.arg("id", .string, doc: "Geräte-ID.")], doc: "Eingabegerät wählen."),
            S.action("audio.set-input-volume", [S.arg("value", .number, doc: "0…1.")], doc: "Eingangslautstärke setzen."),
            S.action("audio.set-input-muted", [S.arg("value", .bool, doc: "stumm oder nicht.")], doc: "Eingang stumm schalten."),
        ],
        events: [
            S.event("audio.volume-changed", [
                S.field("volume", .number, update: .once, doc: "neue Lautstärke."),
                S.field("muted", .bool, update: .once, doc: "neuer Stummzustand."),
            ], doc: "Lautstärke oder Stumm geändert."),
            S.event("audio.output-changed", [S.field("name", .string, update: .once, doc: "neues Gerät.")], doc: "Ausgabegerät geändert."),
            S.event("audio.input-changed", [S.field("name", .string, update: .once, doc: "neues Gerät.")], doc: "Eingabegerät geändert."),
        ],
        doc: "Lautstärke, Geräte."
    )

    static let media = ProviderSchema(
        id: "media",
        fields: [
            S.field("available", .bool, update: .push, doc: "ob der Adapter läuft."),
            S.field("playing", .bool, update: .push, doc: "ob etwas läuft."),
            S.field("title", .string, nullable: true, update: .push, doc: "Titel."),
            S.field("artist", .string, nullable: true, update: .push, doc: "Interpret."),
            S.field("album", .string, nullable: true, update: .push, doc: "Album."),
            S.field("artwork", .value, nullable: true, update: .push, doc: "Cover."),
            S.field("duration", .number, nullable: true, update: .push, doc: "Dauer in s."),
            S.field("elapsed", .number, nullable: true, update: .tick, doc: "vergangene Zeit in s."),
            S.field("progress", .number, nullable: true, update: .push, doc: "Fortschritt 0…1."),
            S.field("unavailable", .string, nullable: true, update: .push, doc: "Grund der Nichtverfügbarkeit."),
            S.field("app", .string, nullable: true, update: .push, doc: "Quelle."),
            S.field("app-name", .string, nullable: true, update: .push, doc: "Name der Quelle."),
            S.field("app-icon", .value, nullable: true, update: .push, doc: "Symbol der Quelle."),
            S.field("kind", .string, update: .push, doc: "music oder video."),
        ],
        actions: [
            S.action("media.play-pause", doc: "Wiedergabe umschalten."),
            S.action("media.next", doc: "nächster Titel."),
            S.action("media.previous", doc: "vorheriger Titel."),
            S.action("media.seek", [S.arg("seconds", .number, doc: "Zielzeit in s.")], doc: "an eine Stelle springen."),
            S.action("media.open-app", doc: "Quelle öffnen."),
        ],
        events: [S.event("media.track-changed", doc: "Titel geändert.")],
        doc: "was gerade läuft."
    )

    static let perf = ProviderSchema(
        id: "perf",
        fields: [
            S.field("cpu", .number, update: .poll(seconds: 2), doc: "CPU-Last 0…1."),
            S.field("memory", .number, update: .poll(seconds: 2), doc: "Speicherlast 0…1."),
            S.field("net-down", .number, update: .poll(seconds: 2), doc: "Bytes/s herunter."),
            S.field("net-up", .number, update: .poll(seconds: 2), doc: "Bytes/s hinauf."),
            S.field("live.cpu", .number, update: .tick, doc: "CPU-Last live."),
            S.field("live.gpu", .number, nullable: true, update: .tick, doc: "GPU-Last live."),
            S.field("live.cpu-history", .list, update: .tick, doc: "letzte 30 CPU-Werte."),
            S.field("live.gpu-history", .list, update: .tick, doc: "letzte 30 GPU-Werte."),
            S.field("live.memory-used", .number, update: .tick, doc: "belegter Speicher in Bytes."),
            S.field("live.memory-total", .number, update: .tick, doc: "gesamter Speicher in Bytes."),
            S.field("live.memory", .number, update: .tick, doc: "Speicherlast 0…1."),
            S.field("live.disk-used", .number, update: .tick, doc: "belegter Platz in Bytes."),
            S.field("live.disk-total", .number, update: .tick, doc: "gesamter Platz in Bytes."),
            S.field("live.disk", .number, update: .tick, doc: "Plattenauslastung 0…1."),
            S.field("live.net-down", .number, update: .tick, doc: "Bytes/s herunter."),
            S.field("live.net-up", .number, update: .tick, doc: "Bytes/s hinauf."),
            S.field("live.net-history", .list, update: .tick, doc: "letzte 30 Netzwerk-Records."),
            S.field("live.net-total-down", .number, update: .tick, doc: "Bytes seit erster Nachfrage."),
            S.field("live.net-total-up", .number, update: .tick, doc: "Bytes seit erster Nachfrage."),
            S.field("chip", .string, update: .once, doc: "Chipname."),
            S.field("cores", .number, update: .once, doc: "Kerne."),
            S.field("gpu-cores", .number, nullable: true, update: .once, doc: "GPU-Kerne."),
        ],
        doc: "CPU, GPU, Speicher, Platte, Netzwerktempo."
    )
}
