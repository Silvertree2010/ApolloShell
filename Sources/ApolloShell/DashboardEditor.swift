import AppKit
import ApolloShellCore
import Observation

/// An edit of the Dashboard, shared between Nexus (pages, widgets,
/// options) and the Dashboard window (dragging, sizing, dropping). Holds
/// the `BentoEditSession` (core, `ApolloShellCore/BentoEditSession.swift`);
/// every change goes through this class, never straight past `session` -
/// this way both sides see the same working copy.
///
/// `begin` calls `onBegin(screen)` (Dashboard: pin the edge window and
/// open it on that screen), `done`/`cancel` call `onEnd` (Dashboard:
/// unpin).
@MainActor
@Observable
final class DashboardEditor {
    private let store: ShellSettingsStore
    private(set) var session: BentoEditSession?
    var isEditing: Bool { session != nil }
    /// Size of the Dashboard while editing (slider in the toolbar,
    /// `BentoGeometry.userScaleRange`) - a working copy like the pages:
    /// the Dashboard follows it right away, it is only saved with "Done"
    /// (`ShellEditor.done`), "Cancel" discards it. `nil` outside of an
    /// edit.
    var scale: Double? {
        didSet { if scale != oldValue { onScaleChange() } }
    }
    private(set) var originalScale: Double = 1
    /// The Dashboard recomputes its scale (`Dashboard.applyScale`).
    var onScaleChange: () -> Void = {}
    /// Page that was shown when editing ended - the Dashboard stays there
    /// afterwards instead of jumping back to the page from the start.
    private(set) var lastPageID: DashboardPage.ID?

    /// Before `begin`: the page the Dashboard is currently showing -
    /// Nexus starts there.
    var onBegin: (NSScreen) -> Void = { _ in }
    var onEnd: () -> Void = {}
    /// After every `setOptions` - the Dashboard uses this to restart a
    /// widget's weather model when Nexus changes its locations during
    /// editing (otherwise it would keep showing the old ones,
    /// `WeatherModels`).
    var onOptionsChange: (WidgetInstance.ID) -> Void = { _ in }

    /// Preview of a widget dragged from Nexus (`BentoDropDelegate`,
    /// `BentoPageView`) - pure UI display, not part of the session.
    var dropPreview: (frame: WidgetFrame, valid: Bool)?
    /// Kind of the widget currently being dragged, once the payload
    /// string is loaded (`NSItemProvider` only loads asynchronously).
    var draggedKind: WidgetKind?
    /// Counter for drop operations (`BentoDropDelegate`): incremented on
    /// `dropExited`, so a payload string loaded too late (async
    /// `NSItemProvider`) discards the ghost instead of bringing it back
    /// to life after leaving the target.
    var dropGeneration = 0

    /// Page whose name is currently shown as a text field in the bar
    /// (context menu "Rename", task 4) - pure UI display like
    /// `dropPreview`, not part of the session. Kept here instead of as
    /// view-local state, so `ShellEditor.handleEscape` (global Esc, task
    /// 6) can close the text field first, before Esc hits the gallery or
    /// the edit itself.
    var renamingPageID: DashboardPage.ID? {
        didSet {
            if let old = oldValue, old != renamingPageID { finishRename(old) }
            if renamingPageID != nil { onNeedsKeyboard() }
        }
    }
    /// The Dashboard window grabs the keyboard
    /// (`EdgeDrawer.takeKeyboard`) as soon as a page name is being
    /// edited - otherwise the keystrokes would land in the control
    /// center, which last became the key window at launch.
    var onNeedsKeyboard: () -> Void = {}

    /// Empty name after renaming: back to "Page" instead of leaving a
    /// tab without a label.
    private func finishRename(_ id: DashboardPage.ID) {
        guard let page = session?.pages.page(id: id),
              page.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        renamePage(id, to: String(localized: "Page"))
    }

    init(store: ShellSettingsStore) {
        self.store = store
    }

    /// Begins on `pageID` (the page selected in Nexus), on `screen` (the
    /// screen of Nexus' window).
    func begin(pageID: DashboardPage.ID, screen: NSScreen) {
        guard let pages = store.settings.dashboardPages else { return }
        session = BentoEditSession(pages: pages, pageID: pageID)
        originalScale = store.settings.dashboardScale
        scale = originalScale
        dropPreview = nil
        draggedKind = nil
        dropGeneration += 1
        renamingPageID = nil
        optionsWidgetID = nil
        onBegin(screen)
    }

    func done() {
        guard let session else { return }
        lastPageID = session.pageID
        if session.hasChanges { store.settings.dashboardPages = session.pages }
        self.session = nil
        dropPreview = nil
        draggedKind = nil
        dropGeneration += 1
        renamingPageID = nil
        optionsWidgetID = nil
        scale = nil
        onEnd()
    }

    func cancel() {
        guard let current = session else { return }
        lastPageID = current.pageID
        session = nil
        dropPreview = nil
        draggedKind = nil
        dropGeneration += 1
        renamingPageID = nil
        optionsWidgetID = nil
        scale = nil
        onEnd()
    }

    // MARK: - Page

    var pageID: DashboardPage.ID? {
        get { session?.pageID }
        set {
            guard let newValue else { return }
            if newValue != session?.pageID { renamingPageID = nil }
            session?.pageID = newValue
        }
    }

    var page: DashboardPage? { session?.page }

    var selectedWidgetID: WidgetInstance.ID? {
        get { session?.selectedWidgetID }
        set {
            session?.selectedWidgetID = newValue
            if newValue == nil { optionsWidgetID = nil }
        }
    }
    /// Widget whose options popover is open - only after a click, not
    /// after dragging (`EditableWidgetView.showsOptions`). Pure UI
    /// display like `dropPreview`.
    var optionsWidgetID: WidgetInstance.ID?
    #if DEBUG
    /// Self-test: frame of the page in the hosting view (top left,
    /// scaled).
    @ObservationIgnored var debugPageRectInHost: CGRect?
    #endif

    // MARK: - Pages (page sidebar while editing, task 4)

    /// New empty page appended at the end, "Page <n>" (the next free
    /// number, no duplicate if one was renamed that way), shown right
    /// away.
    @discardableResult
    func addPage() -> DashboardPage.ID? {
        guard let session else { return nil }
        let name = Self.nextPageName(existing: session.pages.pages.map(\.name))
        var updated = session
        let id = updated.addPage(name: name)
        self.session = updated
        return id
    }

    static func nextPageName(existing: [String]) -> String {
        var n = existing.count + 1
        while existing.contains(String(localized: "Page \(n)")) { n += 1 }
        return String(localized: "Page \(n)")
    }

    @discardableResult
    func duplicatePage(_ id: DashboardPage.ID) -> DashboardPage.ID? {
        guard let session, let page = session.pages.page(id: id) else { return nil }
        let name = page.name + String(localized: " Copy")
        var updated = session
        let newID = updated.duplicatePage(id, name: name)
        self.session = updated
        return newID
    }

    @discardableResult
    func removePage(_ id: DashboardPage.ID) -> Bool {
        guard var updated = session else { return false }
        let removed = updated.removePage(id)
        session = updated
        return removed
    }

    func renamePage(_ id: DashboardPage.ID, to name: String) {
        guard var updated = session else { return }
        updated.renamePage(id, to: name)
        session = updated
    }

    func setSymbol(_ symbol: String, forPage id: DashboardPage.ID) {
        guard var updated = session else { return }
        updated.setSymbol(symbol, forPage: id)
        session = updated
    }

    /// Whether at least one bundled page is missing - for the menu item
    /// "Restore Default Pages" at the **+** of the page sidebar (disabled
    /// when all four are already present).
    var isMissingDefaultPages: Bool {
        guard let session else { return false }
        let present = Set(session.pages.pages.compactMap(\.template))
        return present.count < PageTemplate.allCases.count
    }

    /// "Restore Default Pages" (task 4/7): appends the bundled pages
    /// whose template is still missing, with the currently saved weather
    /// favorites and battery display - like the migration from before
    /// 0.2, see `DashboardPages.migrated`. Does not change the shown
    /// page.
    func restoreDefaults() {
        guard var updated = session else { return }
        let places = WeatherFavorites.loadLive()
        let defaults = DashboardPages.defaultPages(places: places, hasBattery: PerformanceSampler.hasInternalBattery)
        updated.restoreDefaults(from: defaults)
        session = updated
    }

    // MARK: - Passthrough to the session (views never change `session` themselves)

    func previewMove(_ id: WidgetInstance.ID, proposed: WidgetFrame) -> BentoEditSession.Preview? {
        session?.previewMove(id, proposed: proposed)
    }

    func previewResize(_ id: WidgetInstance.ID, proposedWidth: Double, proposedHeight: Double) -> BentoEditSession.Preview? {
        session?.previewResize(id, proposedWidth: proposedWidth, proposedHeight: proposedHeight)
    }

    func previewDrop(_ kind: WidgetKind, x: Double, y: Double) -> BentoEditSession.Preview? {
        session?.previewDrop(kind, x: x, y: y)
    }

    @discardableResult
    func commit(_ id: WidgetInstance.ID, frame: WidgetFrame) -> Bool {
        session?.commit(id, frame: frame) ?? false
    }

    @discardableResult
    func add(_ kind: WidgetKind, frame: WidgetFrame, places: WeatherFavorites = .empty) -> WidgetInstance.ID? {
        session?.add(kind, frame: frame, places: places)
    }

    /// Gallery click (task 3) instead of dragging: at the first free spot
    /// on the shown page. `nil`: no spot free.
    @discardableResult
    func addAtFirstFreeSpot(_ kind: WidgetKind, places: WeatherFavorites = .empty) -> WidgetInstance.ID? {
        session?.addAtFirstFreeSpot(kind, places: places)
    }

    func remove(_ id: WidgetInstance.ID) {
        session?.remove(id)
    }

    func setOptions(_ options: WidgetOptions, for id: WidgetInstance.ID) {
        session?.setOptions(options, for: id)
        onOptionsChange(id)
    }
}
