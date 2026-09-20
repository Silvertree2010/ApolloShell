import AppKit
import ApolloShellCore
import SwiftUI

/// Dashboard window top center, flush with the top edge (Caelestia:
/// Dashboard at the top edge). Opens via Super+D, via the icon at the
/// top of the bar, and like Caelestia when the mouse hits the top
/// center edge.
///
/// Tabs and cards come from Nexus > Dashboard (settings.dashboard); the
/// view reads them live. The size always stays the same.
@MainActor
final class Dashboard {
    private let model = DashboardModel()
    /// One `WeatherModel` per weather widget: only fetches on open when
    /// the data is older than 15 min, and every 30 min while open.
    private let weatherModels: WeatherModels
    /// Now Playing: the adapter process only runs while open.
    private let media = MediaModel()
    private let settings: ShellSettingsStore
    private let editor: DashboardEditor
    private let drawer: EdgeDrawer<DashboardView>
    /// Size at scale 1 (measured from the content, see `init`).
    private let baseSize: NSSize

    /// `settings`: weather provider (Nexus > Provider), pages and
    /// widgets (Nexus > Dashboard, `settings.dashboardPages`). `editor`:
    /// an edit session, started from Nexus > Dashboard > Edit - the same
    /// object also holds Nexus.
    init(settings: ShellSettingsStore, editor: DashboardEditor) {
        self.settings = settings
        self.editor = editor
        // Migration on the very first access to the pages - before
        // anything that reads them (including the size measurement right
        // below).
        if settings.settings.dashboardPages == nil {
            let places = WeatherFavorites.loadLive()
            settings.settings.dashboardPages = DashboardPages.migrated(
                from: settings.settings.dashboard, places: places, hasBattery: PerformanceSampler.hasInternalBattery
            )
        }
        weatherModels = WeatherModels(settings: settings, editor: editor)
        let view = DashboardView(model: model, weatherModels: weatherModels, media: media, settings: settings, editor: editor)
        // Size from the content (fixed card dimensions) at scale 1,
        // before the first opening. Does not depend on pages and
        // widgets - the grid is always 839 x 392; `prepareForScreen`
        // below scales from here.
        let baseSize = NSHostingView(rootView: view.shellTheme()).fittingSize
        drawer = EdgeDrawer(edge: .top, size: baseSize, cornerRadius: 25, rootView: view)
        drawer.opensOnHover = true
        self.baseSize = baseSize
        drawer.prepareForScreen = { [weak self] screen in
            self?.applyScale(on: screen)
        }
        drawer.onOpen = { [model, weatherModels, media, settings] in
            let page = Dashboard.resolvedPage(model: model, settings: settings)
            model.pageID = page.id
            model.showsPerformance = page.widgets.contains { $0.kind.isPerformance }
            model.start()
            let pages = settings.settings.dashboardPages
            // Without a widget, no fetch and no adapter process.
            if pages?.usesWeather == true { weatherModels.start(for: page.widgets.filter { $0.kind.usesPlaces }) }
            if pages?.usesMedia == true { media.start() }
        }
        drawer.onClose = { [model, weatherModels, media] in
            model.stop()
            weatherModels.stop()
            media.stop()
        }
        // Edit (Nexus > Dashboard > Edit): the window stays open and
        // pinned, regardless of the mouse; weather, media, and
        // performance run for the session's currently shown page as usual.
        editor.onBegin = { [weak drawer, model, weatherModels, media] screen in
            guard let drawer else { return }
            let alreadyOpen = drawer.isOpen
            drawer.isPinned = true
            if let page = editor.page {
                model.pageID = page.id
                model.showsPerformance = page.widgets.contains { $0.kind.isPerformance }
            }
            if alreadyOpen {
                if let page = editor.page {
                    if page.widgets.contains(where: { $0.kind.usesPlaces }) {
                        weatherModels.start(for: page.widgets.filter { $0.kind.usesPlaces })
                    }
                    if page.widgets.contains(where: { $0.kind.usesMedia }) { media.start() }
                }
            } else {
                drawer.open(on: screen)
            }
        }
        editor.onEnd = { [weak self, weak drawer, model, settings, editor] in
            // Scale back to the saved one (after "Done" that is the new
            // one, after "Cancel" the old one).
            self?.applyScaleWhileOpen()
            // Stay on the last edited page (if it no longer exists after
            // "Cancel", `resolvedPage` takes the first one).
            if let id = editor.lastPageID, settings.settings.dashboardPages?.page(id: id) != nil {
                model.pageID = id
            }
            // The places of a weather widget can have been changed during
            // the edit and taken back again by Cancel. The models read
            // them live, but what they fetched last stands on the screen
            // until they are started again (20.09.).
            if drawer?.isOpen == true, let self, let id = model.pageID,
               let page = settings.settings.dashboardPages?.page(id: id) {
                let weather = page.widgets.filter { $0.kind.usesPlaces }
                if !weather.isEmpty { self.weatherModels.start(for: weather) }
            }
            // Unpinning alone - the window stays open until the mouse
            // leaves or a click happens elsewhere, like a normally
            // opened Dashboard.
            drawer?.isPinned = false
        }
        // If Nexus changes the locations of a weather widget during
        // editing, it only shows them after restarting its model
        // (`start()` only re-reads them then).
        editor.onOptionsChange = { [weak weatherModels] id in weatherModels?.restart(id) }
        // Slider in the toolbar: the open Dashboard follows immediately.
        editor.onScaleChange = { [weak self] in self?.applyScaleWhileOpen() }
        editor.onNeedsKeyboard = { [weak drawer] in drawer?.takeKeyboard() }
    }

    /// Scale for this screen: automatic based on width times slider -
    /// during editing the toolbar's slider (`editor.scale`), otherwise
    /// the saved one.
    private func applyScale(on screen: NSScreen) {
        let user = editor.scale ?? settings.settings.dashboardScale
        let scale = BentoGeometry.scale(screenWidth: screen.frame.width, availableHeight: screen.visibleFrame.height,
                                        contentHeight: baseSize.height, contentWidth: baseSize.width, userScale: user)
        model.scale = CGFloat(scale)
        drawer.resize(to: NSSize(width: baseSize.width * CGFloat(scale), height: baseSize.height * CGFloat(scale)))
    }

    private func applyScaleWhileOpen() {
        guard drawer.isOpen, let screen = drawer.currentScreen?.screen else { return }
        applyScale(on: screen)
    }

    /// The page shown when opening: `model.pageID`, if it still exists,
    /// otherwise the first one.
    private static func resolvedPage(model: DashboardModel, settings: ShellSettingsStore) -> DashboardPage {
        let pages = settings.settings.dashboardPages
        return model.pageID.flatMap { pages?.page(id: $0) } ?? pages?.pages.first
            ?? DashboardPages.defaultPages(places: .empty, hasBattery: PerformanceSampler.hasInternalBattery)[0]
    }

    /// Open Nexus at Weather when there is (still) no location - wired
    /// by the caller (see `AppDelegate`).
    func onOpenNexus(_ action: @escaping () -> Void) {
        weatherModels.onOpenNexus = action
    }

    func toggle() {
        drawer.toggle()
    }

    /// Frame of the open Dashboard (edit mode: the gallery sits below
    /// it instead of above).
    var openFrame: NSRect? { drawer.openFrame }
    #if DEBUG
    var debugLevel: Int? { drawer.debugLevel }
    var debugWindow: NSWindow { drawer.debugWindow }
    func debugClose() { drawer.close() }
    var debugScale: CGFloat { model.scale }
    var debugIsOpen: Bool { drawer.isOpen }
    var debugShownPage: DashboardPage.ID? { model.pageID }
    var debugShowsPerformance: Bool { model.showsPerformance }
    func debugDrag(from start: CGPoint, to end: CGPoint) { drawer.debugDrag(from: start, to: end) }
    func debugClick(at point: CGPoint) { drawer.debugClick(at: point) }
    func debugScreenRect(ofHostRect rect: CGRect) -> NSRect? { drawer.debugScreenRect(ofHostRect: rect) }
    #endif

    /// For `ShellEditor.dashboardStartPageID`: the page that is
    /// currently open (or was last) - the global edit mode starts there.
    var currentPageID: DashboardPage.ID? { model.pageID }

    /// Module of the bar (media, weather, CPU, battery): goes straight
    /// to the matching page - or, if there is none anymore, to the
    /// first one with a matching widget, otherwise the very first one.
    /// If it is already open, close it - like a second click on the
    /// Dashboard icon.
    func show(tab: DashboardTab) {
        guard let pages = settings.settings.dashboardPages else { return }
        let kinds: [WidgetKind] = switch tab {
        case .dashboard: []
        case .media: [.mediaPlayer, .media]
        case .performance: [.performanceCPU, .performanceGPU, .performanceStorage, .performanceNetwork,
                            .performanceMemory, .performanceBattery]
        case .weather: [.weatherHero, .weatherHourly, .weatherDaily, .weather]
        }
        // During editing the window stays pinned open - no
        // `drawer.close()`/`open()` (they have no effect anymore anyway,
        // `EdgeDrawer.isPinned`), only the session switches the page,
        // and only if a clear one is found (template or matching
        // widget) - otherwise editing stays where it is.
        if editor.isEditing {
            if let session = editor.session,
               let page = session.pages.pages.first(where: { $0.template == PageTemplate(tab) })
                   ?? session.pages.pages.first(where: { page in kinds.contains(where: page.contains) }) {
                editor.pageID = page.id
            }
            return
        }
        let page = pages.page(for: PageTemplate(tab), showing: kinds)
        if drawer.isOpen, model.pageID == page.id {
            drawer.close()
            return
        }
        model.pageID = page.id
        model.showsPerformance = page.widgets.contains { $0.kind.isPerformance }
        drawer.open()
    }

    /// From `FullscreenMonitor`: these screens are in full screen, so
    /// the mouse at the top opens nothing there. At the edges of the
    /// remaining screens, opening via mouse still works.
    func setFullscreen(_ screens: Set<CGDirectDisplayID>) {
        drawer.suspendedScreens = screens
    }

    /// When the app quits: do not let the adapter's perl process keep
    /// running orphaned if the Dashboard is currently open.
    func shutdown() {
        media.stop()
    }
}
