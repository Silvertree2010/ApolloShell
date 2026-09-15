import Foundation

/// Einstellungen der Shell, die Nexus (das Einstellungsfenster) aendert und
/// Leiste, Kurzmeldungen und Schreibtisch-Uhr live lesen. Liegen als
/// ~/Library/Application Support/ApolloShell/settings.json.
///
/// Die Namen folgen Caelestias Konfiguration (bar, utilities.toasts,
/// background), damit man beim Vergleich mit dem Original nicht raten muss.
///
/// Vorgaben = das Verhalten vor Nexus: alles an, Uhr mit Symbol, ohne Datum.
/// Ausnahme frische Installation (gar keine Datei): `firstLaunch` mit den
/// Kuerzeln, dem Deckel-Teil und der Einfuehrung fuer neue Nutzer.
///
/// Nachsichtig beim Lesen: fehlt ein Schluessel oder hat er den falschen Typ,
/// gilt fuer genau diesen die Vorgabe - nicht fuer die ganze Datei. So
/// bleiben die uebrigen Einstellungen erhalten, wenn eine spaetere Fassung
/// Schluessel dazu nimmt oder jemand die Datei von Hand verschreibt.
public struct ShellSettings: Codable, Equatable, Sendable {
    public var bar = Bar()
    public var toasts = Toasts()
    public var background = Background()
    public var providers = Providers()
    public var utilities = Utilities()
    /// Dashboard (Caelestia: dashboard): Reiter und Karten, siehe
    /// `DashboardLayout`. Fehlt der Abschnitt, gilt Caelestias Dashboard.
    public var dashboard = DashboardLayout()
    /// Globale Tastenkuerzel (Nexus > Tastenkürzel).
    public var hotKeys = HotKeySettings.existingInstall
    /// "Wach halten" auch zugeklappt.
    public var keepAwake = KeepAwakeSettings.existingInstall
    /// Einfuehrung beim ersten Start schon durch?
    public var onboarding = OnboardingSettings.existingInstall
    /// Apples eigenes Dock ausblenden, solange ApolloShell laeuft.
    public var appleDockHiding = AppleDockHidingSettings.existingInstall

    /// Die Vorgaben der vier Abschnitte fuer die Veroeffentlichung
    /// (hotKeys, keepAwake, onboarding, appleDockHiding) sind hier die fuer
    /// eine VORHANDENE Installation: so liest sich jede Datei ohne diese
    /// Abschnitte, und `ShellSettings()` bleibt das Verhalten von vorher.
    /// Wer noch gar keine Datei hat, bekommt `firstLaunch`.
    public init(bar: Bar = Bar(), toasts: Toasts = Toasts(), background: Background = Background(),
                providers: Providers = Providers(), utilities: Utilities = Utilities(),
                dashboard: DashboardLayout = DashboardLayout(),
                hotKeys: HotKeySettings = .existingInstall,
                keepAwake: KeepAwakeSettings = .existingInstall,
                onboarding: OnboardingSettings = .existingInstall,
                appleDockHiding: AppleDockHidingSettings = .existingInstall) {
        self.bar = bar
        self.toasts = toasts
        self.background = background
        self.providers = providers
        self.utilities = utilities
        self.dashboard = dashboard
        self.hotKeys = hotKeys
        self.keepAwake = keepAwake
        self.onboarding = onboarding
        self.appleDockHiding = appleDockHiding
    }

    /// Frische Installation (keine settings.json): neue Kuerzel, Deckel-Teil
    /// aus, Einfuehrung offen, Apple-Dock nicht ausgeblendet. Alles andere
    /// wie `ShellSettings()`. Der erste Schreibvorgang legt alle Abschnitte
    /// ausdruecklich an - danach liest sich die Datei wieder als genau
    /// dieser Stand.
    public static var firstLaunch: ShellSettings {
        ShellSettings(hotKeys: .firstLaunch, keepAwake: .firstLaunch, onboarding: .firstLaunch,
                      appleDockHiding: .firstLaunch)
    }

    /// Utilities-Panel unten rechts (Caelestia: utilities.quickToggles):
    /// Karten und Schnellschalter, siehe `UtilitiesLayout`. Fehlt der
    /// Abschnitt (Datei von vor dem Baukasten) oder ist er unlesbar: das
    /// Panel, wie es vorher fest war (Vorlage "Standard").
    public struct Utilities: Codable, Equatable, Sendable {
        public var layout: UtilitiesLayout

        public init(layout: UtilitiesLayout = UtilitiesPreset.standard.layout) {
            self.layout = layout
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            layout = c.lenient(.layout) ?? UtilitiesPreset.standard.layout
        }
    }

    /// Leiste (Caelestia: bar.entries): die Bausteine als geordnete Liste,
    /// siehe `BarLayout`.
    ///
    /// Vor dem Baukasten standen hier feste Schalter (showWorkspaces,
    /// showDock, showClock, showStatusIcons, clock). Fehlt `layout` in der
    /// Datei, wird die Leiste aus diesen gebaut - wer schon eine Datei hat,
    /// sieht also dieselbe Leiste wie vorher. Geschrieben wird nur noch
    /// `layout`.
    public struct Bar: Codable, Equatable, Sendable {
        public var layout: BarLayout

        public init(layout: BarLayout = BarPreset.caelestia.layout) {
            self.layout = layout
        }

        private enum CodingKeys: String, CodingKey {
            case layout
            // Nur noch gelesen, fuer die Migration.
            case showWorkspaces, showDock, showClock, showStatusIcons, clock
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Auch eine leere Liste ist eine Leiste (alles entfernt) - nur
            // eine fehlende oder unlesbare faellt auf die alten Schalter zurueck.
            if let layout: BarLayout = c.lenient(.layout) {
                self.layout = layout
                return
            }
            layout = .migrated(
                showWorkspaces: c.lenient(.showWorkspaces) ?? true,
                showDock: c.lenient(.showDock) ?? true,
                showClock: c.lenient(.showClock) ?? true,
                showStatusIcons: c.lenient(.showStatusIcons) ?? true,
                clock: c.lenient(.clock) ?? BarClockOptions()
            )
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(layout, forKey: .layout)
        }
    }

    /// Welche Ereignisse eine Kurzmeldung ausloesen (Caelestia:
    /// utilities.toasts). Caelestia kennt keine eigene Einstellung fuer die
    /// Akku-Warnungen (die haengen an general.battery.warnLevels); hier ein
    /// Schalter, weil unsere Stufen fest sind.
    public struct Toasts: Codable, Equatable, Sendable {
        public var chargingChanged = true
        public var batteryWarnings = true
        public var audioOutputChanged = true
        public var audioInputChanged = true

        public init(chargingChanged: Bool = true, batteryWarnings: Bool = true,
                    audioOutputChanged: Bool = true, audioInputChanged: Bool = true) {
            self.chargingChanged = chargingChanged
            self.batteryWarnings = batteryWarnings
            self.audioOutputChanged = audioOutputChanged
            self.audioInputChanged = audioInputChanged
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Toasts()
            chargingChanged = c.lenient(.chargingChanged) ?? d.chargingChanged
            batteryWarnings = c.lenient(.batteryWarnings) ?? d.batteryWarnings
            audioOutputChanged = c.lenient(.audioOutputChanged) ?? d.audioOutputChanged
            audioInputChanged = c.lenient(.audioInputChanged) ?? d.audioInputChanged
        }

        /// Ob ein Akku-Ereignis gemeldet wird.
        public func allows(_ event: BatteryToastEvent) -> Bool {
            switch event {
            case .chargerConnected, .chargerDisconnected: chargingChanged
            case .warning: batteryWarnings
            }
        }
    }

    /// Schreibtisch (Caelestia: background).
    public struct Background: Codable, Equatable, Sendable {
        public var desktopClock = true

        public init(desktopClock: Bool = true) {
            self.desktopClock = desktopClock
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            desktopClock = c.lenient(.desktopClock) ?? Background().desktopClock
        }
    }

    /// Woher Daten kommen und welche App was uebernimmt (Nexus > Anbieter).
    /// Vorgaben = das Verhalten vor dieser Einstellung: Open-Meteo, und oben
    /// im Dock ForkLift, wenn installiert, sonst Finder.
    public struct Providers: Codable, Equatable, Sendable {
        public var weather = WeatherProviderID.standard
        /// Bundle-ID des Dateimanagers oben im Dock; `nil` = automatisch
        /// (`ProviderFileManager.automatic`).
        public var fileManager: String?

        /// Von Hand: mit eigenem `encode(to:)` legt Swift keine an, und ohne
        /// sie griffe der Name auf die Schluessel von ShellSettings.
        enum CodingKeys: String, CodingKey {
            case weather, fileManager
        }

        public init(weather: WeatherProviderID = .standard, fileManager: String? = nil) {
            self.weather = weather
            self.fileManager = fileManager
        }

        /// Unbekannter Anbieter (Tippfehler, spaetere Fassung): Vorgabe.
        /// Leere Bundle-ID: automatisch.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            weather = c.lenient(.weather) ?? .standard
            let id: String? = c.lenient(.fileManager)
            let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            fileManager = trimmed.isEmpty ? nil : trimmed
        }

        /// `fileManager` auch ohne Wert als `null` schreiben: so steht der
        /// Schluessel in der Datei, und wer sie von Hand bearbeitet, findet ihn.
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(weather, forKey: .weather)
            try c.encode(fileManager, forKey: .fileManager)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bar = c.lenient(.bar) ?? Bar()
        toasts = c.lenient(.toasts) ?? Toasts()
        background = c.lenient(.background) ?? Background()
        providers = c.lenient(.providers) ?? Providers()
        utilities = c.lenient(.utilities) ?? Utilities()
        dashboard = c.lenient(.dashboard) ?? DashboardLayout()
        // Fehlt ein Abschnitt, stammt die Datei von vor der Veroeffentlichung:
        // wie bisher (alte Kuerzel, zugeklappt wach, keine Einfuehrung).
        hotKeys = c.lenient(.hotKeys) ?? .existingInstall
        keepAwake = c.lenient(.keepAwake) ?? .existingInstall
        onboarding = c.lenient(.onboarding) ?? .existingInstall
        appleDockHiding = c.lenient(.appleDockHiding) ?? .existingInstall
    }

    /// Inhalt von settings.json.
    /// - Keine Datei (`nil`): frische Installation, `firstLaunch`.
    /// - Datei da, aber gar kein JSON-Objekt: die Vorgaben einer vorhandenen
    ///   Installation - wer eine Datei hat, hat die Shell schon benutzt, auch
    ///   wenn sie inzwischen kaputt ist.
    public static func load(from data: Data?) -> ShellSettings {
        guard let data else { return .firstLaunch }
        return (try? JSONDecoder().decode(ShellSettings.self, from: data)) ?? ShellSettings()
    }

    /// Sortierte Schluessel und eingerueckt: die Datei bleibt von Hand lesbar,
    /// und gleiche Einstellungen ergeben byte-gleiche Dateien.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Nur Bool, String und endliche Zahlen (BarGapOptions begrenzt die
        // Hoehe, NaN kommt nicht hinein): kann nicht scheitern.
        return (try? encoder.encode(self)) ?? Data()
    }
}

private extension KeyedDecodingContainer {
    /// Fehlt der Schluessel oder passt der Typ nicht: `nil` statt Fehler.
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}
