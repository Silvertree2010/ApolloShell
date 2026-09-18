import Foundation

// Das Dashboard als Baukasten, wie die Leiste (BarLayout.swift): welche
// Reiter in welcher Reihenfolge, und welche Karten wo in der Uebersicht.
// Nexus > Dashboard bearbeitet es, das Dashboard zeichnet es live.
//
// Das Fenster bleibt dabei gleich gross (Inhalt 839 x 392 wie Caelestia):
// ein Dashboard, das je nach Karten mal breiter, mal schmaler aufgeht, waere
// oben am Rand unruhig, und die festen Kartenmasse sind Caelestias Gesicht.
// Deshalb Plaetze statt freier Anordnung - zwei Reihen und eine Seitenspalte,
// siehe `DashboardZone` und `DashboardGeometry`.

// MARK: - Reiter

/// Reiter des Dashboards, Reihenfolge wie Caelestia. Der Rohwert steht in
/// settings.json, deshalb nie umbenennen.
public enum DashboardTab: String, CaseIterable, Codable, Identifiable, Sendable {
    case dashboard, media, performance, weather

    public var id: Self { self }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .media: String(localized: "Medien")
        case .performance: String(localized: "Leistung")
        case .weather: String(localized: "Wetter")
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

    /// Kennung fuer den Symbol-Austausch im Theme (`icons/<kennung>.png`).
    public var iconID: String {
        switch self {
        case .dashboard: "bar-dashboard"
        case .media: "panel-media"
        case .performance: "panel-performance"
        case .weather: "panel-weather"
        }
    }
}

/// Reihenfolge und Sichtbarkeit der Reiter (Caelestia: dashboard.showMedia
/// usw., hier dazu umsortierbar).
///
/// Anders als bei den Bausteinen der Leiste bleibt ein ausgeblendeter Reiter
/// in der Liste: es gibt nur vier, Nexus zeigt alle mit Schalter, und beim
/// Wiedereinblenden steht er dort, wo man ihn hingezogen hat.
///
/// Immer gueltig: jeder Reiter genau einmal in `order`, mindestens einer
/// sichtbar - ein Dashboard ohne Reiter haette nichts zu zeigen.
///
/// In der Datei: `[{"id": "media", "visible": true}, ...]`.
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
                throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "unbekannter Reiter")
            }
            id = tab
            visible = c.lenient(.visible) ?? true
        }
    }

    /// Unbekannte, doppelte oder kaputte Eintraege fallen weg; fehlende
    /// Reiter (etwa ein spaeter dazugekommener) kommen sichtbar ans Ende.
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

    // MARK: Lesen

    public var visible: [DashboardTab] { order.filter { !hidden.contains($0) } }

    public func isVisible(_ tab: DashboardTab) -> Bool { !hidden.contains(tab) }

    /// Der Reiter, der wirklich gezeigt wird: der gewuenschte, oder - wenn
    /// er ausgeblendet ist - der erste sichtbare. So oeffnet der
    /// Medien-Baustein der Leiste bei ausgeblendetem Reiter Medien nicht ins
    /// Leere.
    public func resolved(_ tab: DashboardTab) -> DashboardTab {
        isVisible(tab) ? tab : (visible.first ?? tab)
    }

    /// Der letzte sichtbare laesst sich nicht ausblenden.
    public func canHide(_ tab: DashboardTab) -> Bool {
        isVisible(tab) && visible.count > 1
    }

    // MARK: Aendern

    public mutating func setVisible(_ tab: DashboardTab, _ visible: Bool) {
        if visible {
            hidden.remove(tab)
        } else if canHide(tab) {
            hidden.insert(tab)
        }
    }

    /// Wie SwiftUIs `onMove` (Ziel vor dem Verschieben gezaehlt).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }

    /// Eine Stelle nach oben (-1) oder unten (+1); am Rand nichts.
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

// MARK: - Plaetze

/// Wo eine Karte in der Uebersicht steht. Die beiden Reihen und die Spalte
/// sind Caelestias Raster: oben Wetter und Benutzer (130 hoch), unten Uhr,
/// Kalender, Ressourcen (250 hoch), rechts die Medien (200 breit).
public enum DashboardZone: String, CaseIterable, Identifiable, Sendable {
    case top, bottom, side

    public var id: Self { self }

    public var title: String {
        switch self {
        case .top: String(localized: "Obere Reihe")
        case .bottom: String(localized: "Untere Reihe")
        case .side: String(localized: "Seitenspalte")
        }
    }

    /// Reihen stellen Karten nebeneinander; die Spalte hat Platz fuer eine.
    public var isRow: Bool { self != .side }
}

/// Wie breit eine Karte in einer Reihe ist. Feste Karten haben ihr
/// Caelestia-Mass; flexible teilen sich den Rest und brauchen mindestens
/// `minimum`, damit ihr Inhalt nicht abgeschnitten wird.
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

// MARK: - Arten

/// Welche Karten es gibt; jede hoechstens einmal (es gibt ein Wetter, einen
/// Benutzer, eine Wiedergabe). Rohwert in settings.json ("kind").
public enum DashboardCardKind: String, CaseIterable, Identifiable, Sendable {
    case weather, user, clock, calendar, resources, media

    public var id: Self { self }

    public var title: String {
        switch self {
        case .weather: String(localized: "Wetter")
        case .user: String(localized: "Benutzer")
        case .clock: String(localized: "Uhr")
        case .calendar: String(localized: "Kalender")
        case .resources: String(localized: "Ressourcen")
        case .media: String(localized: "Medien")
        }
    }

    /// Eine Zeile fuer die Galerie hinter dem +.
    public var summary: String {
        switch self {
        case .weather: String(localized: "Temperatur und Wetterlage am gewählten Ort.")
        case .user: String(localized: "Name, macOS-Version und wie lange der Mac läuft.")
        case .clock: String(localized: "Stunde und Minute, auf Wunsch mit Datum.")
        case .calendar: String(localized: "Der Monat mit heute markiert, zum Blättern.")
        case .resources: String(localized: "CPU, Arbeitsspeicher und Speicher als Ringe.")
        case .media: String(localized: "Was gerade läuft, mit Cover und Knöpfen.")
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

    /// Wo die Karte bei Caelestia steht - dorthin kommt sie beim Hinzufuegen.
    public var home: DashboardZone {
        switch self {
        case .weather, .user: .top
        case .clock, .calendar, .resources: .bottom
        case .media: .side
        }
    }

    /// Wo sie hin darf, `home` zuerst. Der Kalender braucht die Hoehe der
    /// unteren Reihe (sechs Wochen) und mehr Breite als die Spalte hat.
    public var zones: [DashboardZone] {
        switch self {
        case .calendar: [.bottom]
        case .weather, .user: [.top, .bottom, .side]
        case .clock, .resources: [.bottom, .top, .side]
        case .media: [.side, .top, .bottom]
        }
    }

    public func allows(_ zone: DashboardZone) -> Bool { zones.contains(zone) }

    /// Breite in einer Reihe; in der Spalte fuellt jede Karte die Spalte.
    /// Absichtlich unabhaengig von den Optionen: sonst koennte ein Schalter
    /// (drei statt zwei Ringe) eine volle Reihe sprengen.
    public func width(in zone: DashboardZone) -> DashboardCardWidth {
        switch (self, zone) {
        case (_, .side): .fixed(DashboardGeometry.sideWidth)
        // Caelestia-Masse der Vorgabe.
        case (.weather, .top): .fixed(275)
        case (.user, .top): .flexible(minimum: 230)
        case (.clock, _): .fixed(110)
        case (.calendar, _): .flexible(minimum: 300)
        case (.resources, .bottom): .fixed(90)
        // Neue Plaetze: drei Ringe nebeneinander, Wiedergabe als Streifen,
        // Wetter, Benutzer und Wiedergabe hochkant in der unteren Reihe.
        case (.resources, _): .fixed(230)
        case (.media, .top): .flexible(minimum: 300)
        case (.weather, _), (.user, _), (.media, _): .fixed(200)
        }
    }
}

// MARK: - Optionen je Karte

// Nachsichtig wie ShellSettings: fehlt ein Schluessel oder hat er den
// falschen Typ, gilt fuer genau diesen die Vorgabe. Vorgabe = Caelestia.

public struct DashboardWeatherOptions: Codable, Equatable, Sendable {
    /// "Teilweise bewölkt" unter der Temperatur.
    public var showCondition: Bool
    /// Hoechst- und Tiefstwert von heute.
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
    /// `stacked`: Stunde, drei Punkte, Minute untereinander (Caelestia).
    /// `inline`: "14:05" in einer Zeile.
    public enum Style: String, Codable, CaseIterable, Sendable { case stacked, inline }

    public var style: Style
    /// Wochentag und Tag unter der Uhrzeit.
    public var showDate: Bool

    public init(style: Style = .stacked, showDate: Bool = false) {
        self.style = style
        self.showDate = showDate
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.style, into: &style)
        c.lenient(.showDate, into: &showDate)
    }
}

public struct DashboardCalendarOptions: Codable, Equatable, Sendable {
    public enum FirstWeekday: String, Codable, CaseIterable, Sendable {
        case monday, sunday

        /// Wert fuer `Calendar.firstWeekday` (1 = Sonntag).
        public var calendarValue: Int { self == .monday ? 2 : 1 }
    }

    public var firstWeekday: FirstWeekday
    /// Kalenderwoche links neben jeder Zeile.
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

    /// Derselbe Kalender (Sprache, Zeitzone), nur mit dem gewaehlten ersten
    /// Wochentag. Die Regel fuer die erste Woche (in der Schweiz: vier Tage,
    /// ISO 8601) bleibt die der Sprache.
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

    /// Alle drei aus (von Hand so geschrieben): wieder alle an - eine leere
    /// Karte ergibt keinen Sinn. Nexus laesst den letzten Ring gar nicht
    /// ausschalten.
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
    /// App, die gerade spielt, unten in der Karte (nur in der Seitenspalte,
    /// sonst fehlt der Platz).
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

// MARK: - Karte

/// Art und Optionen in einem, wie `BarModule`: jede Art traegt genau ihren
/// Optionstyp. Kennung ist die Art selbst - jede Karte gibt es einmal.
///
/// In der Datei: `{"kind": "clock", "options": {...}}`.
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

    /// Art und (falls vorhanden) gelesene Optionen - der eine Switch fuer
    /// beides, wie `BarModule.init(kind:options:)`.
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

    /// Optionen dieser Karte - jede Art hat welche, anders als bei
    /// `BarModule` oder `UtilitiesToggle`.
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

    /// Unbekannte Art: Fehler - `DashboardCards` uebergeht die Karte dann.
    /// Kaputte Optionen dagegen nur Vorgaben.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw: String = c.lenient(.kind), let kind = DashboardCardKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unbekannte Karte")
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

// MARK: - Karten der Uebersicht

/// Welche Karte wo steht, je Platz von links nach rechts. Eine Karte, die
/// in keinem Platz steht, ist ausgeschaltet (wie bei der Leiste).
///
/// Immer gueltig - dafuer sorgen der Initialisierer (auch beim Lesen) und
/// die Aenderungen unten, deshalb sind die Listen von aussen nur lesbar:
/// - jede Art hoechstens einmal,
/// - nur an erlaubten Plaetzen (`DashboardCardKind.zones`),
/// - in der Spalte hoechstens eine Karte,
/// - jede Reihe passt auch neben der Spalte (`DashboardGeometry.rowWidth`):
///   feste Breiten plus Mindestbreiten plus Abstaende. Gemessen wird immer
///   mit Spalte, sonst sprengte das Hinzufuegen einer Spaltenkarte spaeter
///   eine Reihe, die vorher gerade noch passte.
///
/// In der Datei: `{"top": [...], "bottom": [...], "side": [...]}`. Fehlt ein
/// Platz oder ist er keine Liste, gilt fuer ihn die Vorgabe; eine leere
/// Liste ist ein leerer Platz.
public struct DashboardCards: Codable, Equatable, Sendable {
    public private(set) var top: [DashboardCard]
    public private(set) var bottom: [DashboardCard]
    public private(set) var side: [DashboardCard]

    public init(top: [DashboardCard] = [], bottom: [DashboardCard] = [], side: [DashboardCard] = []) {
        (self.top, self.bottom, self.side) = Self.normalized(top: top, bottom: bottom, side: side)
    }

    /// Kurzform mit Vorgaben je Art (Vorlagen, Tests).
    public init(top: [DashboardCardKind], bottom: [DashboardCardKind], side: [DashboardCardKind]) {
        self.init(top: top.map(DashboardCard.init), bottom: bottom.map(DashboardCard.init),
                  side: side.map(DashboardCard.init))
    }

    /// Caelestias Raster, die Vorgabe.
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

    // MARK: Lesen

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

    /// Passen diese Karten nebeneinander in den Platz?
    public static func fits(_ cards: [DashboardCard], in zone: DashboardZone) -> Bool {
        guard zone.isRow else { return cards.count <= 1 }
        let widths = cards.map { $0.kind.width(in: zone).minimum }
        let gaps = Double(max(cards.count - 1, 0)) * DashboardGeometry.spacing
        return widths.reduce(0, +) + gaps <= DashboardGeometry.rowWidth
    }

    /// Wohin eine ausgeschaltete Karte beim Hinzufuegen kaeme: an ihren
    /// Caelestia-Platz, sonst an den ersten erlaubten mit genug Raum.
    public func placement(for kind: DashboardCardKind) -> DashboardZone? {
        guard !contains(kind) else { return nil }
        return kind.zones.first { Self.fits(self[$0] + [DashboardCard(kind)], in: $0) }
    }

    public func canAdd(_ kind: DashboardCardKind) -> Bool { placement(for: kind) != nil }

    /// Darf die Karte an diesen Platz? Bei belegter Spalte heisst das
    /// tauschen - dann muss die bisherige an den alten Platz der Karte passen.
    public func canMove(_ kind: DashboardCardKind, to zone: DashboardZone) -> Bool {
        var copy = self
        return copy.move(kind, to: zone)
    }

    public func canSwap(_ a: DashboardCardKind, _ b: DashboardCardKind) -> Bool {
        var copy = self
        return copy.swap(a, b)
    }

    // MARK: Aendern

    /// Mit Vorgaben an `placement(for:)`, ans Ende. Gibt den Platz zurueck;
    /// `nil`, wenn die Karte schon da ist oder nirgends Raum hat.
    @discardableResult
    public mutating func add(_ kind: DashboardCardKind) -> DashboardZone? {
        guard let zone = placement(for: kind) else { return nil }
        set(zone, self[zone] + [DashboardCard(kind)])
        return zone
    }

    public mutating func remove(_ kind: DashboardCardKind) {
        for zone in DashboardZone.allCases { set(zone, self[zone].filter { $0.kind != kind }) }
    }

    /// Andere Optionen fuer eine Karte, die schon da ist. Platz und
    /// Reihenfolge bleiben (die Breite haengt nie an den Optionen).
    public mutating func update(_ card: DashboardCard) {
        guard let zone = zone(of: card.kind) else { return }
        set(zone, self[zone].map { $0.kind == card.kind ? card : $0 })
    }

    /// Wie SwiftUIs `onMove`, innerhalb eines Platzes.
    public mutating func move(in zone: DashboardZone, fromOffsets source: IndexSet, toOffset destination: Int) {
        var cards = self[zone]
        cards.move(fromOffsets: source, toOffset: destination)
        set(zone, cards)
    }

    /// Eine Stelle nach links (-1) oder rechts (+1) im eigenen Platz.
    public mutating func move(_ kind: DashboardCardKind, by step: Int) {
        guard let zone = zone(of: kind), let card = self[kind: kind] else { return }
        set(zone, Reorder.move(self[zone], element: card, by: step))
    }

    /// An einen anderen Platz, dort ans Ende. Die Spalte hat nur Raum fuer
    /// eine Karte: ist sie belegt, tauschen die beiden die Plaetze.
    /// `false` (und nichts geaendert), wenn es nicht geht.
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

    /// Zwei Karten tauschen Platz und Stelle. `false` (und nichts
    /// geaendert), wenn eine am Platz der anderen nicht stehen darf oder
    /// eine Reihe danach zu breit waere.
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

    // MARK: Regeln

    /// Der Reihe nach (oben, unten, Spalte, je von links): was eine Regel
    /// verletzt, faellt weg, der Rest bleibt. Doppelte Karte: die erste gilt.
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

/// Alles, was Nexus > Dashboard am Aufbau aendert (settings.json: dashboard).
/// Vorgabe = Caelestia = das Dashboard vor dem Baukasten; wer keine Datei
/// oder keinen Abschnitt `dashboard` hat, sieht also dasselbe wie vorher.
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

    /// Ob das offene Dashboard Wetter braucht. Abrufen kostet eine Anfrage
    /// ins Netz, die Wiedergabe einen perl-Prozess - ohne sichtbare Karte
    /// und ohne Reiter faengt das Dashboard damit gar nicht erst an. Karten
    /// zaehlen nur, wenn der Reiter Dashboard (die Uebersicht) sichtbar ist.
    public var usesWeather: Bool { uses(.weather, tab: .weather) }
    public var usesMedia: Bool { uses(.media, tab: .media) }

    private func uses(_ card: DashboardCardKind, tab: DashboardTab) -> Bool {
        tabs.isVisible(tab) || (tabs.isVisible(.dashboard) && cards.contains(card))
    }
}

// MARK: - Vorlagen

/// Fertige Dashboards zum Laden in Nexus. Reine Daten; "Caelestia" ist die
/// Vorgabe und genau das bisherige Dashboard.
public enum DashboardPreset: String, CaseIterable, Identifiable, Sendable {
    case caelestia, compact, calendarWeather

    public var id: Self { self }

    public var title: String {
        switch self {
        case .caelestia: "Caelestia"
        case .compact: String(localized: "Kompakt")
        case .calendarWeather: String(localized: "Kalender & Wetter")
        }
    }

    public var summary: String {
        switch self {
        case .caelestia: String(localized: "Die Vorgabe: Wetter und Benutzer oben, Uhr, Kalender und Ressourcen unten, Medien rechts.")
        case .compact: String(localized: "Ohne Seitenspalte: die Wiedergabe als Streifen neben dem Wetter, darunter Uhr, Kalender und Ressourcen.")
        case .calendarWeather: String(localized: "Nur Kalender, Uhr und Wetter, dazu die Reiter Dashboard und Wetter. Ruhig, ohne Messwerte.")
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

// MARK: - Masse

/// Lage einer Karte in der Uebersicht, ab der Oberkante links des Rasters.
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

/// Wie das Raster seine feste Flaeche verteilt:
///
/// - Beide Reihen belegt: oben 130, unten 250 hoch (Caelestia). Ist eine
///   Reihe leer, bekommt die andere die ganze Hoehe.
/// - Spalte belegt: 200 breit rechts, die Reihen links daneben. Ist links
///   alles leer, bekommt die Spaltenkarte die ganze Breite.
/// - In einer Reihe bekommen feste Karten ihre Breite, flexible teilen sich
///   den Rest. Ohne flexible werden alle im Verhaeltnis ihrer Breite
///   gestreckt - leere Plaetze fuellen die Nachbarn, statt Loecher zu lassen.
/// - Nur ganze Punkte; was beim Teilen uebrig bleibt, bekommt die letzte
///   Karte. So stehen Kanten scharf auf dem Raster.
public enum DashboardGeometry {
    public static let width: Double = 839
    public static let height: Double = 392
    public static let spacing: Double = 12
    public static let topHeight: Double = 130
    public static let sideWidth: Double = 200
    /// Breite der Reihen neben der Spalte (627) - daran misst `DashboardCards.fits`.
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

    /// Breiten einer Reihe, siehe oben. Passt es nicht einmal mit den
    /// Mindestbreiten (kommt nach `DashboardCards.fits` nicht vor), wird
    /// alles im Verhaeltnis gestaucht statt ueber den Rand zu laufen.
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
        // Keine flexible, oder zu eng: im Verhaeltnis der (Mindest-)Breiten.
        guard minimumSum > 0 else { return widths.map { _ in 0 } }
        var result = minimums.map { ($0 * room / minimumSum).rounded(.down) }
        result[result.count - 1] += room - result.reduce(0, +)
        return result
    }
}

// MARK: - Hilfen

/// Eine Stelle nach vorn oder hinten, dieselbe Regel wie `PinnedList.move(_:by:)`
/// - anders als `move(fromOffsets:toOffset:)` (siehe `Array.move` in
/// Reorder.swift) nur an zwei Stellen gebraucht (Reiter, Dashboard-Karte),
/// darum keine eigene Datei.
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
