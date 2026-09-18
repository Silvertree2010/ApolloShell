import Foundation

/// Vorlage einer mitgelieferten Seite - die vier Reiter von vor 0.2. Ueber
/// die Vorlage finden "Standardseiten wiederherstellen" und die Knoepfe,
/// die eine bestimmte Seite oeffnen (Medien in der Leiste), ihre Seite.
/// Rohwert steht in settings.json - nie umbenennen.
public enum PageTemplate: String, Codable, CaseIterable, Sendable {
    case overview, media, performance, weather

    public init(_ tab: DashboardTab) {
        self = switch tab {
        case .dashboard: .overview
        case .media: .media
        case .performance: .performance
        case .weather: .weather
        }
    }

    public var tab: DashboardTab {
        switch self {
        case .overview: .dashboard
        case .media: .media
        case .performance: .performance
        case .weather: .weather
        }
    }
}

/// Eine Seite des Dashboards: Name, Symbol, Widgets an freien Plaetzen.
/// Immer gueltig: jedes Widget liegt auf der Seite, hat eine erlaubte
/// Groesse und haelt `BentoGeometry.spacing` Abstand zu den anderen.
public struct DashboardPage: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    /// Mitgelieferte Seite (`nil` fuer eigene und Kopien).
    public var template: PageTemplate?
    public private(set) var widgets: [WidgetInstance]

    public static let defaultSymbol = "square.grid.2x2"

    public init(id: UUID = UUID(), name: String, symbol: String, template: PageTemplate? = nil,
                widgets: [WidgetInstance] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.template = template
        self.widgets = Self.normalized(widgets)
    }

    /// Nur gueltige Widgets, in ihrer Reihenfolge; bei zu nahen gewinnt das
    /// fruehere, bei doppelter Kennung ebenso.
    static func normalized(_ widgets: [WidgetInstance]) -> [WidgetInstance] {
        var kept: [WidgetInstance] = []
        for widget in widgets where !kept.contains(where: { $0.id == widget.id })
            && BentoGeometry.isValid(widget.frame, kind: widget.kind, others: kept.map(\.frame)) {
            kept.append(widget)
        }
        return kept
    }

    // MARK: Widgets

    public func frames(excluding id: WidgetInstance.ID? = nil) -> [WidgetFrame] {
        widgets.filter { $0.id != id }.map(\.frame)
    }

    public func contains(_ kind: WidgetKind) -> Bool { widgets.contains { $0.kind == kind } }

    /// Fuegt hinzu, wenn der Rahmen gueltig ist. `false`: nichts geaendert.
    @discardableResult
    public mutating func add(_ widget: WidgetInstance) -> Bool {
        guard !widgets.contains(where: { $0.id == widget.id }),
              BentoGeometry.isValid(widget.frame, kind: widget.kind, others: frames()) else { return false }
        widgets.append(widget)
        return true
    }

    /// Neuer Rahmen (Ziehen, Groesse). Ungueltig: `false`, der alte bleibt.
    @discardableResult
    public mutating func setFrame(_ frame: WidgetFrame, for id: WidgetInstance.ID) -> Bool {
        guard let index = widgets.firstIndex(where: { $0.id == id }),
              BentoGeometry.isValid(frame, kind: widgets[index].kind, others: frames(excluding: id))
        else { return false }
        widgets[index].frame = frame
        return true
    }

    public mutating func setOptions(_ options: WidgetOptions, for id: WidgetInstance.ID) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[index].options = options
    }

    public mutating func removeWidget(id: WidgetInstance.ID) {
        widgets.removeAll { $0.id == id }
    }

    /// Kopie mit neuen Kennungen fuer Seite und Widgets, ohne Vorlage - sonst
    /// gaebe es zwei Seiten fuer dieselbe Vorlage.
    public func duplicated(name: String) -> DashboardPage {
        DashboardPage(name: name, symbol: symbol,
                      widgets: widgets.map { WidgetInstance(kind: $0.kind, frame: $0.frame, options: $0.options) })
    }

    // MARK: Datei

    private enum CodingKeys: String, CodingKey { case id, name, symbol, template, widgets }

    /// Nachsichtig: fehlende Kennung wird neu, unbekannte Vorlage `nil`,
    /// unlesbare oder ungueltige Widgets fallen weg.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list: LenientList<WidgetInstance>? = c.lenient(.widgets)
        self.init(id: c.lenient(.id) ?? UUID(),
                  name: c.lenient(.name) ?? "",
                  symbol: c.lenient(.symbol) ?? Self.defaultSymbol,
                  template: c.lenient(.template),
                  widgets: list?.values ?? [])
    }
}

/// Alle Seiten in ihrer Reihenfolge. Nie leer: die letzte Seite laesst sich
/// nicht loeschen, und eine Datei ohne lesbare Seite gilt als nicht lesbar
/// (die App baut die Seiten dann neu, siehe `DashboardPages.migrated`).
///
/// In der Datei: `[{"id": ..., "name": ..., "symbol": ..., "template": ..., "widgets": [...]}, ...]`.
public struct DashboardPages: Codable, Equatable, Sendable {
    public private(set) var pages: [DashboardPage]

    /// `nil` fuer eine leere Liste. Doppelte Kennungen: die spaetere faellt weg.
    public init?(pages: [DashboardPage]) {
        var seen = Set<UUID>()
        let unique = pages.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { return nil }
        self.pages = unique
    }

    public init(from decoder: any Decoder) throws {
        let list = try LenientList<DashboardPage>(from: decoder)
        guard let value = DashboardPages(pages: list.values) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "keine Seite"))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(pages)
    }

    // MARK: Lesen

    public func page(id: DashboardPage.ID) -> DashboardPage? { pages.first { $0.id == id } }

    /// Fuer Knoepfe, die frueher einen Reiter oeffneten (Medien, Leistung,
    /// Wetter in der Leiste): die Seite mit der Vorlage, sonst die erste mit
    /// einem Widget aus `kinds`, sonst die erste ueberhaupt.
    public func page(for template: PageTemplate, showing kinds: [WidgetKind]) -> DashboardPage {
        pages.first { $0.template == template }
            ?? pages.first { page in kinds.contains(where: page.contains) }
            ?? pages[0]
    }

    /// Wetter abrufen kostet eine Anfrage, die Wiedergabe einen perl-Prozess:
    /// nur, wenn eine Seite ein solches Widget hat.
    public var usesWeather: Bool { pages.contains { $0.widgets.contains { $0.kind.usesPlaces } } }
    public var usesMedia: Bool { pages.contains { $0.widgets.contains { $0.kind.usesMedia } } }

    // MARK: Aendern

    /// Ersetzt die Seite mit derselben Kennung (Bearbeiten).
    public mutating func update(_ page: DashboardPage) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        pages[index] = page
    }

    /// Leere Seite ans Ende.
    @discardableResult
    public mutating func addPage(name: String, symbol: String = DashboardPage.defaultSymbol) -> DashboardPage.ID {
        let page = DashboardPage(name: name, symbol: symbol)
        pages.append(page)
        return page.id
    }

    /// Kopie direkt hinter das Original. `nil`: kein solches Original.
    @discardableResult
    public mutating func duplicatePage(id: DashboardPage.ID, name: String) -> DashboardPage.ID? {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return nil }
        let copy = pages[index].duplicated(name: name)
        pages.insert(copy, at: index + 1)
        return copy.id
    }

    /// `false` fuer die letzte Seite oder eine unbekannte Kennung.
    @discardableResult
    public mutating func removePage(id: DashboardPage.ID) -> Bool {
        guard pages.count > 1, let index = pages.firstIndex(where: { $0.id == id }) else { return false }
        pages.remove(at: index)
        return true
    }

    public mutating func renamePage(id: DashboardPage.ID, to name: String) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].name = name
    }

    public mutating func setSymbol(_ symbol: String, forPage id: DashboardPage.ID) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].symbol = symbol
    }

    /// Wie SwiftUIs `onMove` (Ziel vor dem Verschieben gezaehlt).
    public mutating func movePages(fromOffsets source: IndexSet, toOffset destination: Int) {
        pages.move(fromOffsets: source, toOffset: destination)
    }

    /// Haengt die mitgelieferten Seiten an, deren Vorlage fehlt. Vorhandene
    /// Seiten bleiben, wie sie sind. `defaults`: `DashboardPages.defaultPages(...)`.
    public mutating func restoreDefaults(from defaults: [DashboardPage]) {
        let present = Set(pages.compactMap(\.template))
        pages += defaults.filter { page in page.template.map { !present.contains($0) } ?? false }
    }
}
