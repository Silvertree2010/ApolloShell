import AppKit
import ApolloShellCore
import Observation

/// Der eine Bearbeitungsmodus der ganzen Shell (Spec Abschnitt 4, revidiert
/// 2026-09-19): ein Knopf in Nexus startet ihn, Scrim und Fenster liegen ueber
/// allen Bildschirmen, Dashboard und Kontrollzentrum bleiben auf dem
/// Bildschirm, auf dem Nexus stand, offen und angepinnt. „Fertig“ schreibt
/// beide Arbeitskopien in einer Zuweisung von `store.settings`, „Abbrechen“
/// verwirft beide.
///
/// Haelt `dashboard` (die bestehende `DashboardEditor`, die weiterhin das
/// Anpinnen des Dashboard-Kantenfensters uebernimmt) und `utilities` (eine
/// `UtilitiesEditSession`, neu je Bearbeitung). Die Fenster der Bearbeitung
/// selbst (Scrim, Werkzeugleiste, Galerie: `EditModeWindows.swift`) und das
/// Kontrollzentrum-Fenster (`UtilitiesPanel`) hoeren auf `onBegin`/`onEnd`.
@MainActor
@Observable
final class ShellEditor {
    private let store: ShellSettingsStore
    let dashboard: DashboardEditor
    private(set) var utilities: UtilitiesEditSession?

    var isEditing: Bool { dashboard.isEditing }

    /// Welche Seite das Dashboard beim Start zeigen soll - vom Dashboard-
    /// Fenster gesetzt (die gerade offene Seite, oder `nil` vor dem ersten
    /// Oeffnen: dann die erste Seite).
    var dashboardStartPageID: () -> DashboardPage.ID? = { nil }

    /// Galerie (Task 3): offen/zu, gewaehlter Reiter, "alle zeigen".
    var galleryVisible = false
    var galleryTab: WidgetSurface = .dashboard
    var showsAllInGallery = false

    /// Vor `begin`, mit dem Bildschirm, auf dem Nexus stand: die Panels
    /// pinnen sich dort an (Dashboard: schon in `dashboard.onBegin`
    /// verdrahtet; Kontrollzentrum, Scrim, Werkzeugleiste, Galerie hoeren
    /// hier mit).
    var onBegin: (NSScreen) -> Void = { _ in }
    /// Nach „Fertig“ oder „Abbrechen“: Panels entpinnen, Modus-Fenster
    /// schliessen, Nexus zurueckholen.
    var onEnd: () -> Void = {}

    init(store: ShellSettingsStore, dashboard: DashboardEditor) {
        self.store = store
        self.dashboard = dashboard
    }

    var hasChanges: Bool {
        (dashboard.session?.hasChanges ?? false) || (utilities?.hasChanges ?? false)
    }

    func begin(screen: NSScreen) {
        guard !isEditing, let pages = store.settings.dashboardPages else { return }
        let pageID = dashboardStartPageID() ?? pages.pages[0].id
        utilities = UtilitiesEditSession(layout: store.settings.utilities.layout)
        galleryVisible = false
        galleryTab = .dashboard
        showsAllInGallery = false
        // `dashboard.begin` ruft `DashboardEditor.onBegin` (Dashboard-Fenster
        // anpinnen); unser eigenes `onBegin` folgt fuer die uebrigen Panels
        // und Modus-Fenster.
        dashboard.begin(pageID: pageID, screen: screen)
        onBegin(screen)
    }

    /// „Fertig“: beide Arbeitskopien in einer Zuweisung von `store.settings`
    /// uebernehmen - so entsteht kein Zwischenstand, in dem nur die eine
    /// geschrieben ist (Absturz mitten drin liesse die Einstellungen sonst
    /// halb bearbeitet zurueck).
    func done() {
        guard isEditing else { return }
        var next = store.settings
        var changed = false
        if let session = dashboard.session, session.hasChanges {
            next.dashboardPages = session.pages
            changed = true
        }
        if let utilities, utilities.hasChanges {
            next.utilities.layout = utilities.layout
            changed = true
        }
        if changed { store.settings = next }
        // Die Aenderung ist schon uebernommen - `dashboard.cancel()` wirft nur
        // die Arbeitskopie weg und ruft `DashboardEditor.onEnd` (entpinnen),
        // ohne selbst nochmal zu schreiben.
        dashboard.cancel()
        utilities = nil
        onEnd()
    }

    /// „Abbrechen“ bzw. Esc: beide Arbeitskopien verwerfen. `confirmIfChanged`
    /// ist Sache des Aufrufers (Werkzeugleiste/Esc, Task 6) - hier immer ohne
    /// Rueckfrage.
    func cancel() {
        guard isEditing else { return }
        dashboard.cancel()
        utilities = nil
        onEnd()
    }

    // MARK: - Kontrollzentrum: Durchreichen an die Sitzung

    func setCard(_ kind: UtilitiesCardKind, enabled: Bool) {
        utilities?.setCard(kind, enabled: enabled)
    }

    func moveUtilitiesCards(fromOffsets source: IndexSet, toOffset destination: Int) {
        utilities?.moveCards(fromOffsets: source, toOffset: destination)
    }

    @discardableResult
    func addToggle(_ kind: UtilitiesToggleKind) -> String? {
        utilities?.add(kind)
    }

    func removeToggle(_ id: String) {
        utilities?.remove(toggle: id)
    }

    func updateToggle(_ id: String, to toggle: UtilitiesToggle) {
        utilities?.update(toggle: id, to: toggle)
    }

    func moveToggle(_ id: String, onto target: String) {
        utilities?.moveToggle(id, onto: target)
    }

    var selectedToggleID: String? {
        get { utilities?.selectedToggleID }
        set { utilities?.selectedToggleID = newValue }
    }
}
