import Foundation

/// One editing session of the dashboard (Nexus > Dashboard > Edit): the
/// working copy of all pages, the shown page, the selected widget.
/// "Done" takes `pages` over, "Cancel" discards them (`original`).
/// While dragging, nothing changes - `preview...` only says where it would
/// land and whether it fits there; only `commit`/`add` changes anything.
public struct BentoEditSession: Equatable, Sendable {
    public let original: DashboardPages
    public private(set) var pages: DashboardPages
    /// The shown page. Switching deselects.
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

    /// A new widget with the defaults (weather: the places out of `places`).
    /// Hands back its id and selects it; `nil` when the frame does not fit.
    @discardableResult
    public mutating func add(_ kind: WidgetKind, frame: WidgetFrame, places: WeatherFavorites = .empty) -> WidgetInstance.ID? {
        var page = page
        let widget = WidgetInstance(kind: kind, frame: frame, options: .defaults(for: kind, places: places))
        guard page.add(widget) else { return nil }
        pages.update(page)
        selectedWidgetID = widget.id
        return widget.id
    }

    /// Removes the widget wherever it stands, not only on the shown page:
    /// the minus badge lets its widget fade out for 0.18 s before it calls
    /// here, and a page switch inside that moment used to send the removal
    /// to the new page, where the widget is not - it was silently lost.
    public mutating func remove(_ id: WidgetInstance.ID) {
        guard var target = pages.pages.first(where: { page in page.widgets.contains { $0.id == id } }) else { return }
        target.removeWidget(id: id)
        pages.update(target)
        if selectedWidgetID == id { selectedWidgetID = nil }
    }

    public mutating func setOptions(_ options: WidgetOptions, for id: WidgetInstance.ID) {
        var page = page
        page.setOptions(options, for: id)
        pages.update(page)
    }

    /// A new widget at the first free place of the shown page (a click in the
    /// gallery instead of dragging). `nil`: no free place ("No room on this
    /// page").
    @discardableResult
    public mutating func addAtFirstFreeSpot(_ kind: WidgetKind, places: WeatherFavorites = .empty) -> WidgetInstance.ID? {
        guard let frame = BentoGeometry.firstFreeFrame(kind: kind, others: page.frames()) else { return nil }
        return add(kind, frame: frame, places: places)
    }

    // MARK: Pages

    /// A new empty page at the end, shown right away.
    @discardableResult
    public mutating func addPage(name: String, symbol: String = DashboardPage.defaultSymbol) -> DashboardPage.ID {
        let id = pages.addPage(name: name, symbol: symbol)
        pageID = id
        return id
    }

    /// A copy right behind the original, shown right away. `nil`: no such original.
    @discardableResult
    public mutating func duplicatePage(_ id: DashboardPage.ID, name: String) -> DashboardPage.ID? {
        guard let newID = pages.duplicatePage(id: id, name: name) else { return nil }
        pageID = newID
        return newID
    }

    /// `false` for the last page. When the page that was removed was shown,
    /// its new neighbour is shown (at the same place, otherwise the one before).
    @discardableResult
    public mutating func removePage(_ id: DashboardPage.ID) -> Bool {
        guard let index = pages.pages.firstIndex(where: { $0.id == id }) else { return false }
        let wasShown = pageID == id
        guard pages.removePage(id: id) else { return false }
        if wasShown {
            let neighbourIndex = min(index, pages.pages.count - 1)
            pageID = pages.pages[neighbourIndex].id
        }
        return true
    }

    public mutating func renamePage(_ id: DashboardPage.ID, to name: String) {
        pages.renamePage(id: id, to: name)
    }

    public mutating func setSymbol(_ symbol: String, forPage id: DashboardPage.ID) {
        pages.setSymbol(symbol, forPage: id)
    }

    public mutating func movePages(fromOffsets source: IndexSet, toOffset destination: Int) {
        pages.movePages(fromOffsets: source, toOffset: destination)
    }

    /// “Restore Default Pages” (the sidebar while editing, the menu that ships
    /// with the app at the **+**): appends the pages that ship with the app
    /// whose template is missing - unlike `addPage`/`duplicatePage` this does
    /// not change the shown page, it only adds.
    public mutating func restoreDefaults(from defaults: [DashboardPage]) {
        pages.restoreDefaults(from: defaults)
    }
}
