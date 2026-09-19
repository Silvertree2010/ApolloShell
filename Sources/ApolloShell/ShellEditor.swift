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
/// Kontrollzentrum-Fenster (`UtilitiesPanel`) hoeren ueber
/// `addBeginHandler`/`addEndHandler` mit.
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
    /// Kurzer Hinweis der Galerie (Task 3), z. B. "Kein Platz auf dieser
    /// Seite" - auf `ShellEditor` statt als View-lokaler Zustand, damit
    /// `EditModeWindows` das Panel neu vermisst, sobald der Hinweis
    /// erscheint oder verschwindet (er waechst die Galerie sonst ueber ihren
    /// Rand hinaus).
    var galleryNotice: String?

    /// Rueckfrage vor dem Verwerfen mit ungesicherten Aenderungen (Esc,
    /// Task 6): `true` laesst die Werkzeugleiste eine kleine Nachfrage
    /// zeigen ("Änderungen verwerfen?").
    var pendingCancelConfirmation = false

    /// Esc waehrend der Bearbeitung: eigenes globales Kuerzel (nicht ueber
    /// `HotKeyCenter`, das gehoert den Nutzer-Kuerzeln aus Nexus), nur
    /// registriert, waehrend `isEditing` gilt.
    private var escapeHotKey: GlobalHotKey?

    /// Mehrere Hoerer statt eines einzelnen Abschlusses: Kontrollzentrum,
    /// Scrim/Werkzeugleiste/Galerie und Nexus haengen sich unabhaengig
    /// voneinander ein (`addBeginHandler`/`addEndHandler`), keiner ueberschreibt
    /// den anderen.
    private var beginHandlers: [(NSScreen) -> Void] = []
    private var endHandlers: [() -> Void] = []

    /// Vor `begin`, mit dem Bildschirm, auf dem Nexus stand: die Panels
    /// pinnen sich dort an (Dashboard: schon in `dashboard.onBegin`
    /// verdrahtet; Kontrollzentrum, Scrim, Werkzeugleiste, Galerie hoeren
    /// hier mit).
    func addBeginHandler(_ handler: @escaping (NSScreen) -> Void) {
        beginHandlers.append(handler)
    }

    /// Nach „Fertig“ oder „Abbrechen“: Panels entpinnen, Modus-Fenster
    /// schliessen, Nexus zurueckholen.
    func addEndHandler(_ handler: @escaping () -> Void) {
        endHandlers.append(handler)
    }

    /// Beobachter fuer die Ereignisse, die die Bearbeitung sofort ohne
    /// Rueckfrage beenden (Task 6) - leben so lange wie `ShellEditor` selbst,
    /// wirken aber nur, waehrend `isEditing` gilt.
    private var endAsCancelObservers: [any NSObjectProtocol] = []

    /// Stand der Bildschirme bei `begin`, fuer
    /// `didChangeScreenParametersNotification` (siehe dort): die Meldung
    /// kommt auch, wenn sich gar kein Bildschirm geaendert hat, z. B. beim
    /// Ein-/Ausblenden von Apples Dock (das die Shell selbst versteckt).
    private struct ScreenSnapshot: Equatable {
        let displayIDs: Set<CGDirectDisplayID>
        let editDisplayID: CGDirectDisplayID?
        let editFrame: CGRect?
    }
    private var screenSnapshot: ScreenSnapshot?

    init(store: ShellSettingsStore, dashboard: DashboardEditor) {
        self.store = store
        self.dashboard = dashboard
        observeEndAsCancelEvents()
    }

    /// Ein umgestecker Bildschirm, ein bevorstehender Ruhezustand oder ein
    /// Wechsel der Sitzung (schneller Benutzerwechsel, Bildschirm gesperrt
    /// ueber den Login-Bildschirm) raeumen nicht nach dem Nutzer auf, wenn
    /// sie mitten in der Bearbeitung passieren - die Arbeitskopie verfaellt
    /// ohne Rueckfrage, wie ein Abbrechen. Eine Rueckfrage waere hier ohnehin
    /// oft zu spaet (Deckel zu, Bildschirm weg).
    private func observeEndAsCancelEvents() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        // Drei eigene Abschluesse statt einem geteilten: ein einzeln
        // deklarierter Abschluss gilt fuer den Compiler nicht als
        // `@Sendable`, dreimal derselbe Wert an `using:` (das dort einen
        // `@Sendable`-Abschluss erwartet) waere also eine Warnung wert - so
        // wie an den anderen Beobachtungsstellen der Shell (z. B.
        // `WindowGuard.swift`) direkt am Aufruf.
        endAsCancelObservers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleScreenParametersChanged() }
            },
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            },
            workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            },
        ]
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
        galleryNotice = nil
        pendingCancelConfirmation = false
        // `dashboard.begin` ruft `DashboardEditor.onBegin` (Dashboard-Fenster
        // anpinnen); unser eigenes `onBegin` folgt fuer die uebrigen Panels
        // und Modus-Fenster.
        dashboard.begin(pageID: pageID, screen: screen)
        for handler in beginHandlers { handler(screen) }
        registerEscape()
        let current = ShellScreens.current()
        let editScreen = ShellScreens.matching(screen)
        screenSnapshot = ScreenSnapshot(displayIDs: Set(current.map(\.displayID)),
                                        editDisplayID: editScreen?.displayID, editFrame: editScreen?.frame)
    }

    /// `didChangeScreenParametersNotification` (Task 6) kommt nicht nur bei
    /// einem wirklich umgesteckten oder anders aufgeloesten Bildschirm,
    /// sondern vermutlich auch, wenn Apples Dock oder die Menueleiste ihre
    /// Groesse aendern - und die Shell blendet Apples Dock selbst aus. Ohne
    /// diesen Vergleich haette das die Bearbeitung schon beim Oeffnen der
    /// Galerie (Dock blendet aus) sofort wieder beendet. Nur bei einer
    /// wirklichen Aenderung - andere Menge an Bildschirmen, oder ein anderer
    /// Rahmen des Bearbeitungs-Bildschirms - zaehlt es wie ein Abbrechen.
    private func handleScreenParametersChanged() {
        guard isEditing, let previous = screenSnapshot else { return }
        let current = ShellScreens.current()
        let ids = Set(current.map(\.displayID))
        let editFrame = previous.editDisplayID.flatMap { id in current.first { $0.displayID == id }?.frame }
        guard ids != previous.displayIDs || editFrame != previous.editFrame else { return }
        cancel()
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
        pendingCancelConfirmation = false
        screenSnapshot = nil
        unregisterEscape()
        for handler in endHandlers { handler() }
    }

    /// „Abbrechen“ (Werkzeugleiste, immer sofort - ein Klick ist schon die
    /// Bestaetigung): beide Arbeitskopien verwerfen, ohne Rueckfrage.
    func cancel() {
        guard isEditing else { return }
        dashboard.cancel()
        utilities = nil
        pendingCancelConfirmation = false
        screenSnapshot = nil
        unregisterEscape()
        for handler in endHandlers { handler() }
    }

    // MARK: - Esc (Task 6)

    /// Eigenes globales Kuerzel statt eines lokalen `onExitCommand`
    /// (Kommentar oben bei `escapeHotKey`) - es faengt Esc darum auch dann ab,
    /// wenn gerade ein Seitenname umbenannt wird, ein Optionen-Popover offen
    /// ist, der Kurzbefehl-Picker steht oder eine Loesch-Rueckfrage zeigt.
    /// Ohne diese Prüfungen wuerde Esc dort sofort die Galerie/Bearbeitung
    /// treffen, statt zuerst das innerste dieser Elemente zu schliessen -
    /// deshalb zuerst der Reihe nach das Innerste zu (Kurzbefehl-Picker vor
    /// dem Popover, das ihn zeigt; Umbenennen und Loesch-Rueckfrage
    /// unabhaengig davon), dann die Galerie, erst danach Rueckfrage/Abbruch
    /// der ganzen Bearbeitung. Ein zweites Esc waehrend der
    /// Abbruch-Rueckfrage verwirft nur die Rueckfrage selbst (man kann sich
    /// umentscheiden, ohne gleich die Maus zu bemuehen).
    private func handleEscape() {
        guard isEditing else { return }
        if pickingShortcut {
            pickingShortcut = false
        } else if dashboard.selectedWidgetID != nil {
            dashboard.selectedWidgetID = nil
        } else if selectedToggleID != nil {
            selectedToggleID = nil
        } else if dashboard.renamingPageID != nil {
            dashboard.renamingPageID = nil
        } else if galleryVisible {
            galleryVisible = false
        } else if pendingCancelConfirmation {
            pendingCancelConfirmation = false
        } else if hasChanges {
            pendingCancelConfirmation = true
        } else {
            cancel()
        }
    }

    /// Nachfrage bestaetigt ("Verwerfen"): jetzt wirklich abbrechen.
    func confirmCancel() {
        pendingCancelConfirmation = false
        cancel()
    }

    /// Nachfrage abgelehnt ("Weiter bearbeiten").
    func dismissCancelConfirmation() {
        pendingCancelConfirmation = false
    }

    private func registerEscape() {
        let key = HotKey(keyCode: HotKeyKey.escape)
        if case .success(let hotKey) = GlobalHotKey.register(key, action: { [weak self] in self?.handleEscape() }) {
            escapeHotKey = hotKey
        }
    }

    private func unregisterEscape() {
        escapeHotKey?.unregister()
        escapeHotKey = nil
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

    /// Ob der Kurzbefehl-Picker des gewaehlten Knopfs offen ist (Task 6).
    var pickingShortcut: Bool {
        get { utilities?.pickingShortcut ?? false }
        set { utilities?.pickingShortcut = newValue }
    }
}
