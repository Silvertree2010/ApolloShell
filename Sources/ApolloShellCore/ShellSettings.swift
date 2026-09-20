import Foundation

/// Shell settings that Nexus (the settings window) changes, and that the
/// bar, toasts and desktop clock read live. Stored as
/// ~/Library/Application Support/ApolloShell/settings.json.
///
/// The names follow Caelestia's configuration (bar, utilities.toasts,
/// background), so comparing with the original doesn't require guessing.
///
/// Defaults = the behavior before Nexus: everything on, clock with icon,
/// no date. Exception for a fresh install (no file at all): `firstLaunch`
/// with the new shortcuts, the lid part, and the introduction for new users.
///
/// Lenient when reading: if a key is missing or has the wrong type, the
/// default applies to just that one - not to the whole file. This way the
/// remaining settings survive when a later version adds keys or someone
/// hand-edits the file incorrectly.
public struct ShellSettings: Codable, Equatable, Sendable {
    public var bar = Bar()
    public var toasts = Toasts()
    public var background = Background()
    public var providers = Providers()
    public var utilities = Utilities()
    /// Dashboard (Caelestia: dashboard): tabs and cards, see
    /// `DashboardLayout`. Without the section, Caelestia's dashboard applies.
    public var dashboard = DashboardLayout()
    /// Pages of the bento dashboard (0.2). `nil`: never saved yet or not
    /// readable - the app then builds them once out of `dashboard`
    /// (`DashboardPages.migrated`). `dashboard` itself stays untouched, so a
    /// step back to 0.1.x loses nothing.
    public var dashboardPages: DashboardPages?
    /// Size of the dashboard on top of the automatic one per screen (the
    /// Nexus slider), `BentoGeometry.userScaleRange`.
    public var dashboardScale: Double = 1
    /// Global keyboard shortcuts (Nexus > Shortcuts).
    public var hotKeys = HotKeySettings.existingInstall
    /// "Keep Awake" with the lid closed as well.
    public var keepAwake = KeepAwakeSettings.existingInstall
    /// Has the introduction on the first start been through already?
    public var onboarding = OnboardingSettings.existingInstall
    /// Hide Apple's own Dock while ApolloShell runs.
    public var appleDockHiding = AppleDockHidingSettings.existingInstall
    /// Self-updating (Nexus > Updates).
    public var updates = UpdateSettings()
    /// The chosen theme (Nexus > Themes).
    public var theme = ThemeSettings()

    /// The defaults of the four sections for the release (hotKeys, keepAwake,
    /// onboarding, appleDockHiding) are the ones for an EXISTING installation
    /// here: that way every file without these sections reads the same, and
    /// `ShellSettings()` stays the behavior from before.
    /// Whoever has no file at all gets `firstLaunch`.
    public init(bar: Bar = Bar(), toasts: Toasts = Toasts(), background: Background = Background(),
                providers: Providers = Providers(), utilities: Utilities = Utilities(),
                dashboard: DashboardLayout = DashboardLayout(),
                dashboardPages: DashboardPages? = nil,
                dashboardScale: Double = 1,
                hotKeys: HotKeySettings = .existingInstall,
                keepAwake: KeepAwakeSettings = .existingInstall,
                onboarding: OnboardingSettings = .existingInstall,
                appleDockHiding: AppleDockHidingSettings = .existingInstall,
                updates: UpdateSettings = UpdateSettings(),
                theme: ThemeSettings = ThemeSettings()) {
        self.bar = bar
        self.toasts = toasts
        self.background = background
        self.providers = providers
        self.utilities = utilities
        self.dashboard = dashboard
        self.dashboardPages = dashboardPages
        self.dashboardScale = BentoGeometry.clampedUserScale(dashboardScale)
        self.hotKeys = hotKeys
        self.keepAwake = keepAwake
        self.onboarding = onboarding
        self.appleDockHiding = appleDockHiding
        self.updates = updates
        self.theme = theme
    }

    /// A fresh installation (no settings.json): new shortcuts, the lid part
    /// off, the introduction open, Apple's Dock not hidden. Everything else
    /// like `ShellSettings()`. The first write puts down all sections
    /// explicitly - after that the file reads as exactly this state
    /// again.
    public static var firstLaunch: ShellSettings {
        ShellSettings(hotKeys: .firstLaunch, keepAwake: .firstLaunch, onboarding: .firstLaunch,
                      appleDockHiding: .firstLaunch)
    }

    /// Utilities panel at the bottom right (Caelestia: utilities.quickToggles):
    /// cards and quick toggles, see `UtilitiesLayout`. Without the section (a
    /// file from before the kit) or when it is unreadable: the panel the way
    /// it was fixed before (the "Standard" template).
    public struct Utilities: Codable, Equatable, Sendable {
        public var layout: UtilitiesLayout

        public init(layout: UtilitiesLayout = UtilitiesPreset.standard.layout) {
            self.layout = layout
        }

        public init(from decoder: any Decoder) throws {
            self.init()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            c.lenient(.layout, into: &layout)
        }
    }

    /// Bar (Caelestia: bar.entries): the building blocks as an ordered list,
    /// see `BarLayout`.
    ///
    /// Before the kit there were fixed switches here (showWorkspaces,
    /// showDock, showClock, showStatusIcons, clock). Without `layout` in the
    /// file, the bar is built out of those - so whoever has a file already
    /// sees the same bar as before. From now on only `layout` is
    /// written.
    public struct Bar: Codable, Equatable, Sendable {
        public var layout: BarLayout
        /// Which screens the bar stands on (Nexus > Bar).
        /// The default for all of them - existing installations included: all.
        public var screens: ScreenChoice
        /// What the bar is backed with (Nexus > Bar), see `BarBackground`.
        /// Default: material, the state before this choice existed.
        public var background: BarBackground

        public init(layout: BarLayout = BarPreset.caelestia.layout, screens: ScreenChoice = .all,
                    background: BarBackground = .standard) {
            self.layout = layout
            self.screens = screens
            self.background = background
        }

        private enum CodingKeys: String, CodingKey {
            case layout, screens, background
            // Only read from now on, for the migration.
            case showWorkspaces, showDock, showClock, showStatusIcons, clock
        }

        public init(from decoder: any Decoder) throws {
            self.init()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Before these settings the keys did not exist; then the defaults
            // apply (all screens, the background of back then: material).
            c.lenient(.screens, into: &screens)
            c.lenient(.background, into: &background)
            // An empty list is a bar too (everything removed) - only a missing
            // or unreadable one falls back to the old switches.
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
            try c.encode(screens, forKey: .screens)
            try c.encode(background, forKey: .background)
        }
    }

    /// Which events set off a toast (Caelestia: utilities.toasts). Caelestia
    /// knows no setting of its own for the battery warnings (those hang on
    /// general.battery.warnLevels); here a switch, because our levels are
    /// fixed.
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
            self.init()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            c.lenient(.chargingChanged, into: &chargingChanged)
            c.lenient(.batteryWarnings, into: &batteryWarnings)
            c.lenient(.audioOutputChanged, into: &audioOutputChanged)
            c.lenient(.audioInputChanged, into: &audioInputChanged)
        }

        /// Whether a battery event is reported.
        public func allows(_ event: BatteryToastEvent) -> Bool {
            switch event {
            case .chargerConnected, .chargerDisconnected: chargingChanged
            case .warning: batteryWarnings
            }
        }
    }

    /// Desktop (Caelestia: background).
    public struct Background: Codable, Equatable, Sendable {
        public var desktopClock = true

        public init(desktopClock: Bool = true) {
            self.desktopClock = desktopClock
        }

        public init(from decoder: any Decoder) throws {
            self.init()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            c.lenient(.desktopClock, into: &desktopClock)
        }
    }

    /// Where data comes from and which app takes over what (Nexus > Providers).
    /// Defaults = the behavior before this setting: Open-Meteo, and at the top
    /// of the Dock ForkLift when installed, otherwise Finder.
    public struct Providers: Codable, Equatable, Sendable {
        public var weather = WeatherProviderID.standard
        /// Bundle ID of the file manager at the top of the Dock; `nil` = automatic
        /// (`ProviderFileManager.automatic`).
        public var fileManager: String?

        /// By hand: with an `encode(to:)` of its own Swift puts down none, and
        /// without them the name would reach for the keys of ShellSettings.
        enum CodingKeys: String, CodingKey {
            case weather, fileManager
        }

        public init(weather: WeatherProviderID = .standard, fileManager: String? = nil) {
            self.weather = weather
            self.fileManager = fileManager
        }

        /// An unknown provider (a typo, a later version): the default.
        /// An empty bundle ID: automatic.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            weather = c.lenient(.weather) ?? .standard
            let id: String? = c.lenient(.fileManager)
            let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            fileManager = trimmed.isEmpty ? nil : trimmed
        }

        /// Write `fileManager` as `null` even without a value: that way the key
        /// stands in the file, and whoever edits it by hand finds it.
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
        dashboardPages = c.lenient(.dashboardPages)
        dashboardScale = BentoGeometry.clampedUserScale(c.lenient(.dashboardScale) ?? 1)
        // Without a section the file comes from before the release: as before
        // (old shortcuts, awake with the lid closed, no introduction).
        hotKeys = c.lenient(.hotKeys) ?? .existingInstall
        keepAwake = c.lenient(.keepAwake) ?? .existingInstall
        onboarding = c.lenient(.onboarding) ?? .existingInstall
        appleDockHiding = c.lenient(.appleDockHiding) ?? .existingInstall
        // Both sections only exist from 0.1.2 on. Without them the defaults
        // apply: checking and installing on, no theme of its own.
        updates = c.lenient(.updates) ?? UpdateSettings()
        theme = c.lenient(.theme) ?? ThemeSettings()
    }

    /// The content of settings.json.
    /// - No file (`nil`): a fresh installation, `firstLaunch`.
    /// - A file, but no JSON object at all: the defaults of an existing
    ///   installation - whoever has a file has used the shell already, even
    ///   when it is broken by now.
    public static func load(from data: Data?) -> ShellSettings {
        guard let data else { return .firstLaunch }
        return (try? JSONDecoder().decode(ShellSettings.self, from: data)) ?? ShellSettings()
    }

    /// Sorted keys and indented: the file stays readable by hand, and the same
    /// settings give byte-identical files.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Only Bool, String and finite numbers (BarGapOptions limits the
        // height, NaN never gets in): cannot fail.
        return (try? encoder.encode(self)) ?? Data()
    }
}
