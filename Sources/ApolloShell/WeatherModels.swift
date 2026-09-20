import ApolloShellCore
import Foundation

/// One `WeatherModel` per weather widget, created when needed and kept by the
/// id of the widget - that way every one keeps its own report, even when two
/// widgets show the same place (the fetching is shared through `WeatherModel`'s
/// report cache). The places of a widget stand in its options
/// (`WidgetOptions.places`), read and written through the page it lies on.
@MainActor
final class WeatherModels {
    private var models: [WidgetInstance.ID: WeatherModel] = [:]
    private let settings: ShellSettingsStore
    /// While an editing session runs (`editor.isEditing`) the places of the
    /// working copy hold (`editor.session`), not the saved ones - otherwise
    /// widgets would show places Nexus is only just writing or reading, late or
    /// not at all. `nil` in image samples and the preview.
    private weak var editor: DashboardEditor?
    /// `nil`: real models (the `.widget` source). Set: the same fixed model for
    /// every widget (image samples, the preview in Nexus).
    private let fixed: WeatherModel?
    /// Opens Nexus at the weather without a place - handed on to every newly
    /// created model (set by the caller, see `Dashboard`).
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

    /// The same fixed model for every widget - for image samples and the
    /// preview in Nexus, which never needs a real fetch.
    static func preview(_ model: WeatherModel) -> WeatherModels {
        WeatherModels(fixed: model)
    }

    /// The model of a widget, created anew when needed.
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

    /// The places `widget` should be showing right now: out of the working copy
    /// while an editing session runs, otherwise out of the saved pages.
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

    /// The pages that hold right now: the working copy while an editing session
    /// runs, otherwise the saved ones.
    private var currentPages: DashboardPages? {
        if let editor, editor.isEditing { return editor.session?.pages }
        return settings.settings.dashboardPages
    }

    private static func page(containing id: WidgetInstance.ID, in pages: DashboardPages?) -> DashboardPage? {
        pages?.pages.first { page in page.widgets.contains { $0.id == id } }
    }

    /// Other weather widgets on the same page that have the same place (the
    /// same coordinates) among their own places take it over too - otherwise
    /// the hero, the hours and the days of the same page drift apart (measured:
    /// the hero choice does not change the others).
    private func propagateSelection(_ location: WeatherLocation, from id: WidgetInstance.ID) {
        guard let page = Self.page(containing: id, in: currentPages) else { return }
        for widget in page.widgets where widget.id != id && widget.kind.usesPlaces {
            guard let match = (widget.options.places ?? .empty).locations.first(where: {
                $0.latitude == location.latitude && $0.longitude == location.longitude
            }) else { continue }
            model(for: widget).select(match)
        }
    }

    /// A widget whose places have just changed (Nexus, while an editing session
    /// runs): start its model again, otherwise it goes on showing the places
    /// from before the change (`start()` only reads them in then).
    func restart(_ id: WidgetInstance.ID) {
        guard let model = models[id] else { return }
        model.start()
    }

    /// Starts the models of the widgets on the open page and stops all the
    /// others - only open weather widgets fetch.
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
