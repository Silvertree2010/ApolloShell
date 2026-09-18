import Foundation

// Das Utilities-Panel als Baukasten: welche Karten in welcher Reihenfolge,
// welche Schnellschalter in welcher Reihenfolge. Nexus > Schnellaktionen
// bearbeitet es (ziehen, +, Vorlagen), das Panel zeichnet es und richtet
// seine Hoehe danach.
//
// Anders als die Leiste (`BarLayout`) stehen die Karten IMMER alle in der
// Liste, jede mit `enabled`: es sind drei feste, keine kommt doppelt vor, und
// wer eine ausschaltet, soll sie beim Wiedereinschalten an derselben Stelle
// finden. Die Schnellschalter dagegen sind wie die Leiste eine offene Liste:
// ausgeschaltet = nicht drin (Caelestia: utilities.quickToggles).

// MARK: - Karten

/// Die Karten des Panels. Der Rohwert steht in settings.json - nie
/// umbenennen, hoechstens neue dazu.
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
        case .keepAwake: "Mac wach halten, auf Wunsch auch zugeklappt."
        case .audio: "Lautstärke, Stumm, Ausgabe und Eingang."
        case .quickToggles: "Schalter und Aktionen, fünf pro Reihe."
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

/// Eine Karte und ob sie zu sehen ist. In der Datei:
/// `{"kind": "audio", "enabled": true}`.
public struct UtilitiesCardEntry: Codable, Equatable, Identifiable, Sendable {
    public var kind: UtilitiesCardKind
    public var enabled: Bool

    public var id: UtilitiesCardKind { kind }

    public init(_ kind: UtilitiesCardKind, enabled: Bool = true) {
        self.kind = kind
        self.enabled = enabled
    }

    /// Unbekannte Art: Fehler, `UtilitiesLayout` uebergeht den Eintrag.
    /// Fehlt `enabled` oder ist es kein Bool: an.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw: String = c.lenient(.kind), let kind = UtilitiesCardKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unbekannte Karte")
        }
        self.kind = kind
        enabled = c.lenient(.enabled) ?? true
    }
}

// MARK: - Schnellschalter: Arten

/// Wofuer die Galerie die Arten gruppiert.
public enum UtilitiesToggleGroup: String, CaseIterable, Sendable, Identifiable {
    case switches, actions, custom

    public var id: Self { self }

    public var title: String {
        switch self {
        case .switches: "Schalter"
        case .actions: "Aktionen"
        case .custom: "Eigene Knöpfe"
        }
    }

    public var kinds: [UtilitiesToggleKind] {
        UtilitiesToggleKind.allCases.filter { $0.group == self }
    }
}

/// Welche Knoepfe es gibt. Der Rohwert steht in settings.json ("kind") -
/// nie umbenennen. Unbekannte Arten (neuere Fassung, Tippfehler) fallen
/// beim Lesen weg, der Rest bleibt.
public enum UtilitiesToggleKind: String, CaseIterable, BlockKind, Sendable, Identifiable {
    // Die zehn des bisherigen festen Rasters, in seiner Reihenfolge.
    case wifi, microphone, bluetooth, darkMode, nightShift
    case screenshot, showDesktop, colorPicker, lockScreen, settings
    // Neu dazu.
    case displaySleep, hideApps
    case openApp, openLink, runShortcut

    public var id: Self { self }

    /// Eigene Knoepfe (App, Link, Kurzbefehl) darf es mehrmals geben - jeder
    /// mit anderem Ziel. Alle anderen hoechstens einmal: zwei WLAN-Schalter
    /// schalteten dasselbe.
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
        case .wifi: "WLAN"
        case .microphone: "Mikrofon"
        case .bluetooth: "Bluetooth"
        case .darkMode: "Dunkelmodus"
        case .nightShift: "Night Shift"
        case .screenshot: "Bildschirmfoto"
        case .showDesktop: "Schreibtisch"
        case .colorPicker: "Farbpipette"
        case .lockScreen: "Sperren"
        case .settings: "Einstellungen"
        case .displaySleep: "Bildschirm aus"
        case .hideApps: "Apps ausblenden"
        case .openApp: "App öffnen"
        case .openLink: "Link öffnen"
        case .runShortcut: "Kurzbefehl"
        }
    }

    /// Eine Zeile fuer die Galerie hinter dem +.
    public var summary: String {
        switch self {
        case .wifi: "WLAN ein- und ausschalten."
        case .microphone: "Standard-Mikrofon stummschalten."
        case .bluetooth: "Zeigt den Zustand, ein Klick öffnet die Einstellungen."
        case .darkMode: "Zwischen hell und dunkel wechseln."
        case .nightShift: "Wärmere Farben am Abend."
        case .screenshot: "Apples Leiste für Bildschirmfoto und Aufnahme."
        case .showDesktop: "Alle Fenster zur Seite, der Schreibtisch frei."
        case .colorPicker: "Farbe vom Bildschirm, Hexwert in die Zwischenablage."
        case .lockScreen: "Bildschirm sperren."
        case .settings: "Öffnet Nexus."
        case .displaySleep: "Schaltet die Bildschirme sofort aus, der Mac läuft weiter."
        case .hideApps: "Blendet alle Apps aus; auf Wunsch bleibt die vordere."
        case .openApp: "Startet eine gewählte App oder holt sie nach vorne."
        case .openLink: "Öffnet eine Adresse im Standardbrowser."
        case .runShortcut: "Führt einen Kurzbefehl aus, z. B. einen Fokus schalten."
        }
    }

    /// SF Symbol fuer Galerie und Standardaussehen. `nil` = Bluetooth-Rune
    /// (kein SF Symbol, siehe `QuickToggleLook.symbol`).
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

// MARK: - Schnellschalter: Optionen

// Alle Optionen lesen nachsichtig: fehlt ein Schluessel oder hat er den
// falschen Typ, gilt fuer genau diesen die Vorgabe. Leere Texte heissen
// "automatisch" (Name der App, Adresse, Standardsymbol).

public struct UtilitiesAppOptions: Codable, Equatable, Sendable {
    public static let fallbackSymbol = "app.fill"

    /// Leer, bis in Nexus eine App gewaehlt ist.
    public var bundleID: String
    /// Tooltip und VoiceOver; leer = Name der App.
    public var title: String
    /// Leer = das Symbol der App selbst.
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

    /// Ohne eigenes SF Symbol zeigt der Knopf das App-Symbol.
    public var usesAppIcon: Bool { symbol.trimmed.isEmpty }
}

public struct UtilitiesLinkOptions: Codable, Equatable, Sendable {
    public static let fallbackSymbol = "link"

    /// Wie eingegeben; `UtilitiesLink.url(from:)` macht daraus die Adresse.
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

/// Ein Kurzbefehl aus Apples Kurzbefehle-App. Beide gemerkt: die Kennung
/// ueberlebt Umbenennen, der Name ist lesbar und der Ersatz, falls die
/// Kennung (Datei von Hand, anderer Mac) nicht passt.
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
    /// Die App vorne bleibt stehen (wie ⌥⌘H "Andere ausblenden").
    public var keepFrontmost: Bool

    public init(keepFrontmost: Bool = false) { self.keepFrontmost = keepFrontmost }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.keepFrontmost, into: &keepFrontmost)
    }
}

// MARK: - Schnellschalter: Knopf

/// Art und Optionen in einem: nur die Arten mit Optionen tragen welche.
public enum UtilitiesToggle: BlockModule, Equatable, Sendable {
    case wifi, microphone, bluetooth, darkMode, nightShift
    case screenshot, showDesktop, colorPicker, lockScreen, settings
    case displaySleep
    case hideApps(UtilitiesHideAppsOptions)
    case openApp(UtilitiesAppOptions)
    case openLink(UtilitiesLinkOptions)
    case runShortcut(UtilitiesShortcutOptions)

    /// Mit den Vorgaben der Art.
    public init(_ kind: UtilitiesToggleKind) {
        self.init(kind: kind, options: nil)
    }

    /// Art und (falls vorhanden) gelesene Optionen - der eine Switch fuer
    /// beides, wie `BarModule.init(kind:options:)`.
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

    /// Optionen dieses Knopfs, `nil` bei einer Art ohne welche. Traegt
    /// `hasOptions` (siehe `BlockModule`) und das Schreiben in
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

/// Ein Platz im Raster. Die Kennung bleibt beim Umsortieren und Aendern
/// gleich - SwiftUI haelt daran Animation und Auswahl fest.
///
/// In der Datei: `{"id": "wifi", "kind": "wifi", "options": {...}}`;
/// `options` fehlt bei Arten ohne Optionen.
public struct UtilitiesToggleEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var toggle: UtilitiesToggle

    public var kind: UtilitiesToggleKind { toggle.kind }

    public init(id: String, toggle: UtilitiesToggle) {
        self.id = id
        self.toggle = toggle
    }

    /// Mit Vorgaben; Kennung = Name der Art (eindeutig gemacht von
    /// `UtilitiesLayout`).
    public init(_ kind: UtilitiesToggleKind, id: String? = nil) {
        self.init(id: id ?? kind.rawValue, toggle: UtilitiesToggle(kind))
    }

    public init(toggle: UtilitiesToggle, id: String? = nil) {
        self.init(id: id ?? toggle.kind.rawValue, toggle: toggle)
    }

    // `fileprivate`, nicht `private`: `UtilitiesToggle.init(kind:options:)`
    // braucht denselben Schluesseltyp, um die Optionen zu lesen.
    fileprivate enum CodingKeys: String, CodingKey { case id, kind, options }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw: String = c.lenient(.kind), let kind = UtilitiesToggleKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unbekannter Schnellschalter")
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

/// Fuer `BlockList<UtilitiesToggleEntry>`.
extension UtilitiesToggleEntry: Block {}

// MARK: - Panel

/// Karten und Schnellschalter. Immer gueltig: jede Karte genau einmal,
/// Kennungen der Knoepfe eindeutig und nie leer, feste Knoepfe hoechstens
/// einmal - dafuer sorgen die Initialisierer (auch beim Lesen) und die
/// Aenderungen unten, deshalb sind beide Listen von aussen nur lesbar.
///
/// In der Datei: `{"cards": [...], "quickToggles": [...]}`. Fehlt eine der
/// beiden Listen (oder ist sie keine), gilt fuer sie die Vorgabe; unlesbare
/// Eintraege fallen weg, der Rest bleibt.
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

    /// Das Panel vor dem Baukasten: alle drei Karten in Caelestias Reihenfolge ...
    public static let standardCards: [UtilitiesCardEntry] = UtilitiesCardKind.allCases.map { UtilitiesCardEntry($0) }
    /// ... und die zehn Knoepfe: oben die Schalter, unten die Aktionen.
    public static let standardToggles: [UtilitiesToggleEntry] = [
        .wifi, .microphone, .bluetooth, .darkMode, .nightShift,
        .screenshot, .showDesktop, .colorPicker, .lockScreen, .settings,
    ].map { UtilitiesToggleEntry($0) }

    // MARK: Lesen

    public subscript(toggle id: String) -> UtilitiesToggleEntry? {
        toggleBlocks[id: id]
    }

    public func isEnabled(_ kind: UtilitiesCardKind) -> Bool {
        cards.first { $0.kind == kind }?.enabled ?? false
    }

    public func contains(_ kind: UtilitiesToggleKind) -> Bool {
        toggleBlocks.contains(kind)
    }

    /// Fuer die Galerie: ein zweiter WLAN-Schalter nicht.
    public func canAdd(_ kind: UtilitiesToggleKind) -> Bool {
        toggleBlocks.canAdd(kind)
    }

    /// Was das Panel zeigt, von oben nach unten. Die Schnellschalter-Karte
    /// ohne einen einzigen Knopf faellt weg - eine leere Karte mit
    /// Ueberschrift saehe aus wie ein Fehler.
    public var visibleCards: [UtilitiesCardKind] {
        cards.filter { $0.enabled && ($0.kind != .quickToggles || !toggles.isEmpty) }.map(\.kind)
    }

    /// Die Knoepfe in Reihen zu `QuickToggles.columns`; die letzte darf
    /// kuerzer sein.
    public var toggleRows: [[UtilitiesToggleEntry]] {
        stride(from: 0, to: toggles.count, by: QuickToggles.columns).map {
            Array(toggles[$0..<min($0 + QuickToggles.columns, toggles.count)])
        }
    }

    /// Hoehe des Panels in Punkten - allein aus der Anordnung gerechnet,
    /// nicht gemessen. So kann kein Zustand (langer Geraetename, Wach halten
    /// an) sie aendern, und das Panel kennt seine Groesse, bevor es je
    /// gezeichnet hat. Die Ansicht haelt jede Karte auf genau diese Hoehe.
    public var panelHeight: Double {
        let heights = visibleCards.map { UtilitiesMetrics.cardHeight($0, toggleRows: toggleRows.count) }
        guard !heights.isEmpty else { return 2 * UtilitiesMetrics.padding + UtilitiesMetrics.emptyCardHeight }
        return 2 * UtilitiesMetrics.padding + heights.reduce(0, +)
            + Double(heights.count - 1) * UtilitiesMetrics.spacing
    }

    // MARK: Karten aendern

    public mutating func setCard(_ kind: UtilitiesCardKind, enabled: Bool) {
        guard let index = cards.firstIndex(where: { $0.kind == kind }) else { return }
        cards[index].enabled = enabled
    }

    /// Wie SwiftUIs `onMove` (Ziel vor dem Verschieben gezaehlt).
    public mutating func moveCards(fromOffsets source: IndexSet, toOffset destination: Int) {
        cards.move(fromOffsets: source, toOffset: destination)
    }

    /// Eine Stelle nach oben (-1) oder unten (+1); am Rand nichts.
    public mutating func moveCard(_ kind: UtilitiesCardKind, by step: Int) {
        guard let index = cards.firstIndex(where: { $0.kind == kind }), cards.indices.contains(index + step) else { return }
        cards.swapAt(index, index + step)
    }

    // MARK: Knoepfe aendern

    /// Neuer Knopf, ohne `index` hinten angehaengt (wie in Apples
    /// Kontrollzentrum). Gibt seine Kennung zurueck; `nil`, wenn es ihn nur
    /// einmal geben darf und er schon da ist.
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

    /// Andere Optionen fuer einen Knopf; die Art bleibt.
    public mutating func update(toggle id: String, to toggle: UtilitiesToggle) {
        toggleBlocks.update(id: id, to: UtilitiesToggleEntry(id: id, toggle: toggle))
    }

    public mutating func moveToggles(fromOffsets source: IndexSet, toOffset destination: Int) {
        toggleBlocks.move(fromOffsets: source, toOffset: destination)
    }

    /// Eine Stelle nach vorne (-1) oder hinten (+1); am Rand nichts.
    public mutating func moveToggle(_ id: String, by step: Int) {
        toggleBlocks.move(id: id, by: step)
    }

    /// Beim Ziehen im Raster: der gezogene Knopf nimmt den Platz dessen ein,
    /// ueber dem der Zeiger gerade ist; alles dazwischen rueckt eins weiter.
    /// So wandert er beim Ziehen sichtbar mit.
    public mutating func moveToggle(_ id: String, onto target: String) {
        toggleBlocks.move(id: id, onto: target)
    }

    // MARK: Regeln

    /// Jede Karte genau einmal (die erste zaehlt); fehlt eine - Datei aus
    /// einer aelteren Fassung mit weniger Karten -, kommt sie eingeschaltet
    /// ans Ende.
    static func normalizedCards(_ list: [UtilitiesCardEntry]) -> [UtilitiesCardEntry] {
        var seen = Set<UtilitiesCardKind>()
        var result = list.filter { seen.insert($0.kind).inserted }
        for kind in UtilitiesCardKind.allCases where !seen.contains(kind) {
            result.append(UtilitiesCardEntry(kind))
        }
        return result
    }
}

// MARK: - Masse

/// Die Masse des Panels, am festen Panel vor dem Baukasten abgemessen
/// (Bildprobe 14.09.: 430 x 426, jede Karte in jedem Zustand gleich hoch).
/// Die Ansicht setzt jede Karte auf genau diese Hoehe; `panelHeight` rechnet
/// damit. Aendert man eine Karte, muss die Zahl hier mit.
public enum UtilitiesMetrics {
    /// Caelestia: 430 breit, 16 Rand, 12 zwischen den Karten.
    public static let width = 430.0
    public static let padding = 16.0
    public static let spacing = 12.0
    /// Innenrand jeder Karte.
    public static let cardPadding = 14.0

    /// 40er Symbol-Chip plus Innenrand.
    public static let keepAwakeHeight = 68.0
    /// Ueberschrift 17, 10, Regler-Zeile 32, 10, Geraeteknoepfe 44, plus Innenrand.
    public static let audioHeight = 141.0
    /// Ueberschrift "Schnellschalter" (14 pt, eine Zeile).
    public static let toggleTitleHeight = 17.0
    public static let toggleTitleSpacing = 12.0
    public static let toggleHeight = 48.0
    public static let toggleRowSpacing = 8.0
    /// Hinweis, wenn nichts eingeblendet ist: eine Zeile wie "Wach halten".
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

// MARK: - Vorlagen

/// Fertige Panels zum Laden in Nexus. "Standard" ist die Vorgabe und genau
/// das Panel vor dem Baukasten.
public enum UtilitiesPreset: String, CaseIterable, Identifiable, Sendable {
    case standard, minimal, audio, everything

    public var id: Self { self }

    public var title: String {
        switch self {
        case .standard: "Standard"
        case .minimal: "Minimal"
        case .audio: "Ton & Geräte"
        case .everything: "Alles"
        }
    }

    public var summary: String {
        switch self {
        case .standard: "Die Vorgabe: Wach halten, Ton und zehn Schnellschalter."
        case .minimal: "Nur eine Reihe Schnellschalter, keine Karten darüber."
        case .audio: "Ton zuoberst, darunter Mikrofon, Bluetooth und was man beim Hören braucht."
        case .everything: "Alle Karten und jeder feste Knopf einmal, zum Ausprobieren und Aussortieren."
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

// MARK: - Texte und Aussehen der neuen Knoepfe

public enum UtilitiesToggleText {
    public static let cardTitle = String(localized: "Schnellschalter")
    public static let displaySleepSymbol = "moon.zzz.fill"
    public static let hideAppsSymbol = "eye.slash.fill"
}

extension QuickToggles {
    /// `appName`: Name der installierten App; `nil` = nicht installiert.
    /// Ohne gewaehlte oder installierte App nicht klickbar.
    public static func openApp(_ options: UtilitiesAppOptions, appName: String?) -> QuickToggleLook {
        let symbol = options.symbol.trimmed.nonEmpty ?? UtilitiesAppOptions.fallbackSymbol
        guard !options.bundleID.trimmed.isEmpty else {
            return QuickToggleLook(symbol: symbol, active: false, enabled: false, help: String(localized: "Noch keine App gewählt"))
        }
        guard let appName else {
            return QuickToggleLook(symbol: symbol, active: false, enabled: false, help: String(localized: "App nicht installiert"))
        }
        let title = options.title.trimmed.nonEmpty ?? appName
        return QuickToggleLook(symbol: symbol, active: false, enabled: true, help: String(localized: "\(title) öffnen"))
    }

    public static func openLink(_ options: UtilitiesLinkOptions) -> QuickToggleLook {
        let symbol = options.symbol.trimmed.nonEmpty ?? UtilitiesLinkOptions.fallbackSymbol
        guard let url = UtilitiesLink.url(from: options.url) else {
            let help = options.url.trimmed.isEmpty ? String(localized: "Noch kein Link") : String(localized: "Link ungültig")
            return QuickToggleLook(symbol: symbol, active: false, enabled: false, help: help)
        }
        let title = options.title.trimmed.nonEmpty ?? UtilitiesLink.displayText(url)
        return QuickToggleLook(symbol: symbol, active: false, enabled: true, help: String(localized: "\(title) öffnen"))
    }

    public static func runShortcut(_ options: UtilitiesShortcutOptions) -> QuickToggleLook {
        let symbol = options.symbol.trimmed.nonEmpty ?? UtilitiesShortcutOptions.fallbackSymbol
        guard UtilitiesShortcuts.runArguments(options) != nil else {
            return QuickToggleLook(symbol: symbol, active: false, enabled: false, help: String(localized: "Noch kein Kurzbefehl gewählt"))
        }
        let title = options.title.trimmed.nonEmpty ?? options.name.trimmed.nonEmpty ?? String(localized: "Kurzbefehl")
        return QuickToggleLook(symbol: symbol, active: false, enabled: true, help: String(localized: "Kurzbefehl „\(title)“ ausführen"))
    }

    public static let displaySleep = QuickToggleLook(
        symbol: UtilitiesToggleText.displaySleepSymbol, active: false, enabled: true,
        help: String(localized: "Bildschirm ausschalten")
    )

    public static func hideApps(_ options: UtilitiesHideAppsOptions) -> QuickToggleLook {
        QuickToggleLook(symbol: UtilitiesToggleText.hideAppsSymbol, active: false, enabled: true,
                        help: options.keepFrontmost ? String(localized: "Andere Apps ausblenden") : String(localized: "Alle Apps ausblenden"))
    }
}

// MARK: - Links

public enum UtilitiesLink {
    /// Aus dem Eingabefeld eine Adresse:
    /// - mit Schema (https:, mailto:, x-apple.systempreferences: ...) wie
    ///   eingegeben; http(s) braucht einen Host.
    /// - ohne Schema, aber mit Punkt oder "localhost" ("example.com",
    ///   "localhost:8080"): https:// davor - so tippt man Adressen.
    /// - leer, mit Leerzeichen oder sonst nichts Erkennbares: `nil`.
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

    /// Kurz fuer Tooltips: ohne Schema, ohne "www." und ohne Schraegstrich
    /// am Ende ("example.com/docs"). Andere Schemata ganz.
    public static func displayText(_ url: URL) -> String {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host()
        else { return url.absoluteString }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path()
        return path.isEmpty || path == "/" ? host : host + (path.hasSuffix("/") ? String(path.dropLast()) : path)
    }

    /// Schema nach RFC 3986 (Buchstabe, dann Buchstaben, Ziffern, + . -) vor
    /// dem ersten Doppelpunkt - ausser danach kommen nur Ziffern: das ist
    /// "host:port" ohne Schema.
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

// MARK: - Kurzbefehle

/// Ein Eintrag aus `shortcuts list --show-identifiers`.
public struct UtilitiesShortcut: Equatable, Sendable, Identifiable {
    public var name: String
    public var identifier: String

    public var id: String { identifier.isEmpty ? name : identifier }

    public init(name: String, identifier: String) {
        self.name = name
        self.identifier = identifier
    }
}

/// Apples Kurzbefehle ueber das mitgelieferte Werkzeug /usr/bin/shortcuts:
/// oeffentlich, ohne Freigabe-Dialog, und der einzige Weg, z. B. einen
/// Fokus ("Nicht stoeren") zu schalten, ohne private Schnittstellen.
public enum UtilitiesShortcuts {
    public static let tool = "/usr/bin/shortcuts"
    public static let listArguments = ["list", "--show-identifiers"]

    /// Jede Zeile "Name (KENNUNG)" - die Kennung ist eine UUID in Klammern
    /// am Zeilenende (gemessen 14.09., macOS 26.6). Namen duerfen selbst
    /// Klammern enthalten, deshalb von hinten. Zeilen ohne Kennung: nur der
    /// Name. Sortiert nach Namen wie in der Kurzbefehle-App.
    public static func parse(_ output: String) -> [UtilitiesShortcut] {
        output.split(whereSeparator: \.isNewline).compactMap { raw -> UtilitiesShortcut? in
            let line = String(raw).trimmed
            guard !line.isEmpty else { return nil }
            if line.hasSuffix(")"), let open = line.lastIndex(of: "(") {
                let candidate = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
                if UUID(uuidString: candidate) != nil {
                    // Nur eine Kennung ohne Namen: nichts, was man waehlen koennte.
                    let name = String(line[..<open]).trimmed
                    return name.isEmpty ? nil : UtilitiesShortcut(name: name, identifier: candidate)
                }
            }
            return UtilitiesShortcut(name: line, identifier: "")
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Argumente fuer `shortcuts run`: lieber die Kennung (ueberlebt
    /// Umbenennen), sonst der Name. `nil`: nichts gewaehlt.
    public static func runArguments(_ options: UtilitiesShortcutOptions) -> [String]? {
        if let id = options.identifier.trimmed.nonEmpty { return ["run", id] }
        if let name = options.name.trimmed.nonEmpty { return ["run", name] }
        return nil
    }
}

extension ToastText {
    /// `shortcuts run` endete mit Fehler (Kurzbefehl geloescht, abgebrochen).
    public static func shortcutFailed(_ name: String) -> Content {
        Content(title: String(localized: "Kurzbefehl fehlgeschlagen"),
                message: name.trimmed.nonEmpty ?? String(localized: "Unbekannter Kurzbefehl"),
                symbol: UtilitiesShortcutOptions.fallbackSymbol, kind: .warning)
    }
}

// MARK: - Apps ausblenden

public enum UtilitiesHideApps {
    /// Welche App ausgeblendet wird: nur normale Apps (mit Dock-Symbol),
    /// nie die Shell selbst - sonst verschwaenden Leiste und Panels -, und
    /// bei `keepFrontmost` nicht die vordere.
    public static func shouldHide(pid: Int32, isRegular: Bool, ownPID: Int32, frontmostPID: Int32?,
                                  keepFrontmost: Bool) -> Bool {
        guard isRegular, pid != ownPID else { return false }
        return !(keepFrontmost && pid == frontmostPID)
    }
}

// MARK: - Symbole

/// Die kleine Auswahl in Nexus fuer eigene Knoepfe. Jedes davon gibt es auf
/// macOS 26 (Bildprobe prueft es); ein eigener Name geht zusaetzlich.
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

// MARK: - Hilfen

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
