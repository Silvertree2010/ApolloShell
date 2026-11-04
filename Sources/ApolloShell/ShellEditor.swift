import AppKit
import ApolloShellCore
import Observation

@MainActor
@Observable
final class ShellEditor {
    private let store: ShellSettingsStore
    let dashboard: DashboardEditor

    var isEditing: Bool { dashboard.isEditing }

    var dashboardStartPageID: () -> DashboardPage.ID? = { nil }

    var galleryVisible = false
    var galleryTab: GalleryTab = .dashboard
    var showsAllInGallery = false
    var galleryPanelWidth: CGFloat = galleryWidth

    var galleryNotice: String?
    @ObservationIgnored var galleryNoticeGeneration = 0

    var pendingCancelConfirmation = false

    private var escapeHotKey: GlobalHotKey?

    private var beginHandlers: [(NSScreen) -> Void] = []
    private var endHandlers: [() -> Void] = []

    func addBeginHandler(_ handler: @escaping (NSScreen) -> Void) {
        beginHandlers.append(handler)
    }

    func addEndHandler(_ handler: @escaping () -> Void) {
        endHandlers.append(handler)
    }

    private var endAsCancelObservers: [any NSObjectProtocol] = []

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

    private func observeEndAsCancelEvents() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
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
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            },
        ]
    }

    var hasChanges: Bool {
        (dashboard.session?.hasChanges ?? false) || scaleChanged
    }

    private var scaleChanged: Bool {
        dashboard.scale.map { $0 != dashboard.originalScale } ?? false
    }

    func begin(screen: NSScreen) {
        guard !isEditing, let pages = store.settings.dashboardPages else { return }
        let pageID = dashboardStartPageID() ?? pages.pages[0].id
        galleryVisible = false
        galleryTab = .dashboard
        showsAllInGallery = false
        galleryNotice = nil
        pendingCancelConfirmation = false
        dashboard.begin(pageID: pageID, screen: screen)
        for handler in beginHandlers { handler(screen) }
        registerEscape()
        let current = ShellScreens.current()
        let editScreen = ShellScreens.matching(screen)
        screenSnapshot = ScreenSnapshot(displayIDs: Set(current.map(\.displayID)),
                                        editDisplayID: editScreen?.displayID, editFrame: editScreen?.frame)
    }

    private func handleScreenParametersChanged() {
        guard isEditing, let previous = screenSnapshot else { return }
        let current = ShellScreens.current()
        let ids = Set(current.map(\.displayID))
        let editFrame = previous.editDisplayID.flatMap { id in current.first { $0.displayID == id }?.frame }
        guard ids != previous.displayIDs || editFrame != previous.editFrame else { return }
        cancel()
    }

    func done() {
        guard isEditing else { return }
        dashboard.renamingPageID = nil
        var next = store.settings
        var changed = false
        if let session = dashboard.session, session.hasChanges {
            next.dashboardPages = session.pages
            changed = true
        }
        if scaleChanged, let scale = dashboard.scale {
            next.dashboardScale = BentoGeometry.clampedUserScale(scale)
            changed = true
        }
        if changed { store.settings = next }
        dashboard.cancel()
        pendingCancelConfirmation = false
        screenSnapshot = nil
        unregisterEscape()
        for handler in endHandlers { handler() }
    }

    func cancel() {
        guard isEditing else { return }
        dashboard.cancel()
        pendingCancelConfirmation = false
        screenSnapshot = nil
        unregisterEscape()
        for handler in endHandlers { handler() }
    }

    private func handleEscape() {
        guard isEditing else { return }
        if dashboard.selectedWidgetID != nil {
            dashboard.selectedWidgetID = nil
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


    func confirmCancel() {
        pendingCancelConfirmation = false
        cancel()
    }

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
}
