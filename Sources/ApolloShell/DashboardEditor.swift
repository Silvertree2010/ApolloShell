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
        onBegin(screen)
    }

    func done() {
        guard let session else { return }
        if session.hasChanges { store.settings.dashboardPages = session.pages }
        self.session = nil
        dropPreview = nil
        draggedKind = nil
        dropGeneration += 1
        onEnd()
    }

    func cancel() {
        guard session != nil else { return }
        session = nil
        dropPreview = nil
        draggedKind = nil
        dropGeneration += 1
        onEnd()
    }

    // MARK: - Seite

    var pageID: DashboardPage.ID? {
        get { session?.pageID }
        set {
            guard let newValue else { return }
            session?.pageID = newValue
        }
    }

    var page: DashboardPage? { session?.page }

    var selectedWidgetID: WidgetInstance.ID? {
        get { session?.selectedWidgetID }
        set { session?.selectedWidgetID = newValue }
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

    func remove(_ id: WidgetInstance.ID) {
        session?.remove(id)
    }

    func setOptions(_ options: WidgetOptions, for id: WidgetInstance.ID) {
        session?.setOptions(options, for: id)
    }
}
