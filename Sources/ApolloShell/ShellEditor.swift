import AppKit
import ApolloShellCore
import Observation

/// The one edit mode of the whole shell (spec section 4, revised
/// 2026-09-19): a button in Nexus starts it, scrim and windows lie over
/// all screens, Dashboard and Control Centre stay open and pinned on the
/// screen where Nexus was. "Done" writes both working copies in a single
/// assignment of `store.settings`, "Cancel" discards both.
///
/// Holds `dashboard` (the existing `DashboardEditor`, which continues to
/// handle pinning the Dashboard edge window) and `utilities` (a
/// `UtilitiesEditSession`, new for each edit). The edit mode's own
/// windows (scrim, toolbar, gallery: `EditModeWindows.swift`) and the
/// Control Centre window (`UtilitiesPanel`) listen in via
/// `addBeginHandler`/`addEndHandler`.
@MainActor
@Observable
final class ShellEditor {
    private let store: ShellSettingsStore
    let dashboard: DashboardEditor
    private(set) var utilities: UtilitiesEditSession?
    /// The sidebar's working copy; `nil` while the mode is not running.
    private(set) var bar: BarEditSession?

    var isEditing: Bool { dashboard.isEditing }

    /// Which page the Dashboard should show at start - set by the
    /// Dashboard window (the currently open page, or `nil` before the
    /// first opening: then the first page).
    var dashboardStartPageID: () -> DashboardPage.ID? = { nil }

    /// Gallery (Task 3): open/closed, selected tab, "show all".
    var galleryVisible = false
    var galleryTab: GalleryTab = .dashboard
    var showsAllInGallery = false
    /// Brief notice from the gallery (Task 3), e.g. "No room on this
    /// page" - kept on `ShellEditor` instead of as view-local state, so
    /// `EditModeWindows` re-measures the panel as soon as the notice
    /// appears or disappears (otherwise the gallery grows past its own edge).
    var galleryNotice: String?
    /// Counted up with every notice: the timer that clears one after 1.6 s
    /// only clears its own. Two notices in quick succession (two clicks on
    /// full tiles) used to leave the first timer wiping the second one
    /// away early.
    @ObservationIgnored var galleryNoticeGeneration = 0

    /// Confirmation before discarding unsaved changes (Esc, Task 6):
    /// `true` lets the toolbar show a small prompt ("Discard changes?").
    var pendingCancelConfirmation = false

    /// Esc during editing: its own global shortcut (not via
    /// `HotKeyCenter`, which belongs to the user shortcuts from Nexus),
    /// registered only while `isEditing` holds.
    private var escapeHotKey: GlobalHotKey?

    /// Multiple listeners instead of a single completion: Control
    /// Centre, scrim/toolbar/gallery, and Nexus each hook in
    /// independently (`addBeginHandler`/`addEndHandler`), none overwrites
    /// the other.
    private var beginHandlers: [(NSScreen) -> Void] = []
    private var endHandlers: [() -> Void] = []

    /// Before `begin`, with the screen Nexus was on: the panels pin
    /// themselves there (Dashboard: already wired in `dashboard.onBegin`;
    /// Control Centre, scrim, toolbar, gallery listen in here).
    func addBeginHandler(_ handler: @escaping (NSScreen) -> Void) {
        beginHandlers.append(handler)
    }

    /// After "Done" or "Cancel": unpin panels, close mode windows,
    /// bring Nexus back.
    func addEndHandler(_ handler: @escaping () -> Void) {
        endHandlers.append(handler)
    }

    /// Observers for the events that end editing immediately without
    /// confirmation (Task 6) - live as long as `ShellEditor` itself, but
    /// only take effect while `isEditing` holds.
    private var endAsCancelObservers: [any NSObjectProtocol] = []

    /// State of the screens at `begin`, for
    /// `didChangeScreenParametersNotification` (see there): the
    /// notification also arrives when no screen actually changed, e.g.
    /// when Apple's Dock shows or hides (which the shell itself hides).
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

    /// A reconnected screen, an upcoming sleep, or a session switch
    /// (fast user switching, screen locked via the login screen) do not
    /// clean up after the user if they happen mid-edit - the working
    /// copy decays without confirmation, like a cancel. A confirmation
    /// would often be too late here anyway (lid closed, screen gone).
    private func observeEndAsCancelEvents() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        // Three separate closures instead of a shared one: an
        // individually declared closure does not count as `@Sendable`
        // for the compiler, so passing the same value three times to
        // `using:` (which expects a `@Sendable` closure there) would be
        // worth a warning - just like at the shell's other observation
        // sites (e.g. `WindowGuard.swift`), directly at the call site.
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
            || (bar?.hasChanges ?? false) || scaleChanged
    }

    private var scaleChanged: Bool {
        dashboard.scale.map { $0 != dashboard.originalScale } ?? false
    }

    func begin(screen: NSScreen) {
        guard !isEditing, let pages = store.settings.dashboardPages else { return }
        let pageID = dashboardStartPageID() ?? pages.pages[0].id
        utilities = UtilitiesEditSession(layout: store.settings.utilities.layout)
        bar = BarEditSession(layout: store.settings.bar.layout)
        galleryVisible = false
        galleryTab = .dashboard
        showsAllInGallery = false
        galleryNotice = nil
        pendingCancelConfirmation = false
        // `dashboard.begin` calls `DashboardEditor.onBegin` (pinning the
        // Dashboard window); our own `onBegin` follows for the remaining
        // panels and mode windows.
        dashboard.onSelectWidget = { [weak self] in
            self?.utilities?.selectedToggleID = nil
            self?.bar?.selectedEntryID = nil
        }
        dashboard.begin(pageID: pageID, screen: screen)
        for handler in beginHandlers { handler(screen) }
        registerEscape()
        let current = ShellScreens.current()
        let editScreen = ShellScreens.matching(screen)
        screenSnapshot = ScreenSnapshot(displayIDs: Set(current.map(\.displayID)),
                                        editDisplayID: editScreen?.displayID, editFrame: editScreen?.frame)
    }

    /// `didChangeScreenParametersNotification` (Task 6) arrives not only
    /// for an actually reconnected or differently resolved screen, but
    /// presumably also when Apple's Dock or the menu bar change size -
    /// and the shell hides Apple's Dock itself. Without this comparison
    /// that would immediately end editing again as soon as the gallery
    /// opens (Dock hides). Only on a real change - a different number of
    /// screens, or a different frame of the editing screen - does it
    /// count as a cancel.
    private func handleScreenParametersChanged() {
        guard isEditing, let previous = screenSnapshot else { return }
        let current = ShellScreens.current()
        let ids = Set(current.map(\.displayID))
        let editFrame = previous.editDisplayID.flatMap { id in current.first { $0.displayID == id }?.frame }
        guard ids != previous.displayIDs || editFrame != previous.editFrame else { return }
        cancel()
    }

    /// "Done": apply both working copies in a single assignment of
    /// `store.settings` - this way there is no intermediate state where
    /// only one is written (a crash mid-way would otherwise leave the
    /// settings half-edited).
    func done() {
        guard isEditing else { return }
        // A name field still open counts as finished, before anything is
        // written: `renamingPageID` puts an empty name back to "Page" on
        // its way to `nil`, and only while the session still stands
        // (20.09.: Done while renaming saved a page without a name).
        dashboard.renamingPageID = nil
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
        if let bar, bar.hasChanges {
            next.bar.layout = bar.layout
            changed = true
        }
        if scaleChanged, let scale = dashboard.scale {
            next.dashboardScale = BentoGeometry.clampedUserScale(scale)
            changed = true
        }
        if changed { store.settings = next }
        // The change is already applied - `dashboard.cancel()` only
        // discards the working copy and calls `DashboardEditor.onEnd`
        // (unpinning), without writing anything again itself.
        dashboard.cancel()
        utilities = nil
        bar = nil
        pendingCancelConfirmation = false
        screenSnapshot = nil
        unregisterEscape()
        for handler in endHandlers { handler() }
    }

    /// "Cancel" (toolbar, always immediate - a click is already the
    /// confirmation): discard both working copies, without confirmation.
    func cancel() {
        guard isEditing else { return }
        dashboard.cancel()
        utilities = nil
        bar = nil
        pendingCancelConfirmation = false
        screenSnapshot = nil
        unregisterEscape()
        for handler in endHandlers { handler() }
    }

    // MARK: - Esc (Task 6)

    /// Its own global shortcut instead of a local `onExitCommand`
    /// (comment above at `escapeHotKey`) - this way it catches Esc even
    /// while a page name is being renamed, an options popover is open,
    /// the shortcut picker is showing, or a delete confirmation is
    /// shown. Without these checks, Esc would immediately hit the
    /// gallery/editing there instead of first closing the innermost of
    /// these elements - hence closing the innermost one first, in order
    /// (shortcut picker before the popover that shows it; renaming and
    /// delete confirmation independently of that), then the gallery,
    /// only after that the confirmation/cancel of the whole edit. A
    /// second Esc during the cancel confirmation only dismisses the
    /// confirmation itself (you can change your mind without reaching
    /// for the mouse).
    private func handleEscape() {
        guard isEditing else { return }
        if pickingShortcut {
            pickingShortcut = false
        } else if dashboard.selectedWidgetID != nil {
            dashboard.selectedWidgetID = nil
        } else if selectedToggleID != nil {
            selectedToggleID = nil
        } else if selectedBarEntryID != nil {
            selectedBarEntryID = nil
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

    #if DEBUG
    /// Self-test: Esc without the system-wide shortcut.
    func debugEscape() { handleEscape() }
    /// Self-test: frame of the Control Centre's tiles and cards
    /// (reference space `UtilitiesPanelView.rootSpace`).
    @ObservationIgnored var debugUtilitiesRects: [String: CGRect] = [:]
    #endif

    /// Confirmation confirmed ("Discard"): now actually cancel.
    func confirmCancel() {
        pendingCancelConfirmation = false
        cancel()
    }

    /// Confirmation declined ("Keep Editing").
    func dismissCancelConfirmation() {
        pendingCancelConfirmation = false
    }

    private func registerEscape() {
        #if DEBUG
        // Self-test: do not claim Esc system-wide, alongside the real shell.
        if EditModeSelfTest.invisible { return }
        #endif
        let key = HotKey(keyCode: HotKeyKey.escape)
        if case .success(let hotKey) = GlobalHotKey.register(key, action: { [weak self] in self?.handleEscape() }) {
            escapeHotKey = hotKey
        }
    }

    private func unregisterEscape() {
        escapeHotKey?.unregister()
        escapeHotKey = nil
    }

    // MARK: - Control Centre: passing through to the session

    func setCard(_ kind: UtilitiesCardKind, enabled: Bool) {
        utilities?.setCard(kind, enabled: enabled)
    }

    func moveUtilitiesCards(fromOffsets source: IndexSet, toOffset destination: Int) {
        utilities?.moveCards(fromOffsets: source, toOffset: destination)
    }

    /// The sessions select what they add themselves, on the struct, past
    /// the setters below - so the rule that only one thing in the shell is
    /// selected is kept here, at the three places that add.
    @discardableResult
    func addToggle(_ kind: UtilitiesToggleKind) -> String? {
        guard let id = utilities?.add(kind) else { return nil }
        bar?.selectedEntryID = nil
        dashboard.selectedWidgetID = nil
        return id
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

    /// Selecting in one surface lets the other two go: only one thing in
    /// the shell is selected at a time, and only one options popover
    /// stands open.
    var selectedToggleID: String? {
        get { utilities?.selectedToggleID }
        set {
            utilities?.selectedToggleID = newValue
            if newValue != nil {
                bar?.selectedEntryID = nil
                dashboard.selectedWidgetID = nil
            }
        }
    }

    // MARK: - Sidebar: passing through to the session

    @discardableResult
    func addBarModule(_ kind: BarModuleKind, at index: Int? = nil) -> String? {
        guard let id = bar?.add(kind, at: index) else { return nil }
        utilities?.selectedToggleID = nil
        dashboard.selectedWidgetID = nil
        return id
    }

    func removeBarModule(_ id: String) {
        bar?.remove(id: id)
    }

    func updateBarModule(_ id: String, to module: BarModule) {
        bar?.update(id: id, to: module)
    }

    func moveBarModule(_ id: String, by step: Int) {
        bar?.move(id: id, by: step)
    }

    func moveBarModule(_ id: String, onto target: String) {
        bar?.move(id: id, onto: target)
    }

    var selectedBarEntryID: String? {
        get { bar?.selectedEntryID }
        set {
            bar?.selectedEntryID = newValue
            if newValue != nil {
                utilities?.selectedToggleID = nil
                dashboard.selectedWidgetID = nil
            }
        }
    }

    /// Whether the shortcut picker of the selected button is open (Task 6).
    var pickingShortcut: Bool {
        get { utilities?.pickingShortcut ?? false }
        set { utilities?.pickingShortcut = newValue }
    }
}
