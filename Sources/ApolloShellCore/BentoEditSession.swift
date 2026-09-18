import Foundation

/// Eine Bearbeitung des Dashboards (Nexus > Dashboard > Bearbeiten): die
/// Arbeitskopie aller Seiten, die gezeigte Seite, das gewaehlte Widget.
/// "Fertig" uebernimmt `pages`, "Abbrechen" verwirft sie (`original`).
/// Waehrend gezogen wird, aendert sich nichts - `preview...` sagt nur, wo
/// es landen wuerde und ob es dort passt; erst `commit`/`add` aendert.
public struct BentoEditSession: Equatable, Sendable {
    public let original: DashboardPages
    public private(set) var pages: DashboardPages
    /// Gezeigte Seite. Wechsel waehlt ab.
    public var pageID: DashboardPage.ID {
        didSet { if pageID != oldValue { selectedWidgetID = nil } }
    }
    public var selectedWidgetID: WidgetInstance.ID?

    public init(pages: DashboardPages, pageID: DashboardPage.ID) {
        original = pages
        self.pages = pages
        self.pageID = pages.page(id: pageID)?.id ?? pages.pages[0].id
    }

    public var page: DashboardPage { pages.page(id: pageID) ?? pages.pages[0] }
    public var hasChanges: Bool { pages != original }

    public struct Preview: Equatable, Sendable {
        public var frame: WidgetFrame
        public var valid: Bool
    }

    public func previewMove(_ id: WidgetInstance.ID, proposed: WidgetFrame) -> Preview {
        guard let widget = page.widgets.first(where: { $0.id == id }) else { return Preview(frame: proposed, valid: false) }
        let others = page.frames(excluding: id)
        let frame = BentoGeometry.snapMove(proposed, others: others)
        return Preview(frame: frame, valid: BentoGeometry.isValid(frame, kind: widget.kind, others: others))
    }

    public func previewResize(_ id: WidgetInstance.ID, proposedWidth: Double, proposedHeight: Double) -> Preview {
        guard let widget = page.widgets.first(where: { $0.id == id }) else {
            return Preview(frame: WidgetFrame(x: 0, y: 0, width: proposedWidth, height: proposedHeight), valid: false)
        }
        let others = page.frames(excluding: id)
        let frame = BentoGeometry.snapResize(widget.frame, kind: widget.kind, proposedWidth: proposedWidth,
                                             proposedHeight: proposedHeight, others: others)
        return Preview(frame: frame, valid: BentoGeometry.isValid(frame, kind: widget.kind, others: others))
    }

    public func previewDrop(_ kind: WidgetKind, x: Double, y: Double) -> Preview {
        let others = page.frames()
        let frame = BentoGeometry.dropFrame(kind: kind, x: x, y: y, others: others)
        return Preview(frame: frame, valid: BentoGeometry.isValid(frame, kind: kind, others: others))
    }

    @discardableResult
    public mutating func commit(_ id: WidgetInstance.ID, frame: WidgetFrame) -> Bool {
        var page = page
        guard page.setFrame(frame, for: id) else { return false }
        pages.update(page)
        return true
    }

    /// Neues Widget mit Vorgaben (Wetter: die Orte aus `places`). Liefert
    /// seine Kennung und waehlt es aus; `nil`, wenn der Rahmen nicht passt.
    @discardableResult
    public mutating func add(_ kind: WidgetKind, frame: WidgetFrame, places: WeatherFavorites = .empty) -> WidgetInstance.ID? {
        var page = page
        let widget = WidgetInstance(kind: kind, frame: frame, options: .defaults(for: kind, places: places))
        guard page.add(widget) else { return nil }
        pages.update(page)
        selectedWidgetID = widget.id
        return widget.id
    }

    public mutating func remove(_ id: WidgetInstance.ID) {
        var page = page
        page.removeWidget(id: id)
        pages.update(page)
        if selectedWidgetID == id { selectedWidgetID = nil }
    }

    public mutating func setOptions(_ options: WidgetOptions, for id: WidgetInstance.ID) {
        var page = page
        page.setOptions(options, for: id)
        pages.update(page)
    }
}
