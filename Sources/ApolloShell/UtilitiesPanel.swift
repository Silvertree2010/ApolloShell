import AppKit
import ApolloShellCore
import Observation
import SwiftUI

/// Utilities-Panel unten rechts (Caelestia: modules/utilities in der Ecke
/// rechts unten). Oeffnet per SUPER+U, ueber das Symbol in der Leiste und
/// wie bei Caelestia, wenn die Maus unten rechts an den Rand stoesst - nur
/// nicht ganz in der Ecke, die belegt macOS von Haus aus als heisse Ecke mit
/// der Schnellnotiz (`EdgeHoverArea.cornerGap`).
///
/// Karten und Schnellschalter kommen aus Nexus > Schnellaktionen
/// (settings.utilities.layout). Jede Aenderung gilt sofort: das Panel
/// zeichnet die neue Anordnung und nimmt die Hoehe an, die
/// `UtilitiesLayout.panelHeight` dafuer rechnet.
@MainActor
final class UtilitiesPanel {
    private let model: UtilitiesModel
    private let state: UtilitiesLayoutState
    private let drawer: EdgeDrawer<UtilitiesPanelView>
    private var observation: Task<Void, Never>?
    private var lidObservation: Task<Void, Never>?
    /// Auf oder zu - die Kurzmeldungen weichen dann nach oben aus
    /// (Caelestia haengt sie an `utilities.top`).
    var onVisibilityChange: (_ open: Bool) -> Void = { _ in }
    /// Neue Hoehe nach einer Aenderung in Nexus - fuer die Kurzmeldungen,
    /// die ueber dem Panel sitzen.
    var onHeightChange: (_ height: CGFloat) -> Void = { _ in }
    /// Einstellungs-Knopf: Nexus oeffnen.
    var onOpenSettings: () -> Void = {}
    /// Kurzmeldung zeigen (Farbpipette: "Color Copied"). Setzt LauncherApp,
    /// sobald es den Toaster gibt - der entsteht erst nach dem Panel, weil
    /// sein Fenster die Panelhoehe braucht.
    var onToast: (ToastText.Content) -> Void = { _ in }

    /// Sichtbare Hoehe des Panels.
    var height: CGFloat { drawer.size.height }

    /// `model`: fuer Bildproben ein Vorschau-Modell, das nichts liest und
    /// nichts schaltet; sonst das echte.
    init(settings: ShellSettingsStore, model injected: UtilitiesModel? = nil) {
        model = injected ?? UtilitiesModel(lidAllowed: { settings.settings.keepAwake.lidClosed })
        let layout = settings.settings.utilities.layout
        state = UtilitiesLayoutState(layout: layout)
        let view = UtilitiesPanelView(model: model, state: state)
        // Hoehe gerechnet, nicht gemessen: jede Karte hat eine feste Hoehe
        // (UtilitiesMetrics), die Ansicht haelt sich daran. Kein Zustand
        // (langer Geraetename, Wach halten an) aendert sie.
        drawer = EdgeDrawer(edge: .bottomRight, size: Self.size(for: layout), cornerRadius: 25, rootView: view)
        drawer.opensOnHover = true
        drawer.onOpen = { [weak self] in
            self?.model.start()
            self?.onVisibilityChange(true)
        }
        drawer.onClose = { [weak self] in
            self?.model.stop()
            self?.onVisibilityChange(false)
        }
        // Panel ausdruecklich zu, dann Nexus auf. Nicht darauf warten, dass
        // es sich beim Fokuswechsel selbst schliesst: das haengt an der
        // Reihenfolge, in der macOS die Fenster umschaltet.
        model.onOpenSettings = { [weak self] in
            self?.drawer.close()
            self?.onOpenSettings()
        }
        // Aktionen, die den Bildschirm oder die Tastatur brauchen
        // (Bildschirmfoto, Schreibtisch, Pipette, Sperren, Apps, Links):
        // erst wenn das Panel ganz weg ist.
        model.closePanel = { [weak self] then in
            self?.drawer.close(then: then)
        }
        model.onToast = { [weak self] content in
            self?.onToast(content)
        }
        // Liefert zuerst den aktuellen Wert (gleich, also nichts zu tun),
        // danach jede Aenderung aus Nexus. Lebt so lange wie die App.
        observation = Task { [weak self, settings] in
            for await layout in Observations({ settings.settings.utilities.layout }) {
                self?.apply(layout)
            }
        }
        // "Also With the Lid Closed" in Nexus: gilt sofort, auch mitten
        // in "Keep Awake". Der erste Wert kommt beim Start (dann ist es aus).
        lidObservation = Task { [weak self, settings] in
            for await _ in Observations({ settings.settings.keepAwake.lidClosed }) {
                self?.model.lidSettingChanged()
            }
        }
    }

    static func size(for layout: UtilitiesLayout) -> NSSize {
        NSSize(width: UtilitiesView.width, height: CGFloat(layout.panelHeight))
    }

    /// Inhalt und Rahmen im selben Durchgang: SwiftUI zeichnet die neue
    /// Anordnung im naechsten Bild, das Fenster hat bis dahin schon die
    /// passende Groesse - offen springt also nichts halb.
    private func apply(_ layout: UtilitiesLayout) {
        guard layout != state.layout else { return }
        state.layout = layout
        let size = Self.size(for: layout)
        guard size != drawer.size else { return }
        drawer.resize(to: size)
        onHeightChange(size.height)
    }

    func toggle() {
        drawer.toggle()
    }

    /// Beim Beenden der App: Wach halten (auch zugeklappt) sauber loesen.
    func shutdown() {
        model.shutdown()
    }

    /// Von `FullscreenMonitor`: auf diesen Bildschirmen ist Vollbild, dort
    /// oeffnet die Maus unten rechts nichts. An den Kanten der uebrigen
    /// Bildschirme bleibt es beim Aufklappen per Maus.
    func setFullscreen(_ screens: Set<CGDirectDisplayID>) {
        drawer.suspendedScreens = screens
    }
}

/// Die Anordnung, die das Panel gerade zeigt. Eigene Kopie statt direkt
/// `ShellSettingsStore`: so aendern sich Inhalt und Fensterrahmen im selben
/// Aufruf (`UtilitiesPanel.apply`), nicht der Inhalt ein Bild vor dem Rahmen.
@MainActor
@Observable
final class UtilitiesLayoutState {
    var layout: UtilitiesLayout

    init(layout: UtilitiesLayout) {
        self.layout = layout
    }
}

/// Wurzel im Kantenfenster: das Panel mit der aktuellen Anordnung.
struct UtilitiesPanelView: View {
    let model: UtilitiesModel
    let state: UtilitiesLayoutState

    var body: some View {
        UtilitiesView(model: model, layout: state.layout)
    }
}
