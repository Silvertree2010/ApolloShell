import Foundation

// Die Leiste als Baukasten: eine geordnete Liste von Bausteinen, jeder mit
// eigener Kennung und eigenen Optionen. Nexus > Leiste bearbeitet sie
// (ziehen, +, Vorlagen), die Leiste zeichnet sie der Reihe nach.
//
// Caelestia fuehrt die Leiste ebenso als Liste (bar.entries mit id und
// enabled). Hier ohne `enabled`: ein ausgeschalteter Baustein ist einer, der
// nicht in der Liste steht - ein Zustand weniger, den man verstehen muss.

// MARK: - Arten

/// Welche Bausteine es gibt. Der Rohwert steht in settings.json ("kind"),
/// deshalb nie umbenennen, hoechstens neue dazu. Eine unbekannte Art (Datei
/// aus einer neueren Fassung, von Hand verschrieben) wird beim Lesen
/// uebergangen, statt die ganze Leiste zu verwerfen.
public enum BarModuleKind: String, CaseIterable, Sendable, Identifiable {
    // Die sieben der bisherigen festen Leiste.
    case dashboardButton, workspaces, dock, clock, utilitiesButton, statusIcons, power
    // Neu dazu, fuer andere Geschmaecker.
    case spacer, gap, divider, appButton, battery, cpu, weather, mediaButton

    public var id: Self { self }

    /// Teilt sich die freie Hoehe mit den anderen flexiblen (`BarFlex`).
    public var isFlexible: Bool { self == .dock || self == .spacer }

    /// Hoechstens einmal: das Dock (Ziehen und Ablegen schreibt Apples
    /// Dock-Liste - zwei Spalten mit demselben Inhalt ergaeben keinen Sinn)
    /// und die Statussymbole (das Popout haengt an der Lage ihrer Symbole;
    /// bei zwei Kapseln wuesste es nicht, an welcher).
    public var isUnique: Bool { self == .dock || self == .statusIcons }

    public var title: String {
        switch self {
        case .dashboardButton: String(localized: "Dashboard")
        case .workspaces: String(localized: "Spaces")
        case .dock: String(localized: "Dock")
        case .clock: String(localized: "Uhr")
        case .utilitiesButton: String(localized: "Utilities")
        case .statusIcons: String(localized: "Statussymbole")
        case .power: String(localized: "Ausschalten")
        case .spacer: String(localized: "Flexibler Abstand")
        case .gap: String(localized: "Fester Abstand")
        case .divider: String(localized: "Trennlinie")
        case .appButton: String(localized: "App")
        case .battery: String(localized: "Akku")
        case .cpu: String(localized: "CPU")
        case .weather: String(localized: "Wetter")
        case .mediaButton: String(localized: "Medien")
        }
    }

    /// Eine Zeile fuer die Galerie hinter dem +.
    public var summary: String {
        switch self {
        case .dashboardButton: String(localized: "Öffnet das Dashboard mit Kalender, Medien und Wetter.")
        case .workspaces: String(localized: "Ein Punkt oder eine Nummer je Schreibtisch.")
        case .dock: String(localized: "Angeheftete und laufende Apps wie in Apples Dock.")
        case .clock: String(localized: "Stunde und Minute untereinander, auf Wunsch mit Datum.")
        case .utilitiesButton: String(localized: "Öffnet das Utilities-Panel.")
        case .statusIcons: String(localized: "WLAN, Bluetooth und Akku; ein Klick zeigt Details.")
        case .power: String(localized: "Öffnet das Sitzungsmenü.")
        case .spacer: String(localized: "Füllt freien Platz; teilt ihn mit Dock und anderen Abständen.")
        case .gap: String(localized: "Leerraum mit fester Höhe.")
        case .divider: String(localized: "Kurzer Strich zwischen zwei Gruppen.")
        case .appButton: String(localized: "Startet eine gewählte App mit einem Klick.")
        case .battery: String(localized: "Ladestand in Prozent.")
        case .cpu: String(localized: "Auslastung als Ring oder Zahl, alle 2 Sekunden.")
        case .weather: String(localized: "Symbol und Temperatur vom Ort des Dashboards.")
        case .mediaButton: String(localized: "Öffnet das Dashboard beim Reiter Medien.")
        }
    }

    /// SF Symbol fuer Liste und Galerie.
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

// MARK: - Optionen je Art

// Alle Optionen lesen nachsichtig wie ShellSettings: fehlt ein Schluessel
// oder hat er den falschen Typ, gilt fuer genau diesen die Vorgabe.

public struct BarWorkspacesOptions: Codable, Equatable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable { case dots, numbers }
    public var style: Style

    public init(style: Style = .dots) { self.style = style }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = c.lenient(.style) ?? .dots
    }
}

public struct BarDockOptions: Codable, Equatable, Sendable {
    public enum IconSize: String, Codable, CaseIterable, Sendable {
        case small, medium, large

        /// Kantenlaenge des Symbols. Der Rahmen bleibt 32 wie bei allen
        /// Knoepfen der Leiste; "gross" fuellt ihn fast.
        public var points: Double {
            switch self {
            case .small: 22
            case .medium: 26
            case .large: 30
            }
        }
    }

    /// Auch Apps, die laufen, aber nicht angeheftet sind (unter dem Strich).
    public var showRunning: Bool
    public var iconSize: IconSize

    public init(showRunning: Bool = true, iconSize: IconSize = .medium) {
        self.showRunning = showRunning
        self.iconSize = iconSize
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showRunning = c.lenient(.showRunning) ?? true
        iconSize = c.lenient(.iconSize) ?? .medium
    }
}

/// Caelestia: bar.clock. Ohne `showSeconds`: dafuer muesste die Leiste jede
/// Sekunde neu zeichnen statt jede Minute. Gleiche Schluessel wie das alte
/// `bar.clock`, damit die Migration es unveraendert lesen kann.
public struct BarClockOptions: Codable, Equatable, Sendable {
    public var showIcon: Bool
    public var showDate: Bool

    public init(showIcon: Bool = true, showDate: Bool = false) {
        self.showIcon = showIcon
        self.showDate = showDate
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showIcon = c.lenient(.showIcon) ?? true
        showDate = c.lenient(.showDate) ?? false
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
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showWifi = c.lenient(.showWifi) ?? true
        showBluetooth = c.lenient(.showBluetooth) ?? true
        showBattery = c.lenient(.showBattery) ?? true
    }
}

public struct BarGapOptions: Codable, Equatable, Sendable {
    public static let range: ClosedRange<Double> = 4...96
    public static let standard: Double = 16

    /// Zusaetzlich zum ueblichen Abstand zwischen zwei Bausteinen. Immer im
    /// Bereich: eine von Hand verschriebene 10000 wuerde sonst die ganze
    /// Leiste sprengen, und NaN liesse sich nicht einmal speichern.
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
        let c = try decoder.container(keyedBy: CodingKeys.self)
        height = Self.clamped(c.lenient(.height) ?? Self.standard)
    }

    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return standard }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

public struct BarAppButtonOptions: Codable, Equatable, Sendable {
    /// Leer, bis in Nexus eine App gewaehlt ist; die Leiste zeigt dann einen
    /// gestrichelten Platzhalter.
    public var bundleID: String

    public init(bundleID: String = "") { self.bundleID = bundleID }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = c.lenient(.bundleID) ?? ""
    }
}

public struct BarBatteryOptions: Codable, Equatable, Sendable {
    /// Akkusymbol ueber der Zahl.
    public var showIcon: Bool

    public init(showIcon: Bool = true) { self.showIcon = showIcon }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showIcon = c.lenient(.showIcon) ?? true
    }
}

public struct BarCPUOptions: Codable, Equatable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable { case ring, percent }
    public var style: Style

    public init(style: Style = .ring) { self.style = style }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = c.lenient(.style) ?? .ring
    }
}

public struct BarWeatherOptions: Codable, Equatable, Sendable {
    public var showTemperature: Bool

    public init(showTemperature: Bool = true) { self.showTemperature = showTemperature }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showTemperature = c.lenient(.showTemperature) ?? true
    }
}

// MARK: - Baustein

/// Art und Optionen in einem: jede Art traegt genau ihren Optionstyp, eine
/// Uhr kann also keine Dock-Optionen haben.
public enum BarModule: Equatable, Sendable {
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

    /// Mit den Vorgaben der Art.
    public init(_ kind: BarModuleKind) {
        self = switch kind {
        case .dashboardButton: .dashboardButton
        case .workspaces: .workspaces(.init())
        case .dock: .dock(.init())
        case .clock: .clock(.init())
        case .utilitiesButton: .utilitiesButton
        case .statusIcons: .statusIcons(.init())
        case .power: .power
        case .spacer: .spacer
        case .gap: .gap(.init())
        case .divider: .divider
        case .appButton: .appButton(.init())
        case .battery: .battery(.init())
        case .cpu: .cpu(.init())
        case .weather: .weather(.init())
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

    /// Ob Nexus fuer diesen Baustein Optionen aufklappen laesst.
    public var hasOptions: Bool {
        switch self {
        case .dashboardButton, .utilitiesButton, .power, .spacer, .divider, .mediaButton: false
        default: true
        }
    }

    // Lesezugriff auf die Optionen einer Art; `nil` bei jeder anderen.
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

/// Ein Platz in der Leiste. Die Kennung bleibt beim Umsortieren und beim
/// Aendern der Optionen gleich - SwiftUI haelt daran Zustand und Animation
/// fest, und Nexus weiss, welche Zeile aufgeklappt ist.
///
/// In der Datei: `{"id": "clock", "kind": "clock", "options": {...}}`;
/// `options` fehlt bei Arten ohne Optionen.
public struct BarEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var module: BarModule

    public var kind: BarModuleKind { module.kind }

    public init(id: String, module: BarModule) {
        self.id = id
        self.module = module
    }

    /// Mit den Vorgaben; Kennung = Name der Art (in einer Leiste eindeutig
    /// gemacht von `BarLayout`).
    public init(_ kind: BarModuleKind, id: String? = nil) {
        self.init(id: id ?? kind.rawValue, module: BarModule(kind))
    }

    /// Mit Optionen. Eigene Beschriftung: `.power` gibt es als Art und als
    /// Baustein, ohne sie waere `BarEntry(.power)` mehrdeutig.
    public init(module: BarModule, id: String? = nil) {
        self.init(id: id ?? module.kind.rawValue, module: module)
    }

    private enum CodingKeys: String, CodingKey { case id, kind, options }

    /// Unbekannte oder fehlende Art: Fehler - `BarLayout` uebergeht den
    /// Eintrag dann. Kaputte Optionen dagegen nur Vorgaben.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw: String = c.lenient(.kind), let kind = BarModuleKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unbekannter Baustein")
        }
        // Fehlt die Kennung, vergibt `BarLayout` eine.
        id = c.lenient(.id) ?? ""
        module = switch kind {
        case .dashboardButton: .dashboardButton
        case .workspaces: .workspaces(c.lenient(.options) ?? .init())
        case .dock: .dock(c.lenient(.options) ?? .init())
        case .clock: .clock(c.lenient(.options) ?? .init())
        case .utilitiesButton: .utilitiesButton
        case .statusIcons: .statusIcons(c.lenient(.options) ?? .init())
        case .power: .power
        case .spacer: .spacer
        case .gap: .gap(c.lenient(.options) ?? .init())
        case .divider: .divider
        case .appButton: .appButton(c.lenient(.options) ?? .init())
        case .battery: .battery(c.lenient(.options) ?? .init())
        case .cpu: .cpu(c.lenient(.options) ?? .init())
        case .weather: .weather(c.lenient(.options) ?? .init())
        case .mediaButton: .mediaButton
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .kind)
        switch module {
        case .workspaces(let o): try c.encode(o, forKey: .options)
        case .dock(let o): try c.encode(o, forKey: .options)
        case .clock(let o): try c.encode(o, forKey: .options)
        case .statusIcons(let o): try c.encode(o, forKey: .options)
        case .gap(let o): try c.encode(o, forKey: .options)
        case .appButton(let o): try c.encode(o, forKey: .options)
        case .battery(let o): try c.encode(o, forKey: .options)
        case .cpu(let o): try c.encode(o, forKey: .options)
        case .weather(let o): try c.encode(o, forKey: .options)
        case .dashboardButton, .utilitiesButton, .power, .spacer, .divider, .mediaButton: break
        }
    }
}

// MARK: - Leiste

/// Die Bausteine von oben nach unten. Immer gueltig: Kennungen eindeutig und
/// nie leer, Dock und Statussymbole hoechstens einmal - dafuer sorgen der
/// Initialisierer (auch beim Lesen) und die Aenderungen unten, deshalb ist
/// `entries` von aussen nur lesbar.
///
/// In der Datei eine schlichte Liste. Unlesbare Eintraege (unbekannte Art,
/// kein Objekt) fallen weg, der Rest bleibt.
public struct BarLayout: Codable, Equatable, Sendable {
    public private(set) var entries: [BarEntry]

    public init(_ entries: [BarEntry] = []) {
        self.entries = Self.normalized(entries)
    }

    public init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var list: [BarEntry] = []
        while !c.isAtEnd {
            // `Tolerant` scheitert nie, der Zeiger rueckt also immer weiter.
            // Falls doch (ein Decoder, der das anders haelt): abbrechen statt
            // endlos auf derselben Stelle stehen.
            guard let item = try? c.decode(Tolerant.self) else { break }
            if let entry = item.entry { list.append(entry) }
        }
        entries = Self.normalized(list)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(entries)
    }

    private struct Tolerant: Decodable {
        let entry: BarEntry?
        init(from decoder: any Decoder) {
            entry = try? BarEntry(from: decoder)
        }
    }

    // MARK: Lesen

    public subscript(id id: String) -> BarEntry? {
        entries.first { $0.id == id }
    }

    public func contains(_ kind: BarModuleKind) -> Bool {
        entries.contains { $0.kind == kind }
    }

    /// Fuer die Galerie: ein zweites Dock gibt es nicht.
    public func canAdd(_ kind: BarModuleKind) -> Bool {
        !kind.isUnique || !contains(kind)
    }

    public var flexibleCount: Int {
        entries.filter { $0.kind.isFlexible }.count
    }

    /// Wo ein neuer Baustein hinkommt: direkt unter den letzten flexiblen
    /// (Dock, Abstand) - also oben in die untere Gruppe, bei der
    /// Caelestia-Leiste zwischen Dock und Uhr. Ohne flexiblen vor ein
    /// abschliessendes Ausschalten, sonst ans Ende.
    public var insertionIndex: Int {
        if let last = entries.lastIndex(where: { $0.kind.isFlexible }) { return last + 1 }
        if entries.last?.kind == .power { return entries.count - 1 }
        return entries.count
    }

    // MARK: Aendern

    /// Neuer Baustein mit Vorgaben, ohne `index` an der ueblichen Stelle.
    /// Gibt seine Kennung zurueck; `nil`, wenn die Art schon da ist und nur
    /// einmal vorkommen darf.
    @discardableResult
    public mutating func add(_ kind: BarModuleKind, at index: Int? = nil) -> String? {
        guard canAdd(kind) else { return nil }
        let id = Self.uniqueID(for: kind, taken: Set(entries.map(\.id)))
        let position = min(max(index ?? insertionIndex, 0), entries.count)
        entries.insert(BarEntry(id: id, module: BarModule(kind)), at: position)
        return id
    }

    public mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    /// Andere Optionen fuer einen Baustein. Die Art bleibt: aus einer Uhr
    /// wird so kein zweites Dock.
    public mutating func update(id: String, to module: BarModule) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].kind == module.kind else { return }
        entries[index].module = module
    }

    /// Wie SwiftUIs `onMove`: `destination` zaehlt in der Liste VOR dem
    /// Verschieben ("vor Zeile n einfuegen") - wie `PinnedList.move`.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { entries.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { entries[$0] }
        let before = valid.filter { $0 < destination }.count
        var rest = entries.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let target = min(max(destination - before, 0), rest.count)
        rest.insert(contentsOf: moving, at: target)
        entries = rest
    }

    /// Eine Stelle nach oben (-1) oder unten (+1); am Rand nichts. Fuer das
    /// Kontextmenue, damit es auch ohne Ziehen geht.
    public mutating func move(id: String, by step: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let target = index + step
        guard entries.indices.contains(target) else { return }
        entries.swapAt(index, target)
    }

    // MARK: Regeln

    /// Doppelte Dock/Statussymbole weg (der erste bleibt), leere oder
    /// doppelte Kennungen neu - ohne einer spaeteren ihre ausdrueckliche
    /// Kennung wegzunehmen.
    static func normalized(_ list: [BarEntry]) -> [BarEntry] {
        var kinds = Set<BarModuleKind>()
        var used = Set<String>()
        var taken = Set(list.map(\.id))
        var result: [BarEntry] = []
        for var entry in list {
            if entry.kind.isUnique, !kinds.insert(entry.kind).inserted { continue }
            if entry.id.isEmpty || used.contains(entry.id) {
                entry.id = uniqueID(for: entry.kind, taken: taken)
                taken.insert(entry.id)
            }
            used.insert(entry.id)
            result.append(entry)
        }
        return result
    }

    /// "clock", sonst "clock-2", "clock-3" ... - lesbar in settings.json.
    static func uniqueID(for kind: BarModuleKind, taken: Set<String>) -> String {
        if !taken.contains(kind.rawValue) { return kind.rawValue }
        var n = 2
        while taken.contains("\(kind.rawValue)-\(n)") { n += 1 }
        return "\(kind.rawValue)-\(n)"
    }

    // MARK: Migration

    /// Aus den Schaltern vor dem Baukasten (bar.showWorkspaces usw.): genau
    /// die Leiste, die sie zeigten. Ohne Dock stand dort ein Abstand, der
    /// die untere Gruppe unten hielt - daher dann `spacer` an seiner Stelle.
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

// MARK: - Vorlagen

/// Fertige Leisten zum Laden in Nexus. Reine Daten; "Caelestia" ist die
/// Vorgabe und genau die bisherige Leiste.
public enum BarPreset: String, CaseIterable, Identifiable, Sendable {
    case caelestia, minimal, dockOnly, everything

    public var id: Self { self }

    public var title: String {
        switch self {
        case .caelestia: "Caelestia"
        case .minimal: "Minimal"
        case .dockOnly: "Nur Dock"
        case .everything: "Alles"
        }
    }

    public var summary: String {
        switch self {
        case .caelestia: "Die Vorgabe: Dashboard, Spaces, Dock, Uhr, Utilities, Status, Ausschalten."
        case .minimal: "Spaces oben, Uhr und Ausschalten unten, sonst nichts."
        case .dockOnly: "Nur die Apps, über die ganze Höhe."
        case .everything: "Jeder Baustein einmal, zum Ausprobieren und Aussortieren."
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
            // Ohne flexiblen Abstand und festen Abstand: die teilten sich nur
            // den Platz mit dem Dock. Der Akku steht als eigener Baustein da,
            // deshalb nicht noch einmal in der Kapsel.
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

// MARK: - Hoehe verteilen

/// Lage eines Bausteins in der Leiste: Oberkante und Hoehe, ab der
/// Oberkante des Inhalts.
public struct BarSlot: Equatable, Sendable {
    public var y: Double
    public var height: Double

    public init(y: Double, height: Double) {
        self.y = y
        self.height = height
    }
}

/// Wie die Leiste ihre Hoehe verteilt:
///
/// - Feste Bausteine bekommen ihre eigene Hoehe, dazwischen `spacing`.
/// - Was uebrig bleibt, teilen sich die flexiblen (`nil` in `heights`:
///   Dock, Abstand) zu gleichen Teilen. So fuellt das Dock allein genau den
///   Platz zwischen oberer und unterer Gruppe - wie vor dem Baukasten.
/// - Ohne flexiblen stehen alle oben, der Rest bleibt unten frei.
/// - Reicht der Platz nicht, bekommen die flexiblen 0 (das Dock scrollt),
///   nie eine negative Hoehe.
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

private extension KeyedDecodingContainer {
    /// Fehlt der Schluessel oder passt der Typ nicht: `nil` statt Fehler.
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}
