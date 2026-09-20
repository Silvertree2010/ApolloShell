import Foundation

/// The template of a page that ships with the app - the four tabs from before
/// 0.2. Through the template, "Restore Default Pages" and the buttons that
/// open one particular page (media in the bar) find their page. The raw value
/// stands in settings.json - never rename it.
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

/// One page of the dashboard: name, symbol, widgets at free places. Always
/// valid: every widget lies on the page, has an allowed size and keeps
/// `BentoGeometry.spacing` away from the others.
public struct DashboardPage: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    /// A page that ships with the app (`nil` for one's own and for copies).
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

    /// Only valid widgets, in their order; when two are too close the earlier
    /// one wins, and with a duplicate id the same.
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

    /// Adds it when the frame is valid. `false`: nothing changed.
    @discardableResult
    public mutating func add(_ widget: WidgetInstance) -> Bool {
        guard !widgets.contains(where: { $0.id == widget.id }),
              BentoGeometry.isValid(widget.frame, kind: widget.kind, others: frames()) else { return false }
        widgets.append(widget)
        return true
    }

    /// A new frame (dragging, size). Invalid: `false`, the old one stays.
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

    /// A copy with new ids for the page and the widgets, without a template -
    /// otherwise there would be two pages for the same template.
    public func duplicated(name: String) -> DashboardPage {
        DashboardPage(name: name, symbol: symbol,
                      widgets: widgets.map { WidgetInstance(kind: $0.kind, frame: $0.frame, options: $0.options) })
    }

    // MARK: File

    private enum CodingKeys: String, CodingKey { case id, name, symbol, template, widgets }

    /// Lenient: a missing id becomes a new one, an unknown template `nil`, and
    /// unreadable or invalid widgets fall away.
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

/// All pages in their order. Never empty: the last page cannot be deleted, and
/// a file without a readable page counts as unreadable (the app then builds
/// the pages anew, see `DashboardPages.migrated`).
///
/// In the file: `[{"id": ..., "name": ..., "symbol": ..., "template": ..., "widgets": [...]}, ...]`.
public struct DashboardPages: Codable, Equatable, Sendable {
    public private(set) var pages: [DashboardPage]

    /// `nil` for an empty list. Duplicate ids: the later one falls away.
    public init?(pages: [DashboardPage]) {
        var seen = Set<UUID>()
        let unique = pages.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { return nil }
        self.pages = unique
    }

    public init(from decoder: any Decoder) throws {
        let list = try LenientList<DashboardPage>(from: decoder)
        guard let value = DashboardPages(pages: list.values) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no page"))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(pages)
    }

    // MARK: Reading

    public func page(id: DashboardPage.ID) -> DashboardPage? { pages.first { $0.id == id } }

    /// For buttons that used to open a tab (media, performance, weather in the
    /// bar): the page with the template, otherwise the first one with a widget
    /// out of `kinds`, otherwise the first one at all.
    public func page(for template: PageTemplate, showing kinds: [WidgetKind]) -> DashboardPage {
        pages.first { $0.template == template }
            ?? pages.first { page in kinds.contains(where: page.contains) }
            ?? pages[0]
    }

    /// Fetching the weather costs a request, the playback a perl process: only
    /// when a page has such a widget.
    public var usesWeather: Bool { pages.contains { $0.widgets.contains { $0.kind.usesPlaces } } }
    public var usesMedia: Bool { pages.contains { $0.widgets.contains { $0.kind.usesMedia } } }

    // MARK: Changing

    /// Replaces the page with the same id (editing).
    public mutating func update(_ page: DashboardPage) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        pages[index] = page
    }

    /// An empty page at the end.
    @discardableResult
    public mutating func addPage(name: String, symbol: String = DashboardPage.defaultSymbol) -> DashboardPage.ID {
        let page = DashboardPage(name: name, symbol: symbol)
        pages.append(page)
        return page.id
    }

    /// A copy right behind the original. `nil`: no such original.
    @discardableResult
    public mutating func duplicatePage(id: DashboardPage.ID, name: String) -> DashboardPage.ID? {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return nil }
        let copy = pages[index].duplicated(name: name)
        pages.insert(copy, at: index + 1)
        return copy.id
    }

    /// `false` for the last page or an unknown id.
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

    /// Like SwiftUI's `onMove` (the target counted before the move).
    public mutating func movePages(fromOffsets source: IndexSet, toOffset destination: Int) {
        pages.move(fromOffsets: source, toOffset: destination)
    }

    /// Appends the pages that ship with the app whose template is missing.
    /// Existing pages stay as they are. `defaults`: `DashboardPages.defaultPages(...)`.
    public mutating func restoreDefaults(from defaults: [DashboardPage]) {
        let present = Set(pages.compactMap(\.template))
        pages += defaults.filter { page in page.template.map { !present.contains($0) } ?? false }
    }
}
