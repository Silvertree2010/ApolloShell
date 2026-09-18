import AppKit
import ApolloShellCore
import SwiftUI

/// Dashboard-Fenster oben mittig, buendig an der Oberkante (Caelestia:
/// Dashboard am oberen Rand). Oeffnet per SUPER+D, ueber das Symbol oben in
/// der Leiste und wie bei Caelestia, wenn die Maus oben mittig an den Rand
/// stoesst.
///
/// Reiter und Karten kommen aus Nexus > Dashboard (settings.dashboard); die
/// Ansicht liest sie live. Die Groesse bleibt dabei immer dieselbe.
@MainActor
final class Dashboard {
    private let model = DashboardModel()
    /// Ein `WeatherModel` je Wetter-Widget: laedt nur beim Oeffnen, wenn die
    /// Daten aelter als 15 min sind, und alle 30 min, solange offen.
    private let weatherModels: WeatherModels
    /// Now Playing: der Adapter-Prozess laeuft nur, solange offen.
    private let media = MediaModel()
    private let settings: ShellSettingsStore
    private let editor: DashboardEditor
    private let drawer: EdgeDrawer<DashboardView>

    /// `settings`: Wetteranbieter (Nexus > Anbieter), Seiten und Widgets
    /// (Nexus > Dashboard, `settings.dashboardPages`). `editor`: eine
    /// Bearbeitung, gestartet aus Nexus > Dashboard > Bearbeiten - dasselbe
    /// Objekt haelt auch Nexus.
    init(settings: ShellSettingsStore, editor: DashboardEditor) {
        self.settings = settings
        self.editor = editor
        // Umzug beim allerersten Zugriff auf die Seiten - vor allem, was sie
        // liest (Groessenmessung gleich darunter eingeschlossen).
        if settings.settings.dashboardPages == nil {
            let places = WeatherFavorites.load(from: try? Data(contentsOf: ShellFiles.live.weather))
            settings.settings.dashboardPages = DashboardPages.migrated(
                from: settings.settings.dashboard, places: places, hasBattery: PerformanceSampler.hasInternalBattery
            )
        }
        weatherModels = WeatherModels(settings: settings)
        let view = DashboardView(model: model, weatherModels: weatherModels, media: media, settings: settings, editor: editor)
        // Groesse aus dem Inhalt (feste Karten-Masse) bei Massstab 1, vor dem
        // ersten Oeffnen. Haengt nicht an Seiten und Widgets - das Raster ist
        // immer 839 x 392; `prepareForScreen` unten skaliert von hier aus.
        let baseSize = NSHostingView(rootView: view.shellTheme()).fittingSize
        drawer = EdgeDrawer(edge: .top, size: baseSize, cornerRadius: 25, rootView: view)
        drawer.opensOnHover = true
        drawer.prepareForScreen = { [model, settings, weak drawer] screen in
            let scale = BentoGeometry.scale(screenWidth: screen.frame.width, availableHeight: screen.visibleFrame.height,
                                            contentHeight: baseSize.height, userScale: settings.settings.dashboardScale)
            model.scale = CGFloat(scale)
            drawer?.resize(to: NSSize(width: baseSize.width * CGFloat(scale), height: baseSize.height * CGFloat(scale)))
        }
        drawer.onOpen = { [model, weatherModels, media, settings] in
            let page = Dashboard.resolvedPage(model: model, settings: settings)
            model.pageID = page.id
            model.showsPerformance = page.widgets.contains { $0.kind.isPerformance }
            model.start()
            let pages = settings.settings.dashboardPages
            // Ohne Widget kein Abruf und kein Adapter-Prozess.
            if pages?.usesWeather == true { weatherModels.start(for: page.widgets.filter { $0.kind.usesPlaces }) }
            if pages?.usesMedia == true { media.start() }
        }
        drawer.onClose = { [model, weatherModels, media] in
            model.stop()
            weatherModels.stop()
            media.stop()
        }
        // Bearbeiten (Nexus > Dashboard > Bearbeiten): das Fenster bleibt
        // offen und angepinnt, unabhaengig von der Maus; Wetter, Medien und
        // Leistung laufen fuer die gerade gezeigte Seite der Sitzung wie
        // sonst auch.
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
        editor.onEnd = { [weak drawer] in
            // Entpinnen allein - das Fenster bleibt offen, bis die Maus
            // hinausgeht oder woanders hingeklickt wird, wie ein normal
            // geoeffnetes Dashboard.
            drawer?.isPinned = false
        }
    }

    /// Die Seite, die beim Oeffnen gezeigt wird: `model.pageID`, falls es sie
    /// noch gibt, sonst die erste.
    private static func resolvedPage(model: DashboardModel, settings: ShellSettingsStore) -> DashboardPage {
        let pages = settings.settings.dashboardPages
        return model.pageID.flatMap { pages?.page(id: $0) } ?? pages?.pages.first
            ?? DashboardPages.defaultPages(places: .empty, hasBattery: PerformanceSampler.hasInternalBattery)[0]
    }

    /// Nexus bei Wetter oeffnen, wenn es (noch) keinen Ort gibt - vom
    /// Aufrufer verdrahtet (siehe `AppDelegate`).
    func onOpenNexus(_ action: @escaping () -> Void) {
        weatherModels.onOpenNexus = action
    }

    func toggle() {
        drawer.toggle()
    }

    /// Baustein der Leiste (Medien, Wetter, CPU, Akku): gleich bei der
    /// passenden Seite - oder, wenn es keine mehr gibt, bei der ersten mit
    /// einem passenden Widget, sonst der ersten ueberhaupt. Ist sie schon
    /// offen, zu - wie beim Dashboard-Symbol ein zweiter Klick.
    func show(tab: DashboardTab) {
        guard let pages = settings.settings.dashboardPages else { return }
        let kinds: [WidgetKind] = switch tab {
        case .dashboard: []
        case .media: [.mediaPlayer, .media]
        case .performance: [.performanceCPU, .performanceGPU, .performanceStorage, .performanceNetwork,
                            .performanceMemory, .performanceBattery]
        case .weather: [.weatherHero, .weatherHourly, .weatherDaily, .weather]
        }
        // Waehrend einer Bearbeitung bleibt das Fenster angepinnt offen -
        // kein `drawer.close()`/`open()` (die wirken ohnehin nicht mehr,
        // `EdgeDrawer.isPinned`), nur die Sitzung wechselt die Seite, und nur
        // wenn sich eine eindeutige (Vorlage oder passendes Widget) findet -
        // sonst bleibt die Bearbeitung, wo sie ist.
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

    /// Von `FullscreenMonitor`: auf diesen Bildschirmen ist Vollbild, dort
    /// oeffnet die Maus oben nichts. An den Kanten der uebrigen Bildschirme
    /// bleibt es beim Aufklappen per Maus.
    func setFullscreen(_ screens: Set<CGDirectDisplayID>) {
        drawer.suspendedScreens = screens
    }

    /// Beim Beenden der App: den perl-Prozess des Adapters nicht verwaist
    /// weiterlaufen lassen, falls das Dashboard gerade offen ist.
    func shutdown() {
        media.stop()
    }
}
