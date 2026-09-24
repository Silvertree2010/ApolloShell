import Foundation

// The bar as a construction kit: an ordered list of modules, each with its
// own identifier and its own options. Nexus > Bar edits it (drag, +,
// presets), the bar draws them in order.
//
// Caelestia also runs the bar as a list (bar.entries with id and enabled).
// Here without `enabled`: a disabled module is one that is not in the
// list - one less state to understand.
//
// The actual list work (assigning identifiers, cleaning up, moving,
// lenient reading) is carried by `BlockList` (BlockList.swift); only the
// rules specific to the bar remain here.

// MARK: - Kinds

/// Which modules exist. The raw value is stored in settings.json ("kind"),
/// so never rename it, only add new ones. An unknown kind (file from a
/// newer version, hand-edited) is skipped when reading instead of
/// discarding the whole bar.
public enum BarModuleKind: String, CaseIterable, Sendable, Identifiable {
    // The seven from the previous fixed bar.
    case dashboardButton, workspaces, dock, clock, utilitiesButton, statusIcons, power
    // Added new, for different tastes.
    case spacer, gap, divider, appButton, battery, cpu, weather, mediaButton
    // Stage 3 of the edge bars (spec 23.09.): the modules a top bar lives on.
    case nowPlaying, windowTitle, keyboardLayout, volume, wifi, bluetooth, systemStats
    // 09/23, with the new dashboard widgets.
    case timer, networkSpeed

    public var id: Self { self }

    /// Shares the free height with the other flexible ones (`BarFlex`).
    public var isFlexible: Bool { self == .dock || self == .spacer }

    /// At most once: the Dock (dragging and dropping writes Apple's Dock
    /// list - two columns with the same content would make no sense)
    /// and the status icons (the popout depends on the position of its
    /// icons; with two capsules it would not know which one).
    public var isUnique: Bool { self == .dock || self == .statusIcons }

    public var title: String {
        switch self {
        case .dashboardButton: String(localized: "Dashboard")
        case .workspaces: String(localized: "Spaces")
        case .dock: String(localized: "Dock")
        case .clock: String(localized: "Clock")
        case .utilitiesButton: String(localized: "Control Centre")
        case .statusIcons: String(localized: "Status Icons")
        case .power: String(localized: "Power")
        case .spacer: String(localized: "Flexible Spacer")
        case .gap: String(localized: "Fixed Spacer")
        case .divider: String(localized: "Divider")
        case .appButton: String(localized: "App")
        case .battery: String(localized: "Battery")
        case .cpu: String(localized: "CPU")
        case .weather: String(localized: "Weather")
        case .mediaButton: String(localized: "Media")
        case .nowPlaying: String(localized: "Now Playing")
        case .windowTitle: String(localized: "Window Title")
        case .keyboardLayout: String(localized: "Input Source")
        case .volume: String(localized: "Volume")
        case .wifi: String(localized: "Wi-Fi")
        case .bluetooth: String(localized: "Bluetooth")
        case .systemStats: String(localized: "System Stats")
        case .timer: String(localized: "Timer")
        case .networkSpeed: String(localized: "Network Speed")
        }
    }

    /// A line for the gallery behind the +.
    public var summary: String {
        switch self {
        case .dashboardButton: String(localized: "Opens the Dashboard with calendar, media and weather.")
        case .workspaces: String(localized: "A dot or a number per desktop.")
        case .dock: String(localized: "Pinned and running apps, like Apple's Dock.")
        case .clock: String(localized: "Hour and minute stacked, with an optional date.")
        case .utilitiesButton: String(localized: "Opens the Control Centre.")
        case .statusIcons: String(localized: "Wi-Fi, Bluetooth and battery; a click shows details.")
        case .power: String(localized: "Opens the session menu.")
        case .spacer: String(localized: "Fills free space; shares it with the Dock and other spacers.")
        case .gap: String(localized: "Empty space with a fixed size.")
        case .divider: String(localized: "A short line between two groups.")
        case .appButton: String(localized: "Launches a chosen app with a click.")
        case .battery: String(localized: "Charge level in percent.")
        case .cpu: String(localized: "Load as a ring or number, every 2 seconds.")
        case .weather: String(localized: "Icon and temperature for the Dashboard's location.")
        case .mediaButton: String(localized: "Opens the Dashboard at the Media tab.")
        case .nowPlaying: String(localized: "Title and artist of what is playing, with previous, play and next.")
        case .windowTitle: String(localized: "The frontmost app and the title of its window.")
        case .keyboardLayout: String(localized: "The current keyboard layout; a click switches to the next one.")
        case .volume: String(localized: "Output volume; scroll to change it, click to mute.")
        case .wifi: String(localized: "Wi-Fi on its own; a click shows details.")
        case .bluetooth: String(localized: "Bluetooth on its own; a click shows details.")
        case .systemStats: String(localized: "CPU and memory use in percent, every 2 seconds.")
        case .timer: String(localized: "The time left on the timer; a click starts or pauses it.")
        case .networkSpeed: String(localized: "Download and upload per second, every 2 seconds.")
        }
    }

    /// SF Symbol for list and gallery.
    public var symbol: String {
        switch self {
        case .dashboardButton: "square.grid.2x2.fill"
        case .workspaces: "square.stack.fill"
        case .dock: "dock.rectangle"
        case .clock: "clock.fill"
        case .utilitiesButton: "slider.horizontal.3"
        case .statusIcons: "wifi"
        case .power: "power"
        case .spacer: "arrow.up.and.down"
        case .gap: "arrow.up.and.line.horizontal.and.arrow.down"
        case .divider: "minus"
        case .appButton: "app.fill"
        case .battery: "battery.75percent"
        case .cpu: "cpu.fill"
        case .weather: "cloud.sun.fill"
        case .mediaButton: "music.note"
        case .nowPlaying: "play.circle.fill"
        case .windowTitle: "macwindow"
        case .keyboardLayout: "keyboard"
        case .volume: "speaker.wave.2.fill"
        case .wifi: "wifi"
        // SF Symbols has no Bluetooth rune (a trademark); the bar draws its own.
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .systemStats: "memorychip"
        case .timer: "timer"
        case .networkSpeed: "arrow.up.arrow.down"
        }
    }
}

/// For `BlockList`: the raw value is already `rawValue`, `isUnique` already
/// exists above.
extension BarModuleKind: BlockKind {}

// MARK: - Options per kind

// All options are read leniently like ShellSettings: if a key is missing
// or has the wrong type, the default applies to just that one.

public struct BarWorkspacesOptions: Codable, Equatable, Sendable {
    /// Stored as the raw value in settings.json: never rename a case. An
    /// unknown value (a newer version's face) reads as the default.
    public enum Style: String, Codable, CaseIterable, Sendable {
        case dots, numbers
        /// The active desktop an elongated capsule, the others small dots.
        case pills
        /// A thin bar per desktop, the active one taller.
        case bars
    }
    public var style: Style

    public init(style: Style = .dots) { self.style = style }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.style, into: &style)
    }
}

public struct BarDockOptions: Codable, Equatable, Sendable {
    public enum IconSize: String, Codable, CaseIterable, Sendable {
        case small, medium, large

        /// Edge length of the symbol. The frame stays 32 like all buttons
        /// in the bar; "large" nearly fills it.
        public var points: Double {
            switch self {
            case .small: 22
            case .medium: 26
            case .large: 30
            }
        }
    }

    /// Also apps that are running but not pinned (below the line).
    public var showRunning: Bool
    public var iconSize: IconSize

    public init(showRunning: Bool = true, iconSize: IconSize = .medium) {
        self.showRunning = showRunning
        self.iconSize = iconSize
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showRunning, into: &showRunning)
        c.lenient(.iconSize, into: &iconSize)
    }
}

/// Caelestia: bar.clock. Without `showSeconds`: that would require the bar
/// to redraw every second instead of every minute. Same keys as the old
/// `bar.clock`, so migration can read it unchanged.
public struct BarClockOptions: Codable, Equatable, Sendable {
    /// How the time is laid out. Raw values are stored: never rename one.
    public enum Style: String, Codable, CaseIterable, Sendable {
        /// "14:05" in one line.
        case line
        /// Hour above minute, as in the sidebar.
        case stacked
        /// The time on a filled capsule in the clock colour.
        case badge
    }

    public var showIcon: Bool
    public var showDate: Bool
    /// `nil` is "automatic" and is what every clock saved before faces
    /// existed reads as - so it keeps looking the way it did: stacked
    /// across the narrow sidebar and the right bar, one line along the top
    /// and the bottom bar. See `resolvedStyle(horizontal:)`.
    public var style: Style?

    public init(showIcon: Bool = true, showDate: Bool = false, style: Style? = nil) {
        self.showIcon = showIcon
        self.showDate = showDate
        self.style = style
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showIcon, into: &showIcon)
        c.lenient(.showDate, into: &showDate)
        // Unknown or broken: automatic, like a clock that never chose.
        style = c.lenient(.style)
    }

    /// The face actually drawn along a bar of this axis. A line does not
    /// fit across a vertical bar (32 points hold "14" but not "14:05"), so
    /// there it falls back to stacked; everything else is taken as chosen.
    public func resolvedStyle(horizontal: Bool) -> Style {
        switch style {
        case nil, .line?: horizontal ? .line : .stacked
        case let chosen?: chosen
        }
    }
}

public struct BarStatusIconsOptions: Codable, Equatable, Sendable {
    public var showWifi: Bool
    public var showBluetooth: Bool
    public var showBattery: Bool

    public init(showWifi: Bool = true, showBluetooth: Bool = true, showBattery: Bool = true) {
        self.showWifi = showWifi
        self.showBluetooth = showBluetooth
        self.showBattery = showBattery
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showWifi, into: &showWifi)
        c.lenient(.showBluetooth, into: &showBluetooth)
        c.lenient(.showBattery, into: &showBattery)
    }
}

public struct BarGapOptions: Codable, Equatable, Sendable {
    public static let range: ClosedRange<Double> = 4...96
    public static let standard: Double = 16

    /// In addition to the usual gap between two modules. Always within
    /// range: a hand-edited 10000 would otherwise blow up the whole bar,
    /// and NaN could not even be saved.
    public var height: Double {
        didSet {
            let clamped = Self.clamped(height)
            if clamped != height { height = clamped }
        }
    }

    public init(height: Double = BarGapOptions.standard) {
        self.height = Self.clamped(height)
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Not `into:`: that writes directly to the field's storage and
        // skips `didSet` in the process, so the clamping must be done by hand.
        if let raw: Double = c.lenient(.height) { height = Self.clamped(raw) }
    }

    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return standard }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

public struct BarAppButtonOptions: Codable, Equatable, Sendable {
    /// Empty until an app is chosen in Nexus; the bar then shows a
    /// dashed placeholder.
    public var bundleID: String

    public init(bundleID: String = "") { self.bundleID = bundleID }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.bundleID, into: &bundleID)
    }
}

public struct BarBatteryOptions: Codable, Equatable, Sendable {
    /// Battery icon above the number.
    public var showIcon: Bool

    public init(showIcon: Bool = true) { self.showIcon = showIcon }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showIcon, into: &showIcon)
    }
}

public struct BarCPUOptions: Codable, Equatable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable { case ring, percent }
    public var style: Style

    public init(style: Style = .ring) { self.style = style }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.style, into: &style)
    }
}

public struct BarWeatherOptions: Codable, Equatable, Sendable {
    public var showTemperature: Bool

    public init(showTemperature: Bool = true) { self.showTemperature = showTemperature }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showTemperature, into: &showTemperature)
    }
}

public struct BarNowPlayingOptions: Codable, Equatable, Sendable {
    /// Characters of "title · artist" before it is cut with an ellipsis.
    /// Clamped like the gap's height: a hand-edited 0 or 10000 would leave
    /// nothing or push every other block out of a top bar.
    public var maxLength: Int {
        didSet {
            let clamped = BarText.clampedLength(maxLength)
            if clamped != maxLength { maxLength = clamped }
        }
    }
    /// Previous, play/pause and next beside the text.
    public var showControls: Bool

    public init(maxLength: Int = 28, showControls: Bool = true) {
        self.maxLength = BarText.clampedLength(maxLength)
        self.showControls = showControls
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // By hand for the same reason as the gap: `into:` would skip `didSet`.
        if let raw: Int = c.lenient(.maxLength) { maxLength = BarText.clampedLength(raw) }
        c.lenient(.showControls, into: &showControls)
    }
}

public struct BarWindowTitleOptions: Codable, Equatable, Sendable {
    /// The app's icon before the text.
    public var showIcon: Bool
    /// The focused window's title besides the app's name. Reading it needs
    /// the accessibility permission (the window guard asks for it anyway);
    /// off, nothing is asked of other apps at all.
    public var showTitle: Bool
    public var maxLength: Int {
        didSet {
            let clamped = BarText.clampedLength(maxLength)
            if clamped != maxLength { maxLength = clamped }
        }
    }

    public init(showIcon: Bool = true, showTitle: Bool = true, maxLength: Int = 40) {
        self.showIcon = showIcon
        self.showTitle = showTitle
        self.maxLength = BarText.clampedLength(maxLength)
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showIcon, into: &showIcon)
        c.lenient(.showTitle, into: &showTitle)
        if let raw: Int = c.lenient(.maxLength) { maxLength = BarText.clampedLength(raw) }
    }
}

public struct BarKeyboardLayoutOptions: Codable, Equatable, Sendable {
    /// A keyboard symbol before the short name.
    public var showIcon: Bool

    public init(showIcon: Bool = false) { self.showIcon = showIcon }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showIcon, into: &showIcon)
    }
}

public struct BarVolumeOptions: Codable, Equatable, Sendable {
    public var showPercent: Bool
    /// The output device's name ("MacBook Pro Speakers", "AirPods") beside
    /// the number - only along a horizontal bar, it does not fit across one.
    public var showDevice: Bool

    public init(showPercent: Bool = true, showDevice: Bool = false) {
        self.showPercent = showPercent
        self.showDevice = showDevice
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showPercent, into: &showPercent)
        c.lenient(.showDevice, into: &showDevice)
    }
}

public struct BarSystemStatsOptions: Codable, Equatable, Sendable {
    public var showCPU: Bool
    public var showMemory: Bool

    public init(showCPU: Bool = true, showMemory: Bool = true) {
        self.showCPU = showCPU
        self.showMemory = showMemory
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showCPU, into: &showCPU)
        c.lenient(.showMemory, into: &showMemory)
    }

    /// Both switched off would leave an empty button; the CPU stays then,
    /// the way a module that is in the bar should always show something.
    public var shownCPU: Bool { showCPU || !showMemory }
}

// MARK: - Module

/// Kind and options in one: each kind carries exactly its own option
/// type, so a clock cannot have Dock options.
public enum BarModule: BlockModule, Equatable, Sendable {
    case dashboardButton
    case workspaces(BarWorkspacesOptions)
    case dock(BarDockOptions)
    case clock(BarClockOptions)
    case utilitiesButton
    case statusIcons(BarStatusIconsOptions)
    case power
    case spacer
    case gap(BarGapOptions)
    case divider
    case appButton(BarAppButtonOptions)
    case battery(BarBatteryOptions)
    case cpu(BarCPUOptions)
    case weather(BarWeatherOptions)
    case mediaButton
    case nowPlaying(BarNowPlayingOptions)
    case windowTitle(BarWindowTitleOptions)
    case keyboardLayout(BarKeyboardLayoutOptions)
    case volume(BarVolumeOptions)
    case wifi
    case bluetooth
    case systemStats(BarSystemStatsOptions)
    case timer
    case networkSpeed

    /// With the kind's defaults.
    public init(_ kind: BarModuleKind) {
        self.init(kind: kind, options: nil)
    }

    /// Kind and (if present) the options read - a single switch for both:
    /// without a container the defaults apply to every kind, with a
    /// container the options that were read, broken ones fall back to
    /// the defaults again.
    fileprivate init(kind: BarModuleKind, options c: KeyedDecodingContainer<BarEntry.CodingKeys>?) {
        self = switch kind {
        case .dashboardButton: .dashboardButton
        case .workspaces: .workspaces(Self.decoded(c, forKey: .options, default: .init()))
        case .dock: .dock(Self.decoded(c, forKey: .options, default: .init()))
        case .clock: .clock(Self.decoded(c, forKey: .options, default: .init()))
        case .utilitiesButton: .utilitiesButton
        case .statusIcons: .statusIcons(Self.decoded(c, forKey: .options, default: .init()))
        case .power: .power
        case .spacer: .spacer
        case .gap: .gap(Self.decoded(c, forKey: .options, default: .init()))
        case .divider: .divider
        case .appButton: .appButton(Self.decoded(c, forKey: .options, default: .init()))
        case .battery: .battery(Self.decoded(c, forKey: .options, default: .init()))
        case .cpu: .cpu(Self.decoded(c, forKey: .options, default: .init()))
        case .weather: .weather(Self.decoded(c, forKey: .options, default: .init()))
        case .mediaButton: .mediaButton
        case .nowPlaying: .nowPlaying(Self.decoded(c, forKey: .options, default: .init()))
        case .windowTitle: .windowTitle(Self.decoded(c, forKey: .options, default: .init()))
        case .keyboardLayout: .keyboardLayout(Self.decoded(c, forKey: .options, default: .init()))
        case .volume: .volume(Self.decoded(c, forKey: .options, default: .init()))
        case .wifi: .wifi
        case .bluetooth: .bluetooth
        case .systemStats: .systemStats(Self.decoded(c, forKey: .options, default: .init()))
        case .timer: .timer
        case .networkSpeed: .networkSpeed
        }
    }

    public var kind: BarModuleKind {
        switch self {
        case .dashboardButton: .dashboardButton
        case .workspaces: .workspaces
        case .dock: .dock
        case .clock: .clock
        case .utilitiesButton: .utilitiesButton
        case .statusIcons: .statusIcons
        case .power: .power
        case .spacer: .spacer
        case .gap: .gap
        case .divider: .divider
        case .appButton: .appButton
        case .battery: .battery
        case .cpu: .cpu
        case .weather: .weather
        case .mediaButton: .mediaButton
        case .nowPlaying: .nowPlaying
        case .windowTitle: .windowTitle
        case .keyboardLayout: .keyboardLayout
        case .volume: .volume
        case .wifi: .wifi
        case .bluetooth: .bluetooth
        case .systemStats: .systemStats
        case .timer: .timer
        case .networkSpeed: .networkSpeed
        }
    }

    /// Options of this module, `nil` for a kind that has none. Backs
    /// `hasOptions` (see `BlockModule`) and writing in `BarEntry`.
    public var options: (any Encodable)? {
        switch self {
        case .workspaces(let o): o
        case .dock(let o): o
        case .clock(let o): o
        case .statusIcons(let o): o
        case .gap(let o): o
        case .appButton(let o): o
        case .battery(let o): o
        case .cpu(let o): o
        case .weather(let o): o
        case .nowPlaying(let o): o
        case .windowTitle(let o): o
        case .keyboardLayout(let o): o
        case .volume(let o): o
        case .systemStats(let o): o
        case .dashboardButton, .utilitiesButton, .power, .spacer, .divider, .mediaButton, .wifi, .bluetooth, .timer, .networkSpeed: nil
        }
    }

    // Read access to the options of a kind; `nil` for every other one.
    public var workspaces: BarWorkspacesOptions? { if case .workspaces(let o) = self { o } else { nil } }
    public var dock: BarDockOptions? { if case .dock(let o) = self { o } else { nil } }
    public var clock: BarClockOptions? { if case .clock(let o) = self { o } else { nil } }
    public var statusIcons: BarStatusIconsOptions? { if case .statusIcons(let o) = self { o } else { nil } }
    public var gap: BarGapOptions? { if case .gap(let o) = self { o } else { nil } }
    public var appButton: BarAppButtonOptions? { if case .appButton(let o) = self { o } else { nil } }
    public var battery: BarBatteryOptions? { if case .battery(let o) = self { o } else { nil } }
    public var cpu: BarCPUOptions? { if case .cpu(let o) = self { o } else { nil } }
    public var weather: BarWeatherOptions? { if case .weather(let o) = self { o } else { nil } }
    public var nowPlaying: BarNowPlayingOptions? { if case .nowPlaying(let o) = self { o } else { nil } }
    public var windowTitle: BarWindowTitleOptions? { if case .windowTitle(let o) = self { o } else { nil } }
    public var keyboardLayout: BarKeyboardLayoutOptions? { if case .keyboardLayout(let o) = self { o } else { nil } }
    public var volume: BarVolumeOptions? { if case .volume(let o) = self { o } else { nil } }
    public var systemStats: BarSystemStatsOptions? { if case .systemStats(let o) = self { o } else { nil } }
}

/// A slot in the bar. The identifier stays the same when reordering and
/// when changing options - SwiftUI keeps state and animation tied to it,
/// and Nexus knows which row is expanded.
///
/// In the file: `{"id": "clock", "kind": "clock", "options": {...}}`;
/// `options` is missing for kinds without options.
public struct BarEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var module: BarModule
    /// Shares one capsule with the entry before it (the bars along the other
    /// edges draw groups this way, see `EdgeBar.groups`). The sidebar
    /// ignores it. Only written when set, so the sidebar's section reads the
    /// same as before.
    public var joinsPrevious = false

    public var kind: BarModuleKind { module.kind }

    public init(id: String, module: BarModule) {
        self.id = id
        self.module = module
    }

    /// With the defaults; identifier = name of the kind (made unique
    /// within a bar by `BarLayout`).
    public init(_ kind: BarModuleKind, id: String? = nil) {
        self.init(id: id ?? kind.rawValue, module: BarModule(kind))
    }

    /// With options. Separate label: `.power` exists both as a kind and
    /// as a module, without it `BarEntry(.power)` would be ambiguous.
    public init(module: BarModule, id: String? = nil) {
        self.init(id: id ?? module.kind.rawValue, module: module)
    }

    // `fileprivate`, not `private`: `BarModule.init(kind:options:)` needs
    // the same key type to read the options.
    /// The same entry, joined to the one before it.
    public func joined(_ joins: Bool = true) -> BarEntry {
        var copy = self
        copy.joinsPrevious = joins
        return copy
    }

    fileprivate enum CodingKeys: String, CodingKey { case id, kind, options, joinsPrevious }

    /// Unknown or missing kind: an error - `BarLayout` then skips the
    /// entry. Broken options, on the other hand, just fall back to defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw: String = c.lenient(.kind), let kind = BarModuleKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown module")
        }
        // If the identifier is missing, `BarLayout` assigns one.
        id = c.lenient(.id) ?? ""
        module = BarModule(kind: kind, options: c)
        joinsPrevious = c.lenient(.joinsPrevious) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .kind)
        if let options = module.options {
            try c.encode(AnyEncodable(value: options), forKey: .options)
        }
        if joinsPrevious { try c.encode(true, forKey: .joinsPrevious) }
    }
}

/// For `BlockList<BarEntry>`.
extension BarEntry: Block {}

// MARK: - Bar

/// The modules from top to bottom. Always valid: identifiers unique and
/// never empty, Dock and status icons at most once - `BlockList` takes
/// care of that, which is why `entries` is read-only from the outside.
///
/// A plain list in the file. Unreadable entries (unknown kind, not an
/// object) are dropped, the rest remains.
public struct BarLayout: Codable, Equatable, Sendable {
    private var blocks: BlockList<BarEntry>

    public var entries: [BarEntry] { blocks.entries }

    public init(_ entries: [BarEntry] = []) {
        blocks = BlockList(entries)
    }

    public init(from decoder: any Decoder) throws {
        blocks = try BlockList<BarEntry>(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        try blocks.encode(to: encoder)
    }

    // MARK: Reading

    public subscript(id id: String) -> BarEntry? {
        blocks[id: id]
    }

    public func contains(_ kind: BarModuleKind) -> Bool {
        blocks.contains(kind)
    }

    /// For the gallery: there is no second Dock.
    public func canAdd(_ kind: BarModuleKind) -> Bool {
        blocks.canAdd(kind)
    }

    public var flexibleCount: Int {
        entries.filter { $0.kind.isFlexible }.count
    }

    /// Where a new module goes: right below the last flexible one (Dock,
    /// spacer) - i.e. at the top of the lower group, in the Caelestia bar
    /// between Dock and clock. Without a flexible one, before a trailing
    /// Power off, otherwise at the end.
    public var insertionIndex: Int {
        if let last = entries.lastIndex(where: { $0.kind.isFlexible }) { return last + 1 }
        if entries.last?.kind == .power { return entries.count - 1 }
        return entries.count
    }

    // MARK: Changing

    /// New module with defaults, without `index` at the usual spot.
    /// Returns its identifier; `nil` if the kind is already present and
    /// may only occur once.
    @discardableResult
    public mutating func add(_ kind: BarModuleKind, at index: Int? = nil) -> String? {
        blocks.add(BarEntry(kind), at: index ?? insertionIndex)
    }

    public mutating func remove(id: String) {
        blocks.remove(id: id)
    }

    /// Different options for a module. The kind stays the same: a clock
    /// cannot turn into a second Dock this way.
    /// Keeps `joinsPrevious`: new options must not tear a block out of its
    /// group in an edge bar.
    public mutating func update(id: String, to module: BarModule) {
        let joins = blocks[id: id]?.joinsPrevious ?? false
        blocks.update(id: id, to: BarEntry(id: id, module: module).joined(joins))
    }

    /// Joins a block to the one before it, or splits it off (edge bars draw
    /// a run of joined blocks as one capsule).
    public mutating func setJoinsPrevious(id: String, _ joins: Bool) {
        guard let entry = blocks[id: id], entry.joinsPrevious != joins else { return }
        blocks.update(id: id, to: entry.joined(joins))
    }

    /// An existing block from another zone or bar, options and all. Keeps
    /// its id unless it collides (see `BlockList.insert`); `nil` when the
    /// kind may exist only once and is here already.
    @discardableResult
    public mutating func insert(_ entry: BarEntry, at index: Int) -> String? {
        blocks.insert(entry, at: index)
    }

    /// Like SwiftUI's `onMove`: `destination` counts in the list BEFORE
    /// the move ("insert before row n") - like `PinnedList.move`.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        blocks.move(fromOffsets: source, toOffset: destination)
    }

    /// One spot up (-1) or down (+1); nothing at the edge. For the
    /// context menu, so it also works without dragging.
    public mutating func move(id: String, by step: Int) {
        blocks.move(id: id, by: step)
    }

    /// To the place of another block - everything in between moves along a
    /// step. For dragging in the bar, where the dragged block travels along
    /// visibly.
    public mutating func move(id: String, onto target: String) {
        blocks.move(id: id, onto: target)
    }

    // MARK: Migration

    /// From the switches before the construction kit (bar.showWorkspaces
    /// etc.): exactly the bar they showed. Without a Dock there was a
    /// spacer there that kept the lower group at the bottom - hence
    /// `spacer` in its place.
    public static func migrated(showWorkspaces: Bool = true, showDock: Bool = true, showClock: Bool = true,
                                showStatusIcons: Bool = true, clock: BarClockOptions = .init()) -> BarLayout {
        var list: [BarEntry] = [BarEntry(.dashboardButton)]
        if showWorkspaces { list.append(BarEntry(.workspaces)) }
        list.append(BarEntry(showDock ? .dock : .spacer))
        if showClock { list.append(BarEntry(module: .clock(clock))) }
        list.append(BarEntry(.utilitiesButton))
        if showStatusIcons { list.append(BarEntry(.statusIcons)) }
        list.append(BarEntry(.power))
        return BarLayout(list)
    }
}

// MARK: - Presets

/// Ready-made bars to load in Nexus. Pure data; "Caelestia" is the
/// default and exactly the previous bar.
public enum BarPreset: String, CaseIterable, Identifiable, Sendable {
    case caelestia, minimal, dockOnly, everything

    public var id: Self { self }

    public var title: String {
        switch self {
        case .caelestia: "Caelestia"
        case .minimal: "Minimal"
        case .dockOnly: "Dock Only"
        case .everything: "Everything"
        }
    }

    public var summary: String {
        switch self {
        case .caelestia: "The default: Dashboard, Spaces, Dock, Clock, Control Centre, Status, Power off."
        case .minimal: "Spaces at the top, Clock and Power off at the bottom, nothing else."
        case .dockOnly: "Just the apps, spanning the full height."
        case .everything: "Every module once, to try out and sort through."
        }
    }

    public var layout: BarLayout {
        switch self {
        case .caelestia:
            BarLayout.migrated()
        case .minimal:
            BarLayout([
                BarEntry(.workspaces), BarEntry(.spacer),
                BarEntry(module: .clock(.init(showIcon: false))), BarEntry(.power),
            ])
        case .dockOnly:
            BarLayout([BarEntry(.dock)])
        case .everything:
            // Without a flexible spacer and a fixed spacer: those would
            // only share the space with the Dock. The battery stands as
            // its own module here, so it is not shown again in the capsule.
            BarLayout([
                BarEntry(.dashboardButton), BarEntry(.mediaButton), BarEntry(.workspaces), BarEntry(.divider),
                BarEntry(.dock), BarEntry(.divider),
                BarEntry(module: .appButton(.init(bundleID: "com.apple.systempreferences"))),
                BarEntry(.weather), BarEntry(.cpu), BarEntry(.battery), BarEntry(.clock),
                BarEntry(.utilitiesButton), BarEntry(module: .statusIcons(.init(showBattery: false))), BarEntry(.power),
            ])
        }
    }
}

/// For `LayoutPreset`: "Caelestia" is the default.
extension BarPreset: LayoutPreset {
    public static var `default`: BarPreset { .caelestia }
}

// MARK: - Distributing height

/// Position of a module in the bar: top edge and height, from the top
/// edge of the content.
public struct BarSlot: Equatable, Sendable {
    public var y: Double
    public var height: Double

    public init(y: Double, height: Double) {
        self.y = y
        self.height = height
    }
}

/// How the bar distributes its height:
///
/// - Fixed modules get their own height, `spacing` between them.
/// - What remains is shared equally among the flexible ones (`nil` in
///   `heights`: Dock, spacer). So the Dock alone fills exactly the space
///   between the upper and lower group - as before the construction kit.
/// - Without a flexible one, all stand at the top, the rest stays free
///   at the bottom.
/// - If there is not enough space, the flexible ones get 0 (the Dock
///   scrolls), never a negative height.
public enum BarFlex {
    public static func slots(available: Double, heights: [Double?], spacing: Double) -> [BarSlot] {
        let fixed = heights.compactMap { $0 }
        let flexible = heights.count - fixed.count
        let gaps = Double(max(heights.count - 1, 0)) * spacing
        let free = available - fixed.reduce(0, +) - gaps
        let share = flexible > 0 ? max(free, 0) / Double(flexible) : 0
        var y = 0.0
        return heights.map { height in
            let slot = BarSlot(y: y, height: height ?? share)
            y += slot.height + spacing
            return slot
        }
    }
}
