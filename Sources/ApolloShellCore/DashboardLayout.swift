import Foundation

// The dashboard as a building-block system, like the bar (BarLayout.swift):
// which tabs in which order, and which cards go where in the overview.
// Nexus > Dashboard edits it, the dashboard renders it live.
//
// The window stays the same size throughout (content 839 x 392, like
// Caelestia): a dashboard that grows wider or narrower depending on the
// cards would look unsettled at the top edge, and the fixed card sizes are
// Caelestia's face. That's why there are slots instead of free placement -
// two rows and a side column, see `DashboardZone` and `DashboardGeometry`.

// MARK: - Tabs

/// Dashboard tabs, in Caelestia's order. The raw value is stored in
/// settings.json, so never rename it.
public enum DashboardTab: String, CaseIterable, Codable, Identifiable, Sendable {
    case dashboard, media, performance, weather

    public var id: Self { self }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .media: String(localized: "Media")
        case .performance: String(localized: "Performance")
        case .weather: String(localized: "Weather")
        }
    }

    public var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .media: "music.note.list"
        case .performance: "gauge.with.dots.needle.67percent"
        case .weather: "cloud.sun"
        }
    }

    /// Identifier for symbol replacement in the theme (`icons/<id>.png`).
    public var iconID: String {
        switch self {
        case .dashboard: "bar-dashboard"
        case .media: "panel-media"
        case .performance: "panel-performance"
        case .weather: "panel-weather"
        }
    }
}

/// Order and visibility of the tabs (Caelestia: dashboard.showMedia etc.,
/// here reorderable in addition).
///
/// Unlike the bar's building blocks, a hidden tab stays in the list: there
/// are only four, Nexus shows all of them with a toggle, and when it's shown
/// again it sits wherever it was dragged to.
///
/// Always valid: every tab exactly once in `order`, at least one visible - a
/// dashboard without tabs would have nothing to show.
///
/// In the file: `[{"id": "media", "visible": true}, ...]`.
public struct DashboardTabs: Codable, Equatable, Sendable {
    public private(set) var order: [DashboardTab]
    public private(set) var hidden: Set<DashboardTab>

    public init(order: [DashboardTab] = DashboardTab.allCases, hidden: Set<DashboardTab> = []) {
        (self.order, self.hidden) = Self.normalized(order: order, hidden: hidden)
    }

    private struct Item: Codable {
        var id: DashboardTab
        var visible: Bool

        private enum CodingKeys: String, CodingKey { case id, visible }

        init(id: DashboardTab, visible: Bool) {
            self.id = id
            self.visible = visible
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let raw: String = c.lenient(.id), let tab = DashboardTab(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "unknown tab")
            }
            id = tab
            visible = c.lenient(.visible) ?? true
        }
    }

    /// Unknown, duplicate or broken entries are dropped; missing tabs (e.g.
    /// one added later) end up visible at the end.
    public init(from decoder: any Decoder) throws {
        let items = try LenientList<Item>(from: decoder).values
        var seen = Set<DashboardTab>()
        let unique = items.filter { seen.insert($0.id).inserted }
        self.init(order: unique.map(\.id), hidden: Set(unique.filter { !$0.visible }.map(\.id)))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(order.map { Item(id: $0, visible: !hidden.contains($0)) })
    }

    // MARK: Reading

    public var visible: [DashboardTab] { order.filter { !hidden.contains($0) } }

    public func isVisible(_ tab: DashboardTab) -> Bool { !hidden.contains(tab) }

    /// The tab that is actually shown: the requested one, or - if it is
    /// hidden - the first visible one. This way the bar's media building
    /// block doesn't open into nothing when its tab is hidden.
    public func resolved(_ tab: DashboardTab) -> DashboardTab {
        isVisible(tab) ? tab : (visible.first ?? tab)
    }

    /// The last visible tab cannot be hidden.
    public func canHide(_ tab: DashboardTab) -> Bool {
        isVisible(tab) && visible.count > 1
    }

    // MARK: Changing

    public mutating func setVisible(_ tab: DashboardTab, _ visible: Bool) {
        if visible {
            hidden.remove(tab)
        } else if canHide(tab) {
            hidden.insert(tab)
        }
    }

    /// Like SwiftUI's `onMove` (target counted before the move).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }

    /// One spot up (-1) or down (+1); nothing happens at the edge.
    public mutating func move(_ tab: DashboardTab, by step: Int) {
        order = Reorder.move(order, element: tab, by: step)
    }

    static func normalized(order: [DashboardTab], hidden: Set<DashboardTab>) -> ([DashboardTab], Set<DashboardTab>) {
        var seen = Set<DashboardTab>()
        var list = order.filter { seen.insert($0).inserted }
        list += DashboardTab.allCases.filter { !seen.contains($0) }
        var hidden = hidden
        if list.allSatisfy({ hidden.contains($0) }), let first = list.first { hidden.remove(first) }
        return (list, hidden)
    }
}

// MARK: - Slots

/// Where a card sits in the overview. The two rows and the column are
/// Caelestia's grid: weather and user on top (130 high), clock, calendar,
/// resources at the bottom (250 high), media on the right (200 wide).
public enum DashboardZone: String, CaseIterable, Identifiable, Sendable {
    case top, bottom, side

    public var id: Self { self }

    public var title: String {
        switch self {
        case .top: String(localized: "Top Row")
        case .bottom: String(localized: "Bottom Row")
        case .side: String(localized: "Side Column")
        }
    }

    /// Rows place cards side by side; the column has room for one.
    public var isRow: Bool { self != .side }
}

/// How wide a card is within a row. Fixed cards have their Caelestia size;
/// flexible ones share the remainder and need at least `minimum` so their
/// content isn't cut off.
public enum DashboardCardWidth: Equatable, Sendable {
    case fixed(Double)
    case flexible(minimum: Double)

    public var minimum: Double {
        switch self {
        case .fixed(let width): width
        case .flexible(let minimum): minimum
        }
    }

    public var isFlexible: Bool {
        if case .flexible = self { true } else { false }
    }
}

// MARK: - Kinds

/// Which cards exist; each at most once (there is one weather card, one
/// user card, one playback card). Raw value in settings.json ("kind").
public enum DashboardCardKind: String, CaseIterable, Identifiable, Sendable {
    case weather, user, clock, calendar, resources, media

    public var id: Self { self }

    public var title: String {
        switch self {
        case .weather: String(localized: "Weather")
        case .user: String(localized: "User")
        case .clock: String(localized: "Clock")
        case .calendar: String(localized: "Calendar")
        case .resources: String(localized: "Resources")
        case .media: String(localized: "Media")
        }
    }

    /// One line for the gallery behind the +.
    public var summary: String {
        switch self {
        case .weather: String(localized: "Temperature and condition for the chosen location.")
        case .user: String(localized: "Name, macOS version and how long the Mac has been running.")
        case .clock: String(localized: "Hour and minute, with an optional date.")
        case .calendar: String(localized: "The month with today marked, to page through.")
        case .resources: String(localized: "CPU, memory and storage as rings.")
        case .media: String(localized: "What's currently playing, with cover art and buttons.")
        }
    }

    public var symbol: String {
        switch self {
        case .weather: "cloud.sun.fill"
        case .user: "person.crop.circle.fill"
        case .clock: "clock.fill"
        case .calendar: "calendar"
        case .resources: "gauge.with.dots.needle.33percent"
        case .media: "music.note"
        }
    }

    /// Where the card sits in Caelestia - it lands there when added.
    public var home: DashboardZone {
        switch self {
        case .weather, .user: .top
        case .clock, .calendar, .resources: .bottom
        case .media: .side
        }
    }

    /// Where it is allowed to go, `home` first. The calendar needs the
    /// height of the bottom row (six weeks) and more width than the column
    /// has.
    public var zones: [DashboardZone] {
        switch self {
        case .calendar: [.bottom]
        case .weather, .user: [.top, .bottom, .side]
        case .clock, .resources: [.bottom, .top, .side]
        case .media: [.side, .top, .bottom]
        }
    }

    public func allows(_ zone: DashboardZone) -> Bool { zones.contains(zone) }

    /// Width within a row; in the column every card fills the column.
    /// Deliberately independent of the options: otherwise a toggle (three
    /// rings instead of two) could blow up a full row.
    public func width(in zone: DashboardZone) -> DashboardCardWidth {
        switch (self, zone) {
        case (_, .side): .fixed(DashboardGeometry.sideWidth)
        // Caelestia sizes from the original.
        case (.weather, .top): .fixed(275)
        case (.user, .top): .flexible(minimum: 230)
        case (.clock, _): .fixed(110)
        case (.calendar, _): .flexible(minimum: 300)
        case (.resources, .bottom): .fixed(90)
        // New slots: three rings side by side, playback as a strip,
        // weather, user and playback in portrait orientation in the bottom
        // row.
        case (.resources, _): .fixed(230)
        case (.media, .top): .flexible(minimum: 300)
        case (.weather, _), (.user, _), (.media, _): .fixed(200)
        }
    }
}

// MARK: - Options per card

// Lenient like ShellSettings: if a key is missing or has the wrong type,
// the default applies to just that one. Default = Caelestia.

public struct DashboardWeatherOptions: Codable, Equatable, Sendable {
    /// "Partly cloudy" under the temperature.
    public var showCondition: Bool
    /// Today's high and low.
    public var showRange: Bool

    public init(showCondition: Bool = true, showRange: Bool = true) {
        self.showCondition = showCondition
        self.showRange = showRange
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showCondition, into: &showCondition)
        c.lenient(.showRange, into: &showRange)
    }
}

public struct DashboardUserOptions: Codable, Equatable, Sendable {
    public var showSystem: Bool
    public var showUptime: Bool

    public init(showSystem: Bool = true, showUptime: Bool = true) {
        self.showSystem = showSystem
        self.showUptime = showUptime
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showSystem, into: &showSystem)
        c.lenient(.showUptime, into: &showUptime)
    }
}

public struct DashboardClockOptions: Codable, Equatable, Sendable {
    /// `stacked`: hour, three dots, minute stacked (Caelestia).
    /// `inline`: "14:05" on one line.
    public enum Style: String, Codable, CaseIterable, Sendable { case stacked, inline }

    public var style: Style
    /// Weekday and day under the time.
    public var showDate: Bool
    /// Time zone as an IANA identifier ("Asia/Tokyo"), `nil` = the
    /// system's. With multiple clocks (0.2), each can thus show a
    /// different city. An unknown identifier behaves like `nil`.
    public var timeZone: String?

    public init(style: Style = .stacked, showDate: Bool = false, timeZone: String? = nil) {
        self.style = style
        self.showDate = showDate
        self.timeZone = timeZone
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.style, into: &style)
        c.lenient(.showDate, into: &showDate)
        timeZone = c.lenient(.timeZone)
    }

    public var resolvedTimeZone: TimeZone {
        timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
    }
}

public struct DashboardCalendarOptions: Codable, Equatable, Sendable {
    public enum FirstWeekday: String, Codable, CaseIterable, Sendable {
        case monday, sunday

        /// Value for `Calendar.firstWeekday` (1 = Sunday).
        public var calendarValue: Int { self == .monday ? 2 : 1 }
    }

    public var firstWeekday: FirstWeekday
    /// Calendar week to the left of every row.
    public var showWeekNumbers: Bool

    public init(firstWeekday: FirstWeekday = .monday, showWeekNumbers: Bool = false) {
        self.firstWeekday = firstWeekday
        self.showWeekNumbers = showWeekNumbers
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.firstWeekday, into: &firstWeekday)
        c.lenient(.showWeekNumbers, into: &showWeekNumbers)
    }

    /// The same calendar (language, time zone), only with the chosen first
    /// weekday. The rule for the first week (in Switzerland: four days,
    /// ISO 8601) stays that of the language.
    public func applied(to calendar: Calendar) -> Calendar {
        var calendar = calendar
        calendar.firstWeekday = firstWeekday.calendarValue
        return calendar
    }
}

public struct DashboardResourcesOptions: Codable, Equatable, Sendable {
    public var showCPU: Bool
    public var showMemory: Bool
    public var showStorage: Bool

    public init(showCPU: Bool = true, showMemory: Bool = true, showStorage: Bool = true) {
        self.showCPU = showCPU
        self.showMemory = showMemory
        self.showStorage = showStorage
    }

    /// All three off (handcrafted like this): all on again - an empty card
    /// makes no sense. Nexus doesn't even let you turn off the last ring.
    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showCPU, into: &showCPU)
        c.lenient(.showMemory, into: &showMemory)
        c.lenient(.showStorage, into: &showStorage)
        if count == 0 { self = Self() }
    }

    public var count: Int { [showCPU, showMemory, showStorage].filter { $0 }.count }
}

public struct DashboardMediaOptions: Codable, Equatable, Sendable {
    public var showAlbum: Bool
    /// App that is currently playing, at the bottom of the card (only in
    /// the side column, otherwise there's no room).
    public var showSource: Bool

    public init(showAlbum: Bool = true, showSource: Bool = true) {
        self.showAlbum = showAlbum
        self.showSource = showSource
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.showAlbum, into: &showAlbum)
        c.lenient(.showSource, into: &showSource)
    }
}

// MARK: - Card

/// Kind and options combined, like `BarModule`: each kind carries exactly
/// its own option type. The identifier is the kind itself - each card
/// exists once.
///
/// In the file: `{"kind": "clock", "options": {...}}`.
public enum DashboardCard: BlockModule, Codable, Equatable, Identifiable, Sendable {
    case weather(DashboardWeatherOptions)
    case user(DashboardUserOptions)
    case clock(DashboardClockOptions)
    case calendar(DashboardCalendarOptions)
    case resources(DashboardResourcesOptions)
    case media(DashboardMediaOptions)

    public init(_ kind: DashboardCardKind) {
        self.init(kind: kind, options: nil)
    }

    /// Kind and (if present) decoded options - the single switch for both,
    /// like `BarModule.init(kind:options:)`.
    fileprivate init(kind: DashboardCardKind, options c: KeyedDecodingContainer<CodingKeys>?) {
        self = switch kind {
        case .weather: .weather(Self.decoded(c, forKey: .options, default: .init()))
        case .user: .user(Self.decoded(c, forKey: .options, default: .init()))
        case .clock: .clock(Self.decoded(c, forKey: .options, default: .init()))
        case .calendar: .calendar(Self.decoded(c, forKey: .options, default: .init()))
        case .resources: .resources(Self.decoded(c, forKey: .options, default: .init()))
        case .media: .media(Self.decoded(c, forKey: .options, default: .init()))
        }
    }

    public var kind: DashboardCardKind {
        switch self {
        case .weather: .weather
        case .user: .user
        case .clock: .clock
        case .calendar: .calendar
        case .resources: .resources
        case .media: .media
        }
    }

    public var id: DashboardCardKind { kind }

    /// This card's options - each kind has some, unlike `BarModule` or
    /// `UtilitiesToggle`.
    public var options: (any Encodable)? {
        switch self {
        case .weather(let o): o
        case .user(let o): o
        case .clock(let o): o
        case .calendar(let o): o
        case .resources(let o): o
        case .media(let o): o
        }
    }

    public var weather: DashboardWeatherOptions? { if case .weather(let o) = self { o } else { nil } }
    public var user: DashboardUserOptions? { if case .user(let o) = self { o } else { nil } }
    public var clock: DashboardClockOptions? { if case .clock(let o) = self { o } else { nil } }
    public var calendar: DashboardCalendarOptions? { if case .calendar(let o) = self { o } else { nil } }
    public var resources: DashboardResourcesOptions? { if case .resources(let o) = self { o } else { nil } }
    public var media: DashboardMediaOptions? { if case .media(let o) = self { o } else { nil } }

    public enum CodingKeys: String, CodingKey { case kind, options }

    /// Unknown kind: an error - `DashboardCards` then skips the card.
    /// Broken options, on the other hand, just fall back to defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw: String = c.lenient(.kind), let kind = DashboardCardKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown card")
        }
        self.init(kind: kind, options: c)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind.rawValue, forKey: .kind)
        if let options {
            try c.encode(AnyEncodable(value: options), forKey: .options)
        }
    }
}

// MARK: - Cards of the overview

/// Which card sits where, per slot from left to right. A card that is in
/// no slot is turned off (as with the bar).
///
/// Always valid - the initializer (also when reading) and the changes
/// below take care of that, which is why the lists are read-only from the
/// outside:
/// - each kind at most once,
/// - only in allowed slots (`DashboardCardKind.zones`),
/// - at most one card in the column,
/// - every row also fits next to the column (`DashboardGeometry.rowWidth`):
///   fixed widths plus minimum widths plus spacing. Always measured with
///   the column present, otherwise adding a column card later could blow
///   up a row that used to just fit.
///
/// In the file: `{"top": [...], "bottom": [...], "side": [...]}`. If a slot
/// is missing or isn't a list, its default applies; an empty list means an
/// empty slot.
public struct DashboardCards: Codable, Equatable, Sendable {
    public private(set) var top: [DashboardCard]
    public private(set) var bottom: [DashboardCard]
    public private(set) var side: [DashboardCard]

    public init(top: [DashboardCard] = [], bottom: [DashboardCard] = [], side: [DashboardCard] = []) {
        (self.top, self.bottom, self.side) = Self.normalized(top: top, bottom: bottom, side: side)
    }

    /// Shorthand with defaults per kind (templates, tests).
    public init(top: [DashboardCardKind], bottom: [DashboardCardKind], side: [DashboardCardKind]) {
        self.init(top: top.map(DashboardCard.init), bottom: bottom.map(DashboardCard.init),
                  side: side.map(DashboardCard.init))
    }

    /// Caelestia's grid, the default.
    public static let caelestia = DashboardCards(top: [.weather, .user], bottom: [.clock, .calendar, .resources],
                                                 side: [.media])

    private enum CodingKeys: String, CodingKey { case top, bottom, side }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func zone(_ key: CodingKeys, _ fallback: [DashboardCard]) -> [DashboardCard] {
            guard let list: LenientList<DashboardCard> = c.lenient(key) else { return fallback }
            return list.values
        }
        let d = Self.caelestia
        self.init(top: zone(.top, d.top), bottom: zone(.bottom, d.bottom), side: zone(.side, d.side))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(top, forKey: .top)
        try c.encode(bottom, forKey: .bottom)
        try c.encode(side, forKey: .side)
    }

    // MARK: Reading

    public subscript(zone: DashboardZone) -> [DashboardCard] {
        switch zone {
        case .top: top
        case .bottom: bottom
        case .side: side
        }
    }

    public var all: [DashboardCard] { top + bottom + side }
    public var isEmpty: Bool { all.isEmpty }

    public func contains(_ kind: DashboardCardKind) -> Bool { zone(of: kind) != nil }

    public func zone(of kind: DashboardCardKind) -> DashboardZone? {
        DashboardZone.allCases.first { self[$0].contains { $0.kind == kind } }
    }

    public subscript(kind kind: DashboardCardKind) -> DashboardCard? {
        all.first { $0.kind == kind }
    }

    /// Do these cards fit side by side into the slot?
    public static func fits(_ cards: [DashboardCard], in zone: DashboardZone) -> Bool {
        guard zone.isRow else { return cards.count <= 1 }
        let widths = cards.map { $0.kind.width(in: zone).minimum }
        let gaps = Double(max(cards.count - 1, 0)) * DashboardGeometry.spacing
        return widths.reduce(0, +) + gaps <= DashboardGeometry.rowWidth
    }

    /// Where a disabled card would land when added: at its Caelestia slot,
    /// otherwise at the first allowed one with enough room.
    public func placement(for kind: DashboardCardKind) -> DashboardZone? {
        guard !contains(kind) else { return nil }
        return kind.zones.first { Self.fits(self[$0] + [DashboardCard(kind)], in: $0) }
    }

    public func canAdd(_ kind: DashboardCardKind) -> Bool { placement(for: kind) != nil }

    /// Is the card allowed at this slot? If the column is occupied that
    /// means swapping - then the existing card must fit at the moved
    /// card's old slot.
    public func canMove(_ kind: DashboardCardKind, to zone: DashboardZone) -> Bool {
        var copy = self
        return copy.move(kind, to: zone)
    }

    public func canSwap(_ a: DashboardCardKind, _ b: DashboardCardKind) -> Bool {
        var copy = self
        return copy.swap(a, b)
    }

    // MARK: Changing

    /// With defaults from `placement(for:)`, at the end. Returns the slot;
    /// `nil` if the card is already there or there's no room anywhere.
    @discardableResult
    public mutating func add(_ kind: DashboardCardKind) -> DashboardZone? {
        guard let zone = placement(for: kind) else { return nil }
        set(zone, self[zone] + [DashboardCard(kind)])
        return zone
    }

    public mutating func remove(_ kind: DashboardCardKind) {
        for zone in DashboardZone.allCases { set(zone, self[zone].filter { $0.kind != kind }) }
    }

    /// Different options for a card that's already there. Slot and order
    /// stay the same (the width never depends on the options).
    public mutating func update(_ card: DashboardCard) {
        guard let zone = zone(of: card.kind) else { return }
        set(zone, self[zone].map { $0.kind == card.kind ? card : $0 })
    }

    /// Like SwiftUI's `onMove`, within one slot.
    public mutating func move(in zone: DashboardZone, fromOffsets source: IndexSet, toOffset destination: Int) {
        var cards = self[zone]
        cards.move(fromOffsets: source, toOffset: destination)
        set(zone, cards)
    }

    /// One spot left (-1) or right (+1) within its own slot.
    public mutating func move(_ kind: DashboardCardKind, by step: Int) {
        guard let zone = zone(of: kind), let card = self[kind: kind] else { return }
        set(zone, Reorder.move(self[zone], element: card, by: step))
    }

    /// To another slot, to the end there. The column only has room for one
    /// card: if it's occupied, the two swap places. `false` (and nothing
    /// changed) if it can't be done.
    @discardableResult
    public mutating func move(_ kind: DashboardCardKind, to target: DashboardZone) -> Bool {
        guard let source = zone(of: kind), source != target, kind.allows(target),
              let card = self[kind: kind] else { return false }
        if !target.isRow, let occupant = side.first {
            return swap(kind, occupant.kind)
        }
        var next = self
        next.set(source, self[source].filter { $0.kind != kind })
        next.set(target, self[target] + [card])
        guard Self.fits(next[target], in: target) else { return false }
        self = next
        return true
    }

    /// Two cards swap slot and position. `false` (and nothing changed) if
    /// one isn't allowed at the other's slot or a row would end up too
    /// wide.
    @discardableResult
    public mutating func swap(_ a: DashboardCardKind, _ b: DashboardCardKind) -> Bool {
        guard a != b, let za = zone(of: a), let zb = zone(of: b), a.allows(zb), b.allows(za),
              let ca = self[kind: a], let cb = self[kind: b] else { return false }
        var next = self
        for zone in Set([za, zb]) {
            next.set(zone, self[zone].map { $0.kind == a ? cb : $0.kind == b ? ca : $0 })
        }
        guard Self.fits(next[za], in: za), Self.fits(next[zb], in: zb) else { return false }
        self = next
        return true
    }

    private mutating func set(_ zone: DashboardZone, _ cards: [DashboardCard]) {
        switch zone {
        case .top: top = cards
        case .bottom: bottom = cards
        case .side: side = cards
        }
    }

    // MARK: Rules

    /// In order (top, bottom, column, each left to right): whatever
    /// violates a rule is dropped, the rest stays. Duplicate card: the
    /// first one wins.
    static func normalized(top: [DashboardCard], bottom: [DashboardCard], side: [DashboardCard])
        -> ([DashboardCard], [DashboardCard], [DashboardCard]) {
        var seen = Set<DashboardCardKind>()
        func keep(_ cards: [DashboardCard], in zone: DashboardZone) -> [DashboardCard] {
            var result: [DashboardCard] = []
            for card in cards where !seen.contains(card.kind) && card.kind.allows(zone) {
                guard fits(result + [card], in: zone) else { continue }
                seen.insert(card.kind)
                result.append(card)
            }
            return result
        }
        let t = keep(top, in: .top)
        let b = keep(bottom, in: .bottom)
        let s = keep(side, in: .side)
        return (t, b, s)
    }
}

// MARK: - Dashboard

/// Everything Nexus > Dashboard changes about the layout (settings.json:
/// dashboard). Default = Caelestia = the dashboard before the building-
/// block system; anyone without a file or without a `dashboard` section
/// therefore sees the same as before.
public struct DashboardLayout: Codable, Equatable, Sendable {
    public var tabs: DashboardTabs
    public var cards: DashboardCards

    public init(tabs: DashboardTabs = DashboardTabs(), cards: DashboardCards = .caelestia) {
        self.tabs = tabs
        self.cards = cards
    }

    private enum CodingKeys: String, CodingKey { case tabs, cards }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tabs = c.lenient(.tabs) ?? DashboardTabs()
        cards = c.lenient(.cards) ?? .caelestia
    }

    /// Whether the open dashboard needs weather. Fetching it costs a
    /// network request, playback costs a perl process - without a visible
    /// card and without a tab the dashboard doesn't even start these in
    /// the first place. Cards only count if the Dashboard tab (the
    /// overview) is visible.
    public var usesWeather: Bool { uses(.weather, tab: .weather) }
    public var usesMedia: Bool { uses(.media, tab: .media) }

    private func uses(_ card: DashboardCardKind, tab: DashboardTab) -> Bool {
        tabs.isVisible(tab) || (tabs.isVisible(.dashboard) && cards.contains(card))
    }
}

// MARK: - Presets

/// Ready-made dashboards to load in Nexus. Pure data; "Caelestia" is the
/// default and exactly the previous dashboard.
public enum DashboardPreset: String, CaseIterable, Identifiable, Sendable {
    case caelestia, compact, calendarWeather

    public var id: Self { self }

    public var title: String {
        switch self {
        case .caelestia: "Caelestia"
        case .compact: String(localized: "Compact")
        case .calendarWeather: String(localized: "Calendar & Weather")
        }
    }

    public var summary: String {
        switch self {
        case .caelestia: String(localized: "The default: weather and user on top, clock, calendar and resources below, media on the right.")
        case .compact: String(localized: "Without a side column: playback as a strip next to the weather, with clock, calendar and resources below.")
        case .calendarWeather: String(localized: "Only calendar, clock and weather, plus the Dashboard and Weather tabs. Calm, without readouts.")
        }
    }

    public var layout: DashboardLayout {
        switch self {
        case .caelestia:
            DashboardLayout()
        case .compact:
            DashboardLayout(cards: DashboardCards(top: [.weather, .media], bottom: [.clock, .calendar, .resources],
                                                  side: []))
        case .calendarWeather:
            DashboardLayout(
                tabs: DashboardTabs(order: [.dashboard, .weather, .media, .performance], hidden: [.media, .performance]),
                cards: DashboardCards(top: [], bottom: [.clock, .calendar], side: [.weather])
            )
        }
    }
}

/// For `LayoutPreset`: "Caelestia" is the default.
extension DashboardPreset: LayoutPreset {
    public static var `default`: DashboardPreset { .caelestia }
}

// MARK: - Measurements

/// Placement of a card in the overview, measured from the top-left corner
/// of the grid.
public struct DashboardRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct DashboardPlacement: Equatable, Sendable {
    public var card: DashboardCard
    public var zone: DashboardZone
    public var frame: DashboardRect
}

/// How the grid distributes its fixed area:
///
/// - Both rows occupied: top 130, bottom 250 high (Caelestia). If a row is
///   empty, the other one gets the full height.
/// - Column occupied: 200 wide on the right, the rows to its left. If
///   everything to the left is empty, the column card gets the full width.
/// - Within a row, fixed cards get their width, flexible ones share the
///   rest. Without any flexible ones, all are stretched in proportion to
///   their width - empty slots let their neighbors fill in instead of
///   leaving gaps.
/// - Only whole points; whatever remains from dividing goes to the last
///   card. That way edges land sharply on the grid.
public enum DashboardGeometry {
    public static let width: Double = 839
    public static let height: Double = 392
    public static let spacing: Double = 12
    public static let topHeight: Double = 130
    public static let sideWidth: Double = 200
    /// Width of the rows next to the column (627) - what `DashboardCards.fits` measures against.
    public static var rowWidth: Double { width - spacing - sideWidth }

    public static func placements(for cards: DashboardCards) -> [DashboardPlacement] {
        let hasSide = !cards.side.isEmpty
        let hasLeft = !cards.top.isEmpty || !cards.bottom.isEmpty
        var result: [DashboardPlacement] = []
        let leftWidth = hasSide ? rowWidth : width

        var rows: [(DashboardZone, y: Double, height: Double)] = []
        switch (cards.top.isEmpty, cards.bottom.isEmpty) {
        case (false, false):
            rows = [(.top, 0, topHeight), (.bottom, topHeight + spacing, height - topHeight - spacing)]
        case (false, true): rows = [(.top, 0, height)]
        case (true, false): rows = [(.bottom, 0, height)]
        case (true, true): rows = []
        }
        for (zone, y, rowHeight) in rows {
            let list = cards[zone]
            let widths = self.widths(available: leftWidth, widths: list.map { $0.kind.width(in: zone) }, spacing: spacing)
            var x = 0.0
            for (card, w) in zip(list, widths) {
                result.append(DashboardPlacement(card: card, zone: zone, frame: DashboardRect(x: x, y: y, width: w, height: rowHeight)))
                x += w + spacing
            }
        }
        if let card = cards.side.first {
            let frame = hasLeft
                ? DashboardRect(x: width - sideWidth, y: 0, width: sideWidth, height: height)
                : DashboardRect(x: 0, y: 0, width: width, height: height)
            result.append(DashboardPlacement(card: card, zone: .side, frame: frame))
        }
        return result
    }

    /// Widths of a row, see above. If it doesn't fit even with the minimum
    /// widths (doesn't happen after `DashboardCards.fits`), everything is
    /// compressed proportionally instead of running over the edge.
    public static func widths(available: Double, widths: [DashboardCardWidth], spacing: Double) -> [Double] {
        guard !widths.isEmpty else { return [] }
        let room = max(available - Double(widths.count - 1) * spacing, 0)
        let minimums = widths.map(\.minimum)
        let flexible = widths.indices.filter { widths[$0].isFlexible }
        let fixedSum = widths.filter { !$0.isFlexible }.map(\.minimum).reduce(0, +)
        let minimumSum = minimums.reduce(0, +)

        if !flexible.isEmpty && minimumSum <= room {
            var result = widths.map { $0.isFlexible ? 0 : $0.minimum }
            let free = room - fixedSum
            let share = (free / Double(flexible.count)).rounded(.down)
            for index in flexible { result[index] = share }
            result[flexible[flexible.count - 1]] += free - share * Double(flexible.count)
            return result
        }
        // No flexible ones, or too tight: proportional to the (minimum) widths.
        guard minimumSum > 0 else { return widths.map { _ in 0 } }
        var result = minimums.map { ($0 * room / minimumSum).rounded(.down) }
        result[result.count - 1] += room - result.reduce(0, +)
        return result
    }
}

// MARK: - Helpers

/// One spot forward or back, the same rule as `PinnedList.move(_:by:)` -
/// unlike `move(fromOffsets:toOffset:)` (see `Array.move` in
/// Reorder.swift) only used in two places (tab, dashboard card), so no own
/// file for it.
enum Reorder {
    static func move<T: Equatable>(_ list: [T], element: T, by step: Int) -> [T] {
        guard let index = list.firstIndex(of: element) else { return list }
        let target = index + step
        guard list.indices.contains(target) else { return list }
        var list = list
        list.swapAt(index, target)
        return list
    }
}
