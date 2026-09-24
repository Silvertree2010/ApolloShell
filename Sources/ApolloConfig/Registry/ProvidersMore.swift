enum ProvidersMore {
    private typealias S = ProviderSupport

    static let spaces = ProviderSchema(
        id: "spaces",
        fields: [
            S.field("list", .list, update: .push, doc: "Schreibtische des Kontexts."),
            S.field("current", .number, update: .push, doc: "Index des aktiven Schreibtischs."),
            S.field("count", .number, update: .push, doc: "Anzahl Schreibtische."),
        ],
        actions: [
            S.action("spaces.switch", [S.arg("index", .number, doc: "Zielindex.")], doc: "auf einen Schreibtisch wechseln."),
            S.action("spaces.next", doc: "nächster Schreibtisch."),
            S.action("spaces.previous", doc: "vorheriger Schreibtisch."),
            S.action("spaces.mission-control", doc: "Mission Control öffnen."),
        ],
        events: [S.event("spaces.changed", doc: "Schreibtisch gewechselt.")],
        permissions: ["accessibility"],
        doc: "Schreibtische je Bildschirm."
    )

    static let apps = ProviderSchema(
        id: "apps",
        fields: [
            S.field("all", .list, update: .push, doc: "installierte Apps."),
            S.field("running", .list, update: .push, doc: "laufende Apps."),
            S.field("dock", .list, update: .push, doc: "Dock-Liste."),
            S.field("favorites", .list, update: .push, doc: "Launcher-Favoriten."),
            S.field("frontmost", .record, nullable: true, update: .push, doc: "vorderste App."),
            S.field("file-manager", .record, update: .push, doc: "aufgelöster Dateimanager."),
            S.field("file-managers", .list, update: .push, doc: "erkannte Dateimanager."),
        ],
        actions: [
            S.action("apps.click", [S.arg("app", .value, doc: "App-Record oder Bundle-ID.")], properties: [PropertySchema(name: "modifiers", type: .list, defaultValue: .list([]), doc: "gehaltene Modifikatoren.")], doc: "Klick wie im Dock.", startsProgramsOrControlsApps: true),
            S.action("apps.launch", [S.arg("app", .value, doc: "App.")], doc: "starten oder nach vorne holen.", startsProgramsOrControlsApps: true),
            S.action("apps.new-window", [S.arg("app", .value, doc: "App.")], doc: "neues Fenster.", startsProgramsOrControlsApps: true),
            S.action("apps.cycle-windows", [S.arg("app", .value, doc: "App."), S.arg("direction", .enumeration(["up", "down"]), doc: "Richtung.")], doc: "durch Fenster wechseln.", startsProgramsOrControlsApps: true),
            S.action("apps.open-files", [S.arg("app", .value, doc: "App."), S.arg("files", .list, doc: "Dateien.")], doc: "Dateien mit der App öffnen.", startsProgramsOrControlsApps: true),
            S.action("apps.show-all-windows", [S.arg("app", .value, doc: "App.")], doc: "App-Exposé.", startsProgramsOrControlsApps: true),
            S.action("apps.hide", [S.arg("app", .value, doc: "App.")], doc: "App ausblenden.", startsProgramsOrControlsApps: true),
            S.action("apps.unhide", [S.arg("app", .value, doc: "App.")], doc: "App einblenden.", startsProgramsOrControlsApps: true),
            S.action("apps.quit", [S.arg("app", .value, doc: "App.")], doc: "App beenden.", startsProgramsOrControlsApps: true),
            S.action("apps.force-quit", [S.arg("app", .value, doc: "App.")], doc: "App sofort beenden.", startsProgramsOrControlsApps: true),
            S.action("apps.reveal", [S.arg("app", .value, doc: "App.")], properties: [PropertySchema(name: "in", type: .enumeration(["file-manager", "finder"]), defaultValue: .string("file-manager"), doc: "Ziel.")], doc: "App im Dateimanager zeigen."),
            S.action("apps.refresh", doc: "Katalog, Nutzung und Favoriten neu lesen."),
            S.action("apps.dock-move", [S.arg("from", .string, doc: "Quellschlüssel."), S.arg("to", .string, doc: "Zielschlüssel.")], doc: "im Dock ziehen."),
            S.action("apps.dock-pin", [S.arg("app", .value, doc: "App.")], doc: "im Dock behalten."),
            S.action("apps.dock-unpin", [S.arg("app", .value, doc: "App.")], doc: "aus dem Dock lösen."),
            S.action("apps.favorite-add", [S.arg("app", .value, doc: "App.")], doc: "zu Favoriten hinzufügen."),
            S.action("apps.favorite-remove", [S.arg("app", .value, doc: "App.")], doc: "aus Favoriten entfernen."),
            S.action("apps.favorite-move", [S.arg("from", .number, doc: "Quellstelle."), S.arg("to", .number, doc: "Zielstelle.")], doc: "Favorit umsortieren."),
            S.action("apps.run-command", [S.arg("app", .value, doc: "App."), S.arg("command", .string, doc: "Menübefehl.")], doc: "Menübefehl über Accessibility ausführen.", startsProgramsOrControlsApps: true),
        ],
        events: [
            S.event("apps.launched", [S.field("app", .value, update: .once, doc: "gestartete App.")], doc: "App gestartet."),
            S.event("apps.terminated", [S.field("app", .value, update: .once, doc: "beendete App.")], doc: "App beendet."),
            S.event("apps.activated", [S.field("app", .value, update: .once, doc: "aktivierte App.")], doc: "App aktiviert."),
        ],
        settings: [
            PropertySchema(name: "file-manager", type: .string, defaultValue: .null, doc: "bevorzugter Dateimanager, #null für automatisch."),
        ],
        doc: "installierte, laufende, angeheftete Apps, Dock-Verhalten."
    )

    static let weather = ProviderSchema(
        id: "weather",
        fields: [
            S.field("status", .string, update: .push, doc: "no-place, loading, ready oder failed."),
            S.field("place", .record, nullable: true, update: .push, doc: "gewählter Ort."),
            S.field("current", .record, nullable: true, update: .push, doc: "aktuelles Wetter."),
            S.field("today", .record, nullable: true, update: .push, doc: "Tageswerte."),
            S.field("hourly-strip", .list, update: .push, doc: "12 Einträge im Abstand von 2 h."),
            S.field("days", .list, update: .push, doc: "nächste 7 Tage."),
            S.field("updated", .value, nullable: true, update: .push, doc: "letzter Abruf."),
            S.field("stale", .bool, update: .push, doc: "ob die Daten veraltet sind."),
            S.field("attribution", .record, update: .push, doc: "Quellenangabe."),
            S.field("capabilities", .record, update: .push, doc: "was der Anbieter liefert."),
            S.field("search-results", .list, update: .push, doc: "gefundene Orte."),
            S.field("search-status", .string, update: .push, doc: "idle, searching, done oder failed."),
        ],
        actions: [
            S.action("weather.refresh", doc: "neu abrufen."),
            S.action("weather.search", [S.arg("text", .string, doc: "Suchtext.")], doc: "Ort suchen."),
            S.action("weather.clear-search", doc: "Suche zurücksetzen."),
        ],
        settings: [
            PropertySchema(name: "source", type: .enumeration(["open-meteo", "met-norway", "wttr"]), defaultValue: .string("open-meteo"), doc: "Wetteranbieter."),
            PropertySchema(name: "place", type: .record, defaultValue: .null, doc: "Record name/latitude/longitude oder #null."),
        ],
        doc: "Wetter von drei Anbietern, Ortssuche."
    )

    static let keyboard = ProviderSchema(
        id: "keyboard",
        fields: [
            S.field("source", .record, update: .push, doc: "aktive Eingabequelle."),
            S.field("sources", .list, update: .push, doc: "verfügbare Eingabequellen."),
            S.field("caps-lock", .bool, update: .push, doc: "ob Feststelltaste aktiv ist."),
        ],
        actions: [
            S.action("keyboard.next-source", doc: "nächste Eingabequelle."),
            S.action("keyboard.select", [S.arg("id", .string, doc: "Kennung der Quelle.")], doc: "Eingabequelle wählen."),
        ],
        events: [S.event("keyboard.source-changed", doc: "Eingabequelle geändert.")],
        doc: "Eingabequelle."
    )

    static let window = ProviderSchema(
        id: "window",
        fields: [
            S.field("app", .record, nullable: true, update: .push, doc: "App des vordersten Fensters."),
            S.field("title", .string, nullable: true, update: .push, doc: "Fenstertitel."),
            S.field("fullscreen", .bool, update: .push, doc: "ob Vollbild aktiv ist."),
        ],
        permissions: ["accessibility"],
        doc: "vorderstes Fenster."
    )

    static let screens = ProviderSchema(
        id: "screens",
        fields: [
            S.field("list", .list, update: .push, doc: "Bildschirme."),
            S.field("main", .record, update: .push, doc: "Hauptbildschirm."),
        ],
        events: [S.event("screens.changed", [S.field("screens", .list, update: .once, doc: "neue Bildschirmliste.")], doc: "Bildschirme geändert.")],
        doc: "Bildschirme."
    )

    static let system = ProviderSchema(
        id: "system",
        fields: [
            S.field("dark-mode", .bool, update: .push, doc: "ob Dunkelmodus aktiv ist."),
            S.field("night-shift", .bool, nullable: true, update: .push, doc: "Night Shift."),
            S.field("microphone-muted", .bool, nullable: true, update: .push, doc: "ob Mikrofon stumm ist."),
            S.field("show-desktop-available", .bool, update: .push, doc: "ob der Kurzbefehl aktiv ist."),
            S.field("accent-color", .string, update: .push, doc: "Systemakzentfarbe als Hex."),
            S.field("reduce-motion", .bool, update: .push, doc: "Bewegung reduzieren."),
            S.field("reduce-transparency", .bool, update: .push, doc: "Transparenz reduzieren."),
            S.field("user-name", .string, update: .once, doc: "Kurzname."),
            S.field("full-name", .string, update: .once, doc: "voller Name."),
            S.field("user-image", .value, nullable: true, update: .once, doc: "Profilbild."),
            S.field("host-name", .string, update: .once, doc: "Rechnername."),
            S.field("model", .string, update: .once, doc: "Modell."),
            S.field("chip", .string, update: .once, doc: "Chip."),
            S.field("macos-version", .string, update: .once, doc: "macOS-Version."),
            S.field("kernel-version", .string, update: .once, doc: "Kernel-Version."),
            S.field("uptime", .number, update: .tick, doc: "Laufzeit in s."),
            S.field("apple-dock-hidden", .bool, update: .push, doc: "ob Apples Dock versteckt ist."),
        ],
        actions: [
            S.action("system.set-dark-mode", [S.arg("value", .bool, doc: "Zustand.")], doc: "Erscheinungsbild setzen."),
            S.action("system.toggle-dark-mode", doc: "Erscheinungsbild umschalten."),
            S.action("system.set-night-shift", [S.arg("value", .bool, doc: "Zustand.")], doc: "Night Shift setzen."),
            S.action("system.toggle-night-shift", doc: "Night Shift umschalten."),
            S.action("system.set-microphone-muted", [S.arg("value", .bool, doc: "Zustand.")], doc: "Mikrofon stumm schalten."),
            S.action("system.toggle-microphone", doc: "Mikrofon umschalten."),
            S.action("system.screenshot", doc: "Bildschirmfoto-Leiste öffnen."),
            S.action("system.color-picker", doc: "Farbpipette öffnen."),
            S.action("system.show-desktop", doc: "Schreibtisch zeigen."),
            S.action("system.lock", doc: "Bildschirm sperren."),
            S.action("system.display-sleep", doc: "Bildschirm ausschalten."),
            S.action("system.hide-apps", properties: [PropertySchema(name: "keep-frontmost", type: .bool, defaultValue: .bool(false), doc: "vorderste App behalten.")], doc: "andere Apps ausblenden.", startsProgramsOrControlsApps: true),
            S.action("system.open-settings", [S.arg("pane", .string, required: false, doc: "Bereich.")], doc: "Systemeinstellungen öffnen."),
            S.action("system.hide-apple-dock", [S.arg("value", .bool, doc: "Zustand.")], doc: "Apples Dock ausblenden."),
        ],
        events: [
            S.event("system.appearance-changed", doc: "Erscheinungsbild geändert."),
            S.event("system.color-copied", [S.field("hex", .string, update: .once, doc: "kopierte Farbe.")], doc: "Farbe kopiert."),
            S.event("shortcuts.failed", [S.field("name", .string, update: .once, doc: "Name des Kurzbefehls.")], doc: "run-shortcut fehlgeschlagen."),
        ],
        doc: "Erscheinungsbild, Night Shift, Mikrofon, Benutzer, Rechner, Systemaktionen."
    )

    static let session = ProviderSchema(
        id: "session",
        actions: [
            S.action("session.logout", doc: "abmelden.", startsProgramsOrControlsApps: true),
            S.action("session.restart", doc: "neu starten.", startsProgramsOrControlsApps: true),
            S.action("session.shutdown", doc: "ausschalten.", startsProgramsOrControlsApps: true),
            S.action("session.sleep", doc: "Ruhezustand."),
            S.action("session.lock", doc: "Bildschirm sperren."),
        ],
        permissions: ["automation"],
        doc: "Abmelden, Ruhezustand, Neustart, Ausschalten, Sperren."
    )

    static let power = ProviderSchema(
        id: "power",
        fields: [
            S.field("keep-awake", .bool, update: .push, doc: "ob wachgehalten wird."),
            S.field("keep-awake-since", .value, nullable: true, update: .push, doc: "seit wann."),
            S.field("lid", .string, update: .push, doc: "off, on, pending oder declined."),
            S.field("keep-awake-text", .string, update: .tick, doc: "Unterzeile wie in 0.1.4.2."),
            S.field("lid-rule-installed", .bool, update: .poll(seconds: 2), doc: "ob die sudoers-Regel installiert ist."),
        ],
        actions: [
            S.action("power.set-keep-awake", [S.arg("value", .bool, doc: "Zustand.")], doc: "Wachhalten setzen."),
            S.action("power.toggle-keep-awake", doc: "Wachhalten umschalten."),
            S.action("power.remove-lid-rule", doc: "sudoers-Regel entfernen."),
        ],
        events: [
            S.event("power.keep-awake-stopped", [S.field("reason", .string, update: .once, doc: "Grund, z. B. battery.")], doc: "Wachhalten beendet."),
            S.event("power.lid-still-awake", doc: "Deckel-Ausschalten abgelehnt."),
        ],
        settings: [
            PropertySchema(name: "lid-closed", type: .bool, defaultValue: .null, doc: "Wachhalten auch bei geschlossenem Deckel."),
        ],
        doc: "Wachhalten, auch mit geschlossenem Deckel."
    )

    static let permissions = ProviderSchema(
        id: "permissions",
        fields: [
            S.field("accessibility", .bool, update: .poll(seconds: 2), doc: "Bedienungshilfen erlaubt."),
            S.field("automation", .bool, nullable: true, update: .poll(seconds: 2), doc: "Automation erlaubt."),
            S.field("screen-recording", .bool, update: .poll(seconds: 2), doc: "Bildschirmaufnahme erlaubt."),
        ],
        actions: [
            S.action("permissions.request-accessibility", doc: "Bedienungshilfen anfragen."),
            S.action("permissions.open", [S.arg("kind", .enumeration(["accessibility", "automation", "screen-recording"]), doc: "Bereich.")], doc: "Systemeinstellungen zur Berechtigung öffnen."),
        ],
        doc: "Berechtigungen."
    )

    static let shortcuts = ProviderSchema(
        id: "shortcuts",
        fields: [S.field("list", .list, update: .poll(seconds: 5), doc: "Kurzbefehle der Kurzbefehle-App.")],
        doc: "Kurzbefehle der Kurzbefehle-App."
    )

    static let marketplace = ProviderSchema(
        id: "marketplace",
        fields: [
            S.field("status", .string, update: .push, doc: "idle, loading, loaded oder failed."),
            S.field("error", .string, nullable: true, update: .push, doc: "letzter Fehler einer Aktion, bis marketplace.dismiss."),
            S.field("load-error", .string, nullable: true, update: .push, doc: "warum die Liste nicht geladen werden konnte, nur bei status failed."),
            S.field("items", .list, update: .push, doc: "verfügbare Einträge."),
            S.field("user", .record, nullable: true, update: .push, doc: "angemeldeter Benutzer."),
            S.field("sign-in", .record, update: .push, doc: "Status der Anmeldung."),
            S.field("mine", .list, update: .push, doc: "eigene Einreichungen."),
            S.field("queue", .list, update: .push, doc: "Warteschlange für Admins."),
            S.field("message", .string, nullable: true, update: .push, doc: "letzte Meldung."),
            S.field("local", .list, update: .push, doc: "lokale Themes zum Einreichen: id, name, problem, css."),
        ],
        actions: [
            S.action("marketplace.refresh", doc: "neu laden."),
            S.action("marketplace.get", [S.arg("id", .string, doc: "Eintrag.")], doc: "installieren.", startsProgramsOrControlsApps: true),
            S.action("marketplace.update", [S.arg("id", .string, doc: "Eintrag.")], doc: "aktualisieren.", startsProgramsOrControlsApps: true),
            S.action("marketplace.use", [S.arg("id", .string, doc: "Eintrag.")], doc: "aktivieren."),
            S.action("marketplace.remove", [S.arg("id", .string, doc: "Eintrag.")], doc: "entfernen."),
            S.action("marketplace.sign-in", doc: "anmelden."),
            S.action("marketplace.cancel-sign-in", doc: "Anmeldung abbrechen."),
            S.action("marketplace.copy-code", doc: "Anmeldecode kopieren."),
            S.action("marketplace.sign-out", doc: "abmelden."),
            S.action("marketplace.delete-account", doc: "Konto löschen."),
            S.action("marketplace.submit", [S.arg("themeID", .string, doc: "Theme.")], properties: [PropertySchema(name: "accept-terms", type: .bool, defaultValue: .bool(false), doc: "Zustimmung zu CC0 und Nutzungsbedingungen.")], doc: "einreichen."),
            S.action("marketplace.new-version", [S.arg("id", .string, doc: "Eintrag."), S.arg("source", .string, doc: "Quelle.")], properties: [PropertySchema(name: "accept-terms", type: .bool, defaultValue: .bool(false), doc: "Zustimmung zu CC0 und Nutzungsbedingungen.")], doc: "neue Version einreichen."),
            S.action("marketplace.delete", [S.arg("id", .string, doc: "Eintrag.")], doc: "löschen."),
            S.action("marketplace.report", [S.arg("id", .string, doc: "Eintrag."), S.arg("reason", .string, doc: "Grund.")], doc: "melden."),
            S.action("marketplace.approve", [S.arg("id", .string, doc: "Eintrag."), S.arg("version", .string, doc: "Version.")], doc: "freigeben."),
            S.action("marketplace.reject", [S.arg("id", .string, doc: "Eintrag."), S.arg("version", .string, doc: "Version."), S.arg("reason", .string, doc: "Grund.")], doc: "ablehnen."),
            S.action("marketplace.hide", [S.arg("id", .string, doc: "Eintrag."), S.arg("reason", .string, doc: "Grund.")], doc: "verstecken."),
            S.action("marketplace.unhide", [S.arg("id", .string, doc: "Eintrag.")], doc: "sichtbar machen."),
            S.action("marketplace.ban", [S.arg("userID", .string, doc: "Benutzer."), S.arg("reason", .string, doc: "Grund.")], doc: "sperren."),
            S.action("marketplace.dismiss", doc: "Meldung und Fehler schliessen."),
            S.action("marketplace.open", doc: "Marketplace-Fenster öffnen."),
        ],
        settings: [PropertySchema(name: "enabled", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "schaltet den Marketplace ein oder aus.")],
        doc: "Themes, Configs und Pakete aus dem Marketplace."
    )

    static let wm = ProviderSchema(
        id: "wm",
        feature: "wm",
        fields: [
            S.field("enabled", .bool, update: .push, doc: "ob der Fenstermanager läuft."),
            S.field("layout", .string, update: .push, doc: "aktives Layout."),
            S.field("focused", .record, nullable: true, update: .push, doc: "fokussiertes Fenster."),
            S.field("windows", .list, update: .push, doc: "alle Fenster."),
            S.field("desktop", .number, update: .push, doc: "aktueller Desktop."),
            S.field("workspace", .number, update: .push, doc: "aktueller Arbeitsbereich."),
            S.field("workspaces", .list, update: .push, doc: "Arbeitsbereiche, nur bei apple-desktops=#false."),
            S.field("tab-bars", .list, update: .push, doc: "Tab-Leisten."),
        ],
        actions: [
            S.action("wm.focus", [S.arg("direction", .string, doc: "left, right, up, down oder next.")], doc: "Fokus bewegen."),
            S.action("wm.swap", [S.arg("direction", .string, doc: "left, right, up oder down.")], doc: "Fenster tauschen."),
            S.action("wm.split", doc: "teilen."),
            S.action("wm.equalize", doc: "Grössen ausgleichen."),
            S.action("wm.grow", [S.arg("width", .number, doc: "Breite."), S.arg("height", .number, doc: "Höhe.")], doc: "Grösse ändern."),
            S.action("wm.terminal", doc: "Terminal öffnen.", startsProgramsOrControlsApps: true),
            S.action("wm.group", doc: "gruppieren."),
            S.action("wm.tab", [S.arg("direction", .string, doc: "next oder prev.")], doc: "Tab wechseln."),
            S.action("wm.tab-move", [S.arg("direction", .string, doc: "next oder prev.")], doc: "Tab verschieben."),
            S.action("wm.group-app", doc: "App gruppieren."),
            S.action("wm.float", doc: "schwebend machen."),
            S.action("wm.fullscreen", doc: "Vollbild."),
            S.action("wm.close", doc: "Fenster schliessen."),
            S.action("wm.desktop", [S.arg("index", .number, doc: "Zieldesktop.")], doc: "Desktop wechseln."),
            S.action("wm.send", [S.arg("index", .number, doc: "Zieldesktop.")], doc: "Fenster senden."),
            S.action("wm.scratchpad", doc: "Scratchpad öffnen."),
            S.action("wm.display", [S.arg("direction", .string, doc: "next oder prev.")], doc: "Bildschirm wechseln."),
            S.action("wm.move-display", [S.arg("direction", .string, doc: "next oder prev.")], doc: "Fenster auf anderen Bildschirm."),
            S.action("wm.layout", [S.arg("kind", .enumeration(["dwindle", "canvas"]), doc: "Layout.")], doc: "Layout umschalten."),
            S.action("wm.toggle", doc: "Fenstermanager an/aus."),
            S.action("wm.focus-window", [S.arg("id", .string, doc: "Fenster-ID.")], doc: "Fenster fokussieren."),
        ],
        events: [
            S.event("wm.focus-changed", doc: "Fokus geändert."),
            S.event("wm.layout-changed", doc: "Layout geändert."),
            S.event("wm.window-opened", doc: "Fenster geöffnet."),
            S.event("wm.window-closed", doc: "Fenster geschlossen."),
            S.event("wm.workspace-changed", doc: "Arbeitsbereich geändert."),
        ],
        permissions: ["accessibility"],
        doc: "Tiling-Fenstermanager."
    )
}
