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
    /// Eigenes Modell: laedt nur beim Oeffnen, wenn die Daten aelter als
    /// 15 min sind, und alle 30 min, solange offen.
    private let weather: WeatherModel
    /// Now Playing: der Adapter-Prozess laeuft nur, solange offen.
    private let media = MediaModel()
    private let settings: ShellSettingsStore
    private let drawer: EdgeDrawer<DashboardView>

    /// `settings`: Wetteranbieter (Nexus > Anbieter), Reiter und Karten
    /// (Nexus > Dashboard).
    init(settings: ShellSettingsStore) {
        self.settings = settings
        weather = WeatherModel(settings: settings)
        let view = DashboardView(model: model, weather: weather, media: media, settings: settings)
        // Groesse aus dem Inhalt (feste Karten-Masse), vor dem ersten Oeffnen.
        // Haengt nicht an Reitern und Karten - das Raster ist immer 839 x 392.
        let size = NSHostingView(rootView: view).fittingSize
        drawer = EdgeDrawer(edge: .top, size: size, cornerRadius: 25, rootView: view)
        drawer.opensOnHover = true
        drawer.onOpen = { [model, weather, media, settings] in
            let layout = settings.settings.dashboard
            // Ein inzwischen ausgeblendeter Reiter bleibt nicht gewaehlt.
            // Nexus und Dashboard sind nie zugleich offen (das Dashboard
            // schliesst, sobald ein anderes Fenster den Fokus hat) - beim
            // Oeffnen nachzuziehen genuegt.
            model.tab = layout.tabs.resolved(model.tab)
            model.start()
            // Ohne Karte und Reiter kein Abruf und kein Adapter-Prozess.
            if layout.usesWeather { weather.start() }
            if layout.usesMedia { media.start() }
        }
        drawer.onClose = { [model, weather, media] in
            model.stop()
            weather.stop()
            media.stop()
        }
    }

    /// Nexus bei Wetter oeffnen, wenn es (noch) keinen Ort gibt - vom
    /// Aufrufer verdrahtet (siehe `AppDelegate`).
    func onOpenNexus(_ action: @escaping () -> Void) {
        weather.onOpenNexus = action
    }

    func toggle() {
        drawer.toggle()
    }

    /// Baustein der Leiste (Medien, Wetter, CPU, Akku): gleich beim
    /// passenden Reiter - oder, wenn der ausgeblendet ist, beim ersten
    /// sichtbaren. Ist es dort schon offen, zu - wie beim Dashboard-Symbol
    /// ein zweiter Klick.
    func show(tab: DashboardTab) {
        let tab = settings.settings.dashboard.tabs.resolved(tab)
        if drawer.isOpen, model.tab == tab {
            drawer.close()
            return
        }
        model.tab = tab
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
