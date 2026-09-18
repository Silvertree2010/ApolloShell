import ApolloShellCore
import Foundation

/// Ein `WeatherModel` je Wetter-Widget, angelegt bei Bedarf und behalten
/// ueber die Kennung des Widgets - so behaelt jedes seinen eigenen Bericht,
/// auch wenn zwei Widgets denselben Ort zeigen (der Abruf teilt sich ueber
/// `WeatherModel`s Bericht-Cache). Die Orte eines Widgets stehen in seinen
/// Optionen (`WidgetOptions.places`), gelesen und geschrieben ueber die
/// Seite, auf der es liegt.
@MainActor
final class WeatherModels {
    private var models: [WidgetInstance.ID: WeatherModel] = [:]
    private let settings: ShellSettingsStore
    /// Waehrend einer Bearbeitung (`editor.isEditing`) gelten die Orte der
    /// Arbeitskopie (`editor.session`), nicht die gespeicherten - sonst
    /// zeigten Widgets Orte, die Nexus gerade erst schreibt/liest, verzoegert
    /// oder gar nicht. `nil` in Bildproben und der Vorschau.
    private weak var editor: DashboardEditor?
    /// `nil`: echte Modelle (`.widget`-Quelle). Gesetzt: dasselbe feste
    /// Modell fuer jedes Widget (Bildproben, Vorschau in Nexus).
    private let fixed: WeatherModel?
    /// Oeffnet Nexus bei Wetter ohne Ort - an jedes neu angelegte Modell
    /// weitergereicht (vom Aufrufer gesetzt, siehe `Dashboard`).
    var onOpenNexus: () -> Void = {}

    init(settings: ShellSettingsStore, editor: DashboardEditor? = nil) {
        self.settings = settings
        self.editor = editor
        fixed = nil
    }

    private init(fixed: WeatherModel) {
        settings = .preview()
        self.fixed = fixed
    }

    /// Dasselbe feste Modell fuer jedes Widget - fuer Bildproben und die
    /// Vorschau in Nexus, die nie einen echten Abruf braucht.
    static func preview(_ model: WeatherModel) -> WeatherModels {
        WeatherModels(fixed: model)
    }

    /// Das Modell eines Widgets, bei Bedarf neu angelegt.
    func model(for widget: WidgetInstance) -> WeatherModel {
        if let fixed { return fixed }
        if let existing = models[widget.id] { return existing }
        let id = widget.id
        let source: WeatherPlacesSource = .widget(
            read: { [weak self] in
                guard let self else { return .empty }
                return self.currentPlaces(for: id)
            },
            write: { [weak self] favorites in
                self?.writePlaces(favorites, for: id)
            }
        )
        let model = WeatherModel(settings: settings, places: source)
        model.onOpenNexus = { [weak self] in self?.onOpenNexus() }
        model.onSelect = { [weak self] location in self?.propagateSelection(location, from: id) }
        models[id] = model
        return model
    }

    /// Die Orte, die `widget` gerade zeigen sollte: waehrend einer
    /// Bearbeitung aus der Arbeitskopie, sonst aus den gespeicherten Seiten.
    private func currentPlaces(for id: WidgetInstance.ID) -> WeatherFavorites {
        guard let page = Self.page(containing: id, in: currentPages) else { return .empty }
        return page.widgets.first { $0.id == id }?.options.places ?? .empty
    }

    private func writePlaces(_ favorites: WeatherFavorites, for id: WidgetInstance.ID) {
        if let editor, editor.isEditing {
            guard let page = Self.page(containing: id, in: editor.session?.pages) else { return }
            var options = page.widgets.first { $0.id == id }?.options ?? .init()
            options.places = favorites
            editor.setOptions(options, for: id)
            return
        }
        guard var pages = settings.settings.dashboardPages,
              var page = Self.page(containing: id, in: pages) else { return }
        var options = page.widgets.first { $0.id == id }?.options ?? .init()
        options.places = favorites
        page.setOptions(options, for: id)
        pages.update(page)
        settings.settings.dashboardPages = pages
    }

    /// Die gerade geltenden Seiten: Arbeitskopie waehrend einer Bearbeitung,
    /// sonst die gespeicherten.
    private var currentPages: DashboardPages? {
        if let editor, editor.isEditing { return editor.session?.pages }
        return settings.settings.dashboardPages
    }

    private static func page(containing id: WidgetInstance.ID, in pages: DashboardPages?) -> DashboardPage? {
        pages?.pages.first { page in page.widgets.contains { $0.id == id } }
    }

    /// Andere Wetter-Widgets auf derselben Seite, die denselben Ort (gleiche
    /// Koordinaten) unter ihren eigenen Orten haben, uebernehmen ihn
    /// ebenfalls - sonst laufen Hero, Stunden und Tage derselben Seite
    /// auseinander (gemessen: Hero-Auswahl aendert die anderen nicht).
    private func propagateSelection(_ location: WeatherLocation, from id: WidgetInstance.ID) {
        guard let page = Self.page(containing: id, in: currentPages) else { return }
        for widget in page.widgets where widget.id != id && widget.kind.usesPlaces {
            guard let match = (widget.options.places ?? .empty).locations.first(where: {
                $0.latitude == location.latitude && $0.longitude == location.longitude
            }) else { continue }
            model(for: widget).select(match)
        }
    }

    /// Ein Widget, dessen Orte sich gerade geaendert haben (Nexus, waehrend
    /// einer Bearbeitung): sein Modell neu starten, sonst zeigt es weiter die
    /// Orte von vor der Aenderung (`start()` liest sie erst dabei neu ein).
    func restart(_ id: WidgetInstance.ID) {
        guard let model = models[id] else { return }
        model.start()
    }

    /// Startet die Modelle der Widgets auf der offenen Seite, stoppt alle
    /// anderen - nur offene Wetter-Widgets rufen ab.
    func start(for widgets: [WidgetInstance]) {
        let wanted = Set(widgets.map(\.id))
        for widget in widgets { model(for: widget).start() }
        for (id, model) in models where !wanted.contains(id) { model.stop() }
    }

    func stop() {
        for model in models.values { model.stop() }
        fixed?.stop()
    }
}
