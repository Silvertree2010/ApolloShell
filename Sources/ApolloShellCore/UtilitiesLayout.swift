import Foundation

// The Utilities panel as a building-kit: which cards in which order, which
// quick toggles in which order. The edit mode of the shell arranges it
// +, presets), the panel draws it and sizes its height accordingly.
//
// Unlike the bar (`BarLayout`), the cards are ALWAYS all in the list, each
// with `enabled`: there are three fixed ones, none appears twice, and
// whoever turns one off should find it in the same spot when turning it
// back on. The quick toggles, on the other hand, are an open list like the
// bar: disabled = not present (Caelestia: utilities.quickToggles).

// MARK: - Cards

/// The panel's cards. The raw value is stored in settings.json - never
/// rename, only add new ones.
public enum UtilitiesCardKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case keepAwake, audio, quickToggles

    public var id: Self { self }

    public var title: String {
        switch self {
        case .keepAwake: KeepAwakeText.title
        case .audio: UtilitiesAudioText.title
        case .quickToggles: UtilitiesToggleText.cardTitle
        }
    }

    public var summary: String {
        switch self {
        case .keepAwake: "Keep the Mac awake, even with the lid closed if you want."
        case .audio: "Volume, mute, output and input."
        case .quickToggles: "Switches and actions, five per row."
        }
    }

    public var symbol: String {
        switch self {
        case .keepAwake: "cup.and.saucer.fill"
        case .audio: "speaker.wave.2.fill"
        case .quickToggles: "square.grid.3x3.fill"
        }
    }
}

/// A card and whether it is shown. In the file:
/// `{"kind": "audio", "enabled": true}`.
public struct UtilitiesCardEntry: Codable, Equatable, Identifiable, Sendable {
    public var kind: UtilitiesCardKind
    public var enabled: Bool

    public var id: UtilitiesCardKind { kind }

    public init(_ kind: UtilitiesCardKind, enabled: Bool = true) {
        self.kind = kind
        self.enabled = enabled
    }

    /// Unknown kind: error, `UtilitiesLayout` skips the entry.
    /// Missing `enabled` or not a Bool: on.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw: String = c.lenient(.kind), let kind = UtilitiesCardKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown card")
        }
        self.kind = kind
        enabled = c.lenient(.enabled) ?? true
    }
}

// MARK: - Quick toggles: kinds

/// What the gallery groups the kinds by.
public enum UtilitiesToggleGroup: String, CaseIterable, Sendable, Identifiable {
    case switches, actions, custom

    public var id: Self { self }

    public var title: String {
        switch self {
        case .switches: "Switches"
        case .actions: "Actions"
        case .custom: "Custom Buttons"
        }
    }

    public var kinds: [UtilitiesToggleKind] {
        UtilitiesToggleKind.allCases.filter { $0.group == self }
    }
}

/// The buttons that exist. The raw value is stored in settings.json
/// ("kind") - never rename. Unknown kinds (newer version, typo) are
/// dropped on read, the rest stays.
public enum UtilitiesToggleKind: String, CaseIterable, BlockKind, Sendable, Identifiable {
    // The ten from the previous fixed grid, in its order.
    case wifi, microphone, bluetooth, darkMode, nightShift
    case screenshot, showDesktop, colorPicker, lockScreen, settings
    // Newly added.
    case displaySleep, hideApps
    case openApp, openLink, runShortcut

    public var id: Self { self }

    /// Custom buttons (app, link, shortcut) may appear more than once -
    /// each with a different target. All others at most once: two Wi-Fi
    /// switches would toggle the same thing.
    public var isUnique: Bool { group != .custom }

    public var group: UtilitiesToggleGroup {
        switch self {
        case .wifi, .microphone, .bluetooth, .darkMode, .nightShift: .switches
        case .screenshot, .showDesktop, .colorPicker, .lockScreen, .settings, .displaySleep, .hideApps: .actions
        case .openApp, .openLink, .runShortcut: .custom
        }
    }

    public var title: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .microphone: "Microphone"
        case .bluetooth: "Bluetooth"
        case .darkMode: "Dark Mode"
        case .nightShift: "Night Shift"
        case .screenshot: "Screenshot"
        case .showDesktop: "Desktop"
        case .colorPicker: "Color Picker"
        case .lockScreen: "Lock"
        case .settings: "Settings"
        case .displaySleep: "Display Off"
        case .hideApps: "Hide Apps"
        case .openApp: "Open App"
        case .openLink: "Open Link"
        case .runShortcut: "Shortcut"
        }
    }

    /// A line for the gallery behind the +.
    public var summary: String {
        switch self {
        case .wifi: "Turn Wi-Fi on and off."
        case .microphone: "Mute the default microphone."
        case .bluetooth: "Shows the state, a click opens Settings."
        case .darkMode: "Switch between light and dark."
        case .nightShift: "Warmer colors in the evening."
        case .screenshot: "Apple's bar for screenshot and recording."
        case .showDesktop: "All windows aside, the desktop clear."
        case .colorPicker: "Color from the screen, hex value to the clipboard."
        case .lockScreen: "Lock the screen."
        case .settings: "Opens Nexus."
        case .displaySleep: "Turns off the displays immediately, the Mac keeps running."
        case .hideApps: "Hides all apps; the frontmost one can stay if you want."
        case .openApp: "Launches a chosen app or brings it to the front."
        case .openLink: "Opens an address in the default browser."
        case .runShortcut: "Runs a shortcut, e.g. to toggle a Focus."
        }
    }

    /// SF Symbol for the gallery and default look. `nil` = the Bluetooth
    /// rune (no SF Symbol, see `QuickToggleLook.symbol`).
    public var symbol: String? {
        switch self {
        case .wifi: "wifi"
        case .microphone: "mic.fill"
        case .bluetooth: nil
        case .darkMode: "circle.lefthalf.filled"
        case .nightShift: "sunset.fill"
        case .screenshot: "camera.viewfinder"
        case .showDesktop: "desktopcomputer"
        case .colorPicker: "eyedropper"
        case .lockScreen: "lock.fill"
        case .settings: "gearshape.fill"
        case .displaySleep: UtilitiesToggleText.displaySleepSymbol
        case .hideApps: UtilitiesToggleText.hideAppsSymbol
        case .openApp: UtilitiesAppOptions.fallbackSymbol
        case .openLink: UtilitiesLinkOptions.fallbackSymbol
        case .runShortcut: UtilitiesShortcutOptions.fallbackSymbol
        }
    }
}

// MARK: - Quick toggles: options

// All options are read leniently: if a key is missing or has the wrong
// type, the default applies for just that one. Empty strings mean
// "automatic" (the app's name, address, default symbol).

public struct UtilitiesAppOptions: Codable, Equatable, Sendable {
    public static let fallbackSymbol = "app.fill"

    /// Empty until an app is chosen in Nexus.
    public var bundleID: String
    /// Tooltip and VoiceOver; empty = the app's name.
    public var title: String
    /// Empty = the app's own icon.
    public var symbol: String

    public init(bundleID: String = "", title: String = "", symbol: String = "") {
        self.bundleID = bundleID
        self.title = title
        self.symbol = symbol
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.bundleID, into: &bundleID)
        c.lenient(.title, into: &title)
        c.lenient(.symbol, into: &symbol)
    }

    /// Without its own SF Symbol, the button shows the app's icon.
    public var usesAppIcon: Bool { symbol.trimmed.isEmpty }
}

public struct UtilitiesLinkOptions: Codable, Equatable, Sendable {
    public static let fallbackSymbol = "link"

    /// As entered; `UtilitiesLink.url(from:)` turns it into the address.
    public var url: String
    public var title: String
    public var symbol: String

    public init(url: String = "", title: String = "", symbol: String = "") {
        self.url = url
        self.title = title
        self.symbol = symbol
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.url, into: &url)
        c.lenient(.title, into: &title)
        c.lenient(.symbol, into: &symbol)
    }
}

/// A shortcut from Apple's Shortcuts app. Both are kept: the identifier
/// survives renaming, the name is readable and the fallback if the
/// identifier (hand-edited file, different Mac) does not match.
public struct UtilitiesShortcutOptions: Codable, Equatable, Sendable {
    public static let fallbackSymbol = "square.2.layers.3d.fill"

    public var name: String
    public var identifier: String
    public var title: String
    public var symbol: String

    public init(name: String = "", identifier: String = "", title: String = "", symbol: String = "") {
        self.name = name
        self.identifier = identifier
        self.title = title
        self.symbol = symbol
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.name, into: &name)
        c.lenient(.identifier, into: &identifier)
        c.lenient(.title, into: &title)
        c.lenient(.symbol, into: &symbol)
    }
}

public struct UtilitiesHideAppsOptions: Codable, Equatable, Sendable {
    /// The frontmost app stays visible (like Option-Command-H "Hide Others").
    public var keepFrontmost: Bool

    public init(keepFrontmost: Bool = false) { self.keepFrontmost = keepFrontmost }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.keepFrontmost, into: &keepFrontmost)
    }
}

// MARK: - Quick toggles: button

/// Kind and options in one: only the kinds with options carry any.
public enum UtilitiesToggle: BlockModule, Equatable, Sendable {
    case wifi, microphone, bluetooth, darkMode, nightShift
    case screenshot, showDesktop, colorPicker, lockScreen, settings
    case displaySleep
    case hideApps(UtilitiesHideAppsOptions)
    case openApp(UtilitiesAppOptions)
    case openLink(UtilitiesLinkOptions)
    case runShortcut(UtilitiesShortcutOptions)

    /// With the kind's defaults.
    public init(_ kind: UtilitiesToggleKind) {
        self.init(kind: kind, options: nil)
    }

    /// Kind and (if present) parsed options - the one switch for both,
    /// like `BarModule.init(kind:options:)`.
    fileprivate init(kind: UtilitiesToggleKind, options c: KeyedDecodingContainer<UtilitiesToggleEntry.CodingKeys>?) {
        self = switch kind {
        case .wifi: .wifi
        case .microphone: .microphone
        case .bluetooth: .bluetooth
        case .darkMode: .darkMode
        case .nightShift: .nightShift
        case .screenshot: .screenshot
        case .showDesktop: .showDesktop
        case .colorPicker: .colorPicker
        case .lockScreen: .lockScreen
        case .settings: .settings
        case .displaySleep: .displaySleep
        case .hideApps: .hideApps(Self.decoded(c, forKey: .options, default: .init()))
        case .openApp: .openApp(Self.decoded(c, forKey: .options, default: .init()))
        case .openLink: .openLink(Self.decoded(c, forKey: .options, default: .init()))
        case .runShortcut: .runShortcut(Self.decoded(c, forKey: .options, default: .init()))
        }
    }

    public var kind: UtilitiesToggleKind {
        switch self {
        case .wifi: .wifi
        case .microphone: .microphone
        case .bluetooth: .bluetooth
        case .darkMode: .darkMode
        case .nightShift: .nightShift
        case .screenshot: .screenshot
        case .showDesktop: .showDesktop
        case .colorPicker: .colorPicker
        case .lockScreen: .lockScreen
        case .settings: .settings
        case .displaySleep: .displaySleep
        case .hideApps: .hideApps
        case .openApp: .openApp
        case .openLink: .openLink
        case .runShortcut: .runShortcut
        }
    }

    /// This button's options, `nil` for a kind without any. Backs
    /// `hasOptions` (see `BlockModule`) and writing in
    /// `UtilitiesToggleEntry`.
    public var options: (any Encodable)? {
        switch self {
        case .hideApps(let o): o
        case .openApp(let o): o
        case .openLink(let o): o
        case .runShortcut(let o): o
        default: nil
        }
    }

    public var app: UtilitiesAppOptions? { if case .openApp(let o) = self { o } else { nil } }
    public var link: UtilitiesLinkOptions? { if case .openLink(let o) = self { o } else { nil } }
    public var shortcut: UtilitiesShortcutOptions? { if case .runShortcut(let o) = self { o } else { nil } }
    public var hideApps: UtilitiesHideAppsOptions? { if case .hideApps(let o) = self { o } else { nil } }
}

/// A slot in the grid. The identifier stays the same across reordering and
/// changes - SwiftUI relies on it for animation and selection.
///
/// In the file: `{"id": "wifi", "kind": "wifi", "options": {...}}`;
/// `options` is missing for kinds without options.
public struct UtilitiesToggleEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var toggle: UtilitiesToggle

    public var kind: UtilitiesToggleKind { toggle.kind }

    public init(id: String, toggle: UtilitiesToggle) {
        self.id = id
        self.toggle = toggle
    }

    /// With defaults; identifier = the kind's name (made unique by
    /// `UtilitiesLayout`).
    public init(_ kind: UtilitiesToggleKind, id: String? = nil) {
        self.init(id: id ?? kind.rawValue, toggle: UtilitiesToggle(kind))
    }

    public init(toggle: UtilitiesToggle, id: String? = nil) {
        self.init(id: id ?? toggle.kind.rawValue, toggle: toggle)
    }

    // `fileprivate`, not `private`: `UtilitiesToggle.init(kind:options:)`
    // needs the same key type to read the options.
    fileprivate enum CodingKeys: String, CodingKey { case id, kind, options }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw: String = c.lenient(.kind), let kind = UtilitiesToggleKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown quick toggle")
        }
        id = c.lenient(.id) ?? ""
        toggle = UtilitiesToggle(kind: kind, options: c)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .kind)
        if let options = toggle.options {
            try c.encode(AnyEncodable(value: options), forKey: .options)
        }
    }
}

/// For `BlockList<UtilitiesToggleEntry>`.
extension UtilitiesToggleEntry: Block {}

// MARK: - Panel

/// Cards and quick toggles. Always valid: every card exactly once,
/// button identifiers unique and never empty, fixed buttons at most once -
/// the initializers (including on read) and the mutations below take care
/// of that, which is why both lists are read-only from outside.
///
/// In the file: `{"cards": [...], "quickToggles": [...]}`. If either list
/// is missing (or is not one), the default applies to it; unreadable
/// entries are dropped, the rest stays.
public struct UtilitiesLayout: Codable, Equatable, Sendable {
    public private(set) var cards: [UtilitiesCardEntry]
    private var toggleBlocks: BlockList<UtilitiesToggleEntry>

    public var toggles: [UtilitiesToggleEntry] { toggleBlocks.entries }

    public init(cards: [UtilitiesCardEntry] = UtilitiesLayout.standardCards,
                toggles: [UtilitiesToggleEntry] = UtilitiesLayout.standardToggles) {
        self.cards = Self.normalizedCards(cards)
        toggleBlocks = BlockList(toggles)
    }

    private enum CodingKeys: String, CodingKey { case cards, quickToggles }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cards = (try? c.decodeIfPresent(LenientList<UtilitiesCardEntry>.self, forKey: .cards)) ?? nil
        let toggles = (try? c.decodeIfPresent(BlockList<UtilitiesToggleEntry>.self, forKey: .quickToggles)) ?? nil
        self.init(cards: cards?.values ?? Self.standardCards, toggles: toggles?.entries ?? Self.standardToggles)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cards, forKey: .cards)
        try c.encode(toggleBlocks, forKey: .quickToggles)
    }

    /// The panel before the building-kit: all three cards in Caelestia's order ...
    public static let standardCards: [UtilitiesCardEntry] = UtilitiesCardKind.allCases.map { UtilitiesCardEntry($0) }
    /// ... and the ten buttons: switches on top, actions below.
    public static let standardToggles: [UtilitiesToggleEntry] = [
        .wifi, .microphone, .bluetooth, .darkMode, .nightShift,
        .screenshot, .showDesktop, .colorPicker, .lockScreen, .settings,
    ].map { UtilitiesToggleEntry($0) }

    // MARK: Reading

    public subscript(toggle id: String) -> UtilitiesToggleEntry? {
        toggleBlocks[id: id]
    }

    public func isEnabled(_ kind: UtilitiesCardKind) -> Bool {
        cards.first { $0.kind == kind }?.enabled ?? false
    }

    public func contains(_ kind: UtilitiesToggleKind) -> Bool {
        toggleBlocks.contains(kind)
    }

    /// For the gallery: not a second Wi-Fi switch.
    public func canAdd(_ kind: UtilitiesToggleKind) -> Bool {
        toggleBlocks.canAdd(kind)
    }

    /// What the panel shows, top to bottom. The quick-toggles card without
    /// a single button drops out - an empty card with a heading would look
    /// like a bug.
    public var visibleCards: [UtilitiesCardKind] {
        cards.filter { $0.enabled && ($0.kind != .quickToggles || !toggles.isEmpty) }.map(\.kind)
    }

    /// The buttons in rows of `QuickToggles.columns`; the last one may be
    /// shorter.
    public var toggleRows: [[UtilitiesToggleEntry]] {
        stride(from: 0, to: toggles.count, by: QuickToggles.columns).map {
            Array(toggles[$0..<min($0 + QuickToggles.columns, toggles.count)])
        }
    }

    /// Height of the panel in points - computed purely from the layout, not
    /// measured. That way no state (a long device name, Keep Awake on) can
    /// change it, and the panel knows its size before it has ever drawn.
    /// The view holds every card to exactly this height.
    public var panelHeight: Double {
        let heights = visibleCards.map { UtilitiesMetrics.cardHeight($0, toggleRows: toggleRows.count) }
        guard !heights.isEmpty else { return 2 * UtilitiesMetrics.padding + UtilitiesMetrics.emptyCardHeight }
        return 2 * UtilitiesMetrics.padding + heights.reduce(0, +)
            + Double(heights.count - 1) * UtilitiesMetrics.spacing
    }

    // MARK: Changing cards

    public mutating func setCard(_ kind: UtilitiesCardKind, enabled: Bool) {
        guard let index = cards.firstIndex(where: { $0.kind == kind }) else { return }
        cards[index].enabled = enabled
    }

    /// Like SwiftUI's `onMove` (destination counted before the move).
    public mutating func moveCards(fromOffsets source: IndexSet, toOffset destination: Int) {
        cards.move(fromOffsets: source, toOffset: destination)
    }

    /// One spot up (-1) or down (+1); nothing at the edge.
    public mutating func moveCard(_ kind: UtilitiesCardKind, by step: Int) {
        guard let index = cards.firstIndex(where: { $0.kind == kind }), cards.indices.contains(index + step) else { return }
        cards.swapAt(index, index + step)
    }

    // MARK: Changing buttons

    /// New button, appended at the end without `index` (as in Apple's
    /// Control Center). Returns its identifier; `nil` if it may only exist
    /// once and is already there.
    @discardableResult
    public mutating func add(_ toggle: UtilitiesToggle, at index: Int? = nil) -> String? {
        toggleBlocks.add(UtilitiesToggleEntry(toggle: toggle), at: index ?? toggles.count)
    }

    @discardableResult
    public mutating func add(_ kind: UtilitiesToggleKind, at index: Int? = nil) -> String? {
        add(UtilitiesToggle(kind), at: index)
    }

    public mutating func remove(toggle id: String) {
        toggleBlocks.remove(id: id)
    }

    /// Different options for a button; the kind stays the same.
    public mutating func update(toggle id: String, to toggle: UtilitiesToggle) {
        toggleBlocks.update(id: id, to: UtilitiesToggleEntry(id: id, toggle: toggle))
    }

    public mutating func moveToggles(fromOffsets source: IndexSet, toOffset destination: Int) {
        toggleBlocks.move(fromOffsets: source, toOffset: destination)
    }

    /// One spot forward (-1) or back (+1); nothing at the edge.
    public mutating func moveToggle(_ id: String, by step: Int) {
        toggleBlocks.move(id: id, by: step)
    }

    /// While dragging in the grid: the dragged button takes the spot of the
    /// one the pointer is currently over; everything in between shifts by
    /// one. That way it visibly moves along while dragging.
    public mutating func moveToggle(_ id: String, onto target: String) {
        toggleBlocks.move(id: id, onto: target)
    }

    // MARK: Rules

    /// Every card exactly once (the first one counts); if one is missing -
    /// a file from an older version with fewer cards -, it is appended at
    /// the end, enabled.
    static func normalizedCards(_ list: [UtilitiesCardEntry]) -> [UtilitiesCardEntry] {
        var seen = Set<UtilitiesCardKind>()
        var result = list.filter { seen.insert($0.kind).inserted }
        for kind in UtilitiesCardKind.allCases where !seen.contains(kind) {
            result.append(UtilitiesCardEntry(kind))
        }
        return result
    }
}

// MARK: - Metrics

/// The panel's dimensions, measured on the fixed panel before the
/// building-kit (visual test 14.09.: 430 x 426, every card the same height
/// in every state). The view sets every card to exactly this height;
/// `panelHeight` computes with it. If a card changes, this number has to
/// change too.
public enum UtilitiesMetrics {
    /// Caelestia: 430 wide, 16 margin, 12 between cards.
    public static let width = 430.0
    public static let padding = 16.0
    public static let spacing = 12.0
    /// Inner margin of every card.
    public static let cardPadding = 14.0

    /// 40pt symbol chip plus inner margin.
    public static let keepAwakeHeight = 68.0
    /// Heading 17, 10, slider row 32, 10, device buttons 44, plus inner margin.
    public static let audioHeight = 141.0
    /// Heading "Quick Toggles" (14 pt, one line).
    public static let toggleTitleHeight = 17.0
    public static let toggleTitleSpacing = 12.0
    public static let toggleHeight = 48.0
    public static let toggleRowSpacing = 8.0
    /// Notice when nothing is shown: one line like "Keep Awake".
    public static let emptyCardHeight = 68.0

    public static func toggleCardHeight(rows: Int) -> Double {
        let rows = max(rows, 1)
        return 2 * cardPadding + toggleTitleHeight + toggleTitleSpacing
            + Double(rows) * toggleHeight + Double(rows - 1) * toggleRowSpacing
    }

    public static func cardHeight(_ kind: UtilitiesCardKind, toggleRows: Int) -> Double {
        switch kind {
        case .keepAwake: keepAwakeHeight
        case .audio: audioHeight
        case .quickToggles: toggleCardHeight(rows: toggleRows)
        }
    }
}

// MARK: - Presets

/// Ready-made panels to load in Nexus. "Standard" is the default and
/// exactly the panel before the building-kit.
public enum UtilitiesPreset: String, CaseIterable, Identifiable, Sendable {
    case standard, minimal, audio, everything

    public var id: Self { self }

    public var title: String {
        switch self {
        case .standard: "Standard"
        case .minimal: "Minimal"
        case .audio: "Sound & Devices"
        case .everything: "Everything"
        }
    }

    public var summary: String {
        switch self {
        case .standard: "The default: Keep Awake, Sound and ten quick toggles."
        case .minimal: "Just one row of quick toggles, no cards above."
        case .audio: "Sound at the top, below that microphone, Bluetooth and what you need while listening."
        case .everything: "Every card and every fixed button once, for trying out and sorting through."
        }
    }

    public var layout: UtilitiesLayout {
        switch self {
        case .standard:
            UtilitiesLayout()
        case .minimal:
            UtilitiesLayout(
                cards: [UtilitiesCardEntry(.quickToggles), UtilitiesCardEntry(.keepAwake, enabled: false),
                        UtilitiesCardEntry(.audio, enabled: false)],
                toggles: [.wifi, .bluetooth, .darkMode, .lockScreen, .settings].map { UtilitiesToggleEntry($0) }
            )
        case .audio:
            UtilitiesLayout(
                cards: [UtilitiesCardEntry(.audio), UtilitiesCardEntry(.quickToggles), UtilitiesCardEntry(.keepAwake, enabled: false)],
                toggles: [.microphone, .bluetooth, .wifi, .displaySleep, .settings].map { UtilitiesToggleEntry($0) }
            )
        case .everything:
            UtilitiesLayout(toggles: [
                .wifi, .microphone, .bluetooth, .darkMode, .nightShift,
                .screenshot, .showDesktop, .colorPicker, .lockScreen, .displaySleep,
                .hideApps, .settings,
            ].map { UtilitiesToggleEntry($0) })
        }
    }
}

/// For `LayoutPreset`: "Standard" is the default.
extension UtilitiesPreset: LayoutPreset {
    public static var `default`: UtilitiesPreset { .standard }
}

// MARK: - Text and look of the new buttons

public enum UtilitiesToggleText {
    public static let cardTitle = String(localized: "Quick Toggles")
    public static let displaySleepSymbol = "moon.zzz.fill"
    public static let hideAppsSymbol = "eye.slash.fill"
}

extension QuickToggles {
    /// `appName`: name of the installed app; `nil` = not installed.
    /// Not clickable without a chosen or installed app.
    public static func openApp(_ options: UtilitiesAppOptions, appName: String?) -> QuickToggleLook {
        let symbol = options.symbol.trimmed.nonEmpty ?? UtilitiesAppOptions.fallbackSymbol
        guard !options.bundleID.trimmed.isEmpty else {
            return QuickToggleLook(symbol: symbol, active: false, enabled: false, help: String(localized: "No App Chosen Yet"))
        }
        guard let appName else {
            return QuickToggleLook(symbol: symbol, active: false, enabled: false, help: String(localized: "App Not Installed"))
        }
        let title = options.title.trimmed.nonEmpty ?? appName
        return QuickToggleLook(symbol: symbol, active: false, enabled: true, help: String(localized: "Open \(title)"))
    }

    public static func openLink(_ options: UtilitiesLinkOptions) -> QuickToggleLook {
        let symbol = options.symbol.trimmed.nonEmpty ?? UtilitiesLinkOptions.fallbackSymbol
        guard let url = UtilitiesLink.url(from: options.url) else {
            let help = options.url.trimmed.isEmpty ? String(localized: "No Link Yet") : String(localized: "Invalid Link")
            return QuickToggleLook(symbol: symbol, active: false, enabled: false, help: help)
        }
        let title = options.title.trimmed.nonEmpty ?? UtilitiesLink.displayText(url)
        return QuickToggleLook(symbol: symbol, active: false, enabled: true, help: String(localized: "Open \(title)"))
    }

    public static func runShortcut(_ options: UtilitiesShortcutOptions) -> QuickToggleLook {
        let symbol = options.symbol.trimmed.nonEmpty ?? UtilitiesShortcutOptions.fallbackSymbol
        guard UtilitiesShortcuts.runArguments(options) != nil else {
            return QuickToggleLook(symbol: symbol, active: false, enabled: false, help: String(localized: "No Shortcut Chosen Yet"))
        }
        let title = options.title.trimmed.nonEmpty ?? options.name.trimmed.nonEmpty ?? String(localized: "Shortcut")
        return QuickToggleLook(symbol: symbol, active: false, enabled: true, help: String(localized: "Run Shortcut \u{201c}\(title)\u{201d}"))
    }

    public static let displaySleep = QuickToggleLook(
        symbol: UtilitiesToggleText.displaySleepSymbol, active: false, enabled: true,
        help: String(localized: "Turn Off Display")
    )

    public static func hideApps(_ options: UtilitiesHideAppsOptions) -> QuickToggleLook {
        QuickToggleLook(symbol: UtilitiesToggleText.hideAppsSymbol, active: false, enabled: true,
                        help: options.keepFrontmost ? String(localized: "Hide Other Apps") : String(localized: "Hide All Apps"))
    }
}

// MARK: - Links

public enum UtilitiesLink {
    /// From the input field to an address:
    /// - with a scheme (https:, mailto:, x-apple.systempreferences: ...) as
    ///   entered; http(s) needs a host.
    /// - without a scheme, but with a dot or "localhost" ("example.com",
    ///   "localhost:8080"): https:// prepended - the way one usually types
    ///   addresses.
    /// - empty, with whitespace, or otherwise unrecognizable: `nil`.
    public static func url(from input: String) -> URL? {
        let text = input.trimmed
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        if let scheme = scheme(of: text) {
            guard let url = URL(string: text), url.scheme?.lowercased() == scheme else { return nil }
            if scheme == "http" || scheme == "https" {
                guard let host = url.host(), !host.isEmpty else { return nil }
            }
            return url
        }
        guard text.contains(".") || text.lowercased().hasPrefix("localhost"),
              let url = URL(string: "https://" + text), let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    /// Short form for tooltips: without scheme, without "www." and without
    /// a trailing slash ("example.com/docs"). Other schemes shown in full.
    public static func displayText(_ url: URL) -> String {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host()
        else { return url.absoluteString }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path()
        return path.isEmpty || path == "/" ? host : host + (path.hasSuffix("/") ? String(path.dropLast()) : path)
    }

    /// Scheme per RFC 3986 (letter, then letters, digits, + . -) before the
    /// first colon - unless what follows is digits only: that is
    /// "host:port" without a scheme.
    private static func scheme(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let head = text[..<colon]
        guard let first = head.first, first.isASCII, first.isLetter,
              head.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+.-".contains($0)) })
        else { return nil }
        let tail = text[text.index(after: colon)...].prefix { $0 != "/" }
        if !tail.isEmpty, tail.allSatisfy(\.isNumber) { return nil }
        return head.lowercased()
    }
}

// MARK: - Shortcuts

/// An entry from `shortcuts list --show-identifiers`.
public struct UtilitiesShortcut: Equatable, Sendable, Identifiable {
    public var name: String
    public var identifier: String

    public var id: String { identifier.isEmpty ? name : identifier }

    public init(name: String, identifier: String) {
        self.name = name
        self.identifier = identifier
    }
}

/// Apple's Shortcuts via the bundled tool /usr/bin/shortcuts: public, no
/// permission dialog, and the only way to e.g. toggle a Focus ("Do Not
/// Disturb") without private interfaces.
public enum UtilitiesShortcuts {
    public static let tool = "/usr/bin/shortcuts"
    public static let listArguments = ["list", "--show-identifiers"]

    /// Every line "Name (IDENTIFIER)" - the identifier is a UUID in
    /// parentheses at the end of the line (measured 14.09., macOS 26.6).
    /// Names may themselves contain parentheses, hence read from the back.
    /// Lines without an identifier: just the name. Sorted by name as in the
    /// Shortcuts app.
    public static func parse(_ output: String) -> [UtilitiesShortcut] {
        output.split(whereSeparator: \.isNewline).compactMap { raw -> UtilitiesShortcut? in
            let line = String(raw).trimmed
            guard !line.isEmpty else { return nil }
            if line.hasSuffix(")"), let open = line.lastIndex(of: "(") {
                let candidate = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
                if UUID(uuidString: candidate) != nil {
                    // Just an identifier without a name: nothing one could pick.
                    let name = String(line[..<open]).trimmed
                    return name.isEmpty ? nil : UtilitiesShortcut(name: name, identifier: candidate)
                }
            }
            return UtilitiesShortcut(name: line, identifier: "")
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Arguments for `shortcuts run`: prefer the identifier (survives
    /// renaming), otherwise the name. `nil`: nothing chosen.
    public static func runArguments(_ options: UtilitiesShortcutOptions) -> [String]? {
        if let id = options.identifier.trimmed.nonEmpty { return ["run", id] }
        if let name = options.name.trimmed.nonEmpty { return ["run", name] }
        return nil
    }
}

extension ToastText {
    /// `shortcuts run` ended with an error (shortcut deleted, cancelled).
    public static func shortcutFailed(_ name: String) -> Content {
        Content(title: String(localized: "Shortcut Failed"),
                message: name.trimmed.nonEmpty ?? String(localized: "Unknown Shortcut"),
                symbol: UtilitiesShortcutOptions.fallbackSymbol, kind: .warning)
    }
}

// MARK: - Hiding apps

public enum UtilitiesHideApps {
    /// Which app gets hidden: only regular apps (with a Dock icon), never
    /// the shell itself - otherwise the bar and panels would disappear -,
    /// and not the frontmost one when `keepFrontmost` is set.
    public static func shouldHide(pid: Int32, isRegular: Bool, ownPID: Int32, frontmostPID: Int32?,
                                  keepFrontmost: Bool) -> Bool {
        guard isRegular, pid != ownPID else { return false }
        return !(keepFrontmost && pid == frontmostPID)
    }
}

// MARK: - Symbols

/// The small selection in Nexus for custom buttons. Every one of these
/// exists on macOS 26 (the visual test checks it); a custom name also works.
public enum UtilitiesSymbols {
    public static let choices: [String] = [
        "app.fill", "link", "globe", "square.2.layers.3d.fill", "star.fill", "heart.fill", "bolt.fill",
        "moon.fill", "sun.max.fill", "bell.fill", "bell.slash.fill", "music.note", "play.fill", "headphones",
        "house.fill", "envelope.fill", "message.fill", "calendar", "note.text", "checklist", "book.fill",
        "doc.fill", "folder.fill", "terminal.fill", "hammer.fill", "paintbrush.fill", "camera.fill", "photo.fill",
        "film.fill", "gamecontroller.fill", "cup.and.saucer.fill", "lightbulb.fill", "timer", "alarm.fill",
        "flag.fill", "bookmark.fill", "cart.fill", "briefcase.fill", "chart.bar.fill", "keyboard.fill",
        "printer.fill", "network", "server.rack", "key.fill", "sparkles", "wand.and.stars", "leaf.fill", "airplane",
    ]
}

// MARK: - Helpers

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
