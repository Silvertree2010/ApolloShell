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
    public enum Style: String, Codable, CaseIterable, Sendable { case dots, numbers }
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
    public var showIcon: Bool
    public var showDate: Bool

    public init(showIcon: Bool = true, showDate: Bool = false) {
        self.showIcon = showIcon
        self.showDate = showDate
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showIcon, into: &showIcon)
        c.lenient(.showDate, into: &showDate)
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
        case .dashboardButton, .utilitiesButton, .power, .spacer, .divider, .mediaButton: nil
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
    fileprivate enum CodingKeys: String, CodingKey { case id, kind, options }

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
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .kind)
        if let options = module.options {
            try c.encode(AnyEncodable(value: options), forKey: .options)
        }
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
    public mutating func update(id: String, to module: BarModule) {
        blocks.update(id: id, to: BarEntry(id: id, module: module))
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
