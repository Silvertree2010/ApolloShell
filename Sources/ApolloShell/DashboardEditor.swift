import AppKit
import ApolloShellCore
import Observation

/// Eine Bearbeitung des Dashboards, geteilt zwischen Nexus (Seiten, Widgets,
/// Optionen) und dem Dashboard-Fenster (Ziehen, Groesse, Ablegen). Haelt die
/// `BentoEditSession` (Kern, `ApolloShellCore/BentoEditSession.swift`); alle
/// Aenderungen laufen ueber diese Klasse, nie direkt an `session` vorbei -
/// so bekommen beide Seiten dieselbe Arbeitskopie zu sehen.
///
/// `begin` ruft `onBegin(screen)` (Dashboard: Kantenfenster anpinnen und auf
/// diesem Bildschirm oeffnen), `done`/`cancel` rufen `onEnd` (Dashboard:
/// entpinnen).
@MainActor
@Observable
final class DashboardEditor {
    private let store: ShellSettingsStore
    private(set) var session: BentoEditSession?
    var isEditing: Bool { session != nil }

    /// Vor `begin`: die Seite, auf der das Dashboard gerade steht - Nexus
    /// beginnt dort.
    var onBegin: (NSScreen) -> Void = { _ in }
    var onEnd: () -> Void = {}
    /// Nach jeder `setOptions` - Dashboard nutzt es, um das Wetter-Modell
    /// eines Widgets neu zu starten, wenn Nexus waehrend der Bearbeitung
    /// seine Orte aendert (sonst zeigt es die alten weiter, `WeatherModels`).
    var onOptionsChange: (WidgetInstance.ID) -> Void = { _ in }

    /// Vorschau eines aus Nexus gezogenen Widgets (`BentoDropDelegate`,
    /// `BentoPageView`) - reine UI-Anzeige, nicht Teil der Sitzung.
    var dropPreview: (frame: WidgetFrame, valid: Bool)?
    /// Art des gerade gezogenen Widgets, sobald der Nutzlast-String geladen
    /// ist (`NSItemProvider` laedt nur async).
    var draggedKind: WidgetKind?
    /// Zaehler fuer Ablege-Vorgaenge (`BentoDropDelegate`): erhoeht bei
    /// `dropExited`, so verwirft ein verspaetet geladener Nutzlast-String
    /// (async `NSItemProvider`) den Ghost, statt ihn nach dem Verlassen des
    /// Ziels wieder aufleben zu lassen.
    var dropGeneration = 0

    /// Seite, deren Name gerade als Textfeld in der Leiste steht
    /// (Kontextmenue „Umbenennen“, Task 4) - reine UI-Anzeige wie
    /// `dropPreview`, nicht Teil der Sitzung. Hier statt als View-lokaler
    /// Zustand, damit `ShellEditor.handleEscape` (globales Esc, Task 6) das
    /// Textfeld als erstes schliessen kann, bevor Esc die Galerie oder die
    /// Bearbeitung selbst trifft.
    var renamingPageID: DashboardPage.ID?
    /// Seite mit offener Loesch-Rueckfrage (Kontextmenue „Löschen“) - aus
    /// demselben Grund hier statt View-lokal.
    var pendingDeletePageID: DashboardPage.ID?

    init(store: ShellSettingsStore) {
        self.store = store
    }

    /// Beginnt auf `pageID` (die in Nexus gewaehlte Seite), auf `screen`
    /// (der Bildschirm von Nexus' Fenster).
    func begin(pageID: DashboardPage.ID, screen: NSScreen) {
        guard let pages = store.settings.dashboardPages else { return }
        session = BentoEditSession(pages: pages, pageID: pageID)
        dropPreview = nil
        draggedKind = nil
        dropGeneration += 1
        renamingPageID = nil
        pendingDeletePageID = nil
        onBegin(screen)
    }

    func done() {
        guard let session else { return }
        if session.hasChanges { store.settings.dashboardPages = session.pages }
        self.session = nil
        dropPreview = nil
        draggedKind = nil
        dropGeneration += 1
        renamingPageID = nil
        pendingDeletePageID = nil
        onEnd()
    }

    func cancel() {
        guard session != nil else { return }
        session = nil
        dropPreview = nil
        draggedKind = nil
        dropGeneration += 1
        renamingPageID = nil
        pendingDeletePageID = nil
        onEnd()
    }

    // MARK: - Seite

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
        set { session?.selectedWidgetID = newValue }
    }

    // MARK: - Seiten (Seitenleiste beim Bearbeiten, Task 4)

    /// Neue leere Seite ans Ende, "Seite <n>" (die naechste freie Zahl,
    /// keine Dopplung, falls eine so umbenannt wurde), sofort gezeigt.
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
        while existing.contains(String(localized: "Seite \(n)")) { n += 1 }
        return String(localized: "Seite \(n)")
    }

    @discardableResult
    func duplicatePage(_ id: DashboardPage.ID) -> DashboardPage.ID? {
        guard let session, let page = session.pages.page(id: id) else { return nil }
        let name = page.name + String(localized: " Kopie")
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

    // MARK: - Durchreichen an die Sitzung (Views aendern `session` nie selbst)

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

    /// Galerie-Klick (Task 3) statt Ziehen: an der ersten freien Stelle der
    /// gezeigten Seite. `nil`: keine Stelle frei.
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
