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
    /// `nil`: echte Modelle (`.widget`-Quelle). Gesetzt: dasselbe feste
    /// Modell fuer jedes Widget (Bildproben, Vorschau in Nexus).
    private let fixed: WeatherModel?
    /// Oeffnet Nexus bei Wetter ohne Ort - an jedes neu angelegte Modell
    /// weitergereicht (vom Aufrufer gesetzt, siehe `Dashboard`).
    var onOpenNexus: () -> Void = {}

    init(settings: ShellSettingsStore) {
        self.settings = settings
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
            read: { [weak settings] in
                guard let settings, let page = Self.page(containing: id, in: settings.settings.dashboardPages) else {
                    return .empty
                }
                return page.widgets.first { $0.id == id }?.options.places ?? .empty
            },
            write: { [weak settings] favorites in
                guard let settings, var pages = settings.settings.dashboardPages,
                      var page = Self.page(containing: id, in: pages) else { return }
                var options = page.widgets.first { $0.id == id }?.options ?? .init()
                options.places = favorites
                page.setOptions(options, for: id)
                pages.update(page)
                settings.settings.dashboardPages = pages
            }
        )
        let model = WeatherModel(settings: settings, places: source)
        model.onOpenNexus = { [weak self] in self?.onOpenNexus() }
        models[id] = model
        return model
    }

    private static func page(containing id: WidgetInstance.ID, in pages: DashboardPages?) -> DashboardPage? {
        pages?.pages.first { page in page.widgets.contains { $0.id == id } }
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
