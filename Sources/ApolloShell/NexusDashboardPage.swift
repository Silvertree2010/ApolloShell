import Foundation
import ApolloShellCore
import Observation
import SwiftUI
import os

/// Wetter-Favoriten fuer das Dashboard: Ortssuche bei Open-Meteo, gespeichert
/// in weather.json. `WeatherModel.start()` liest die Datei bei jedem Oeffnen
/// des Dashboards; eine Aenderung gilt also beim naechsten Oeffnen, und das
/// alte Wetter wird dort sofort verworfen. Gleichzeitig offen sind Nexus und
/// Dashboard nie (das Dashboard schliesst, sobald ein anderes Fenster den
/// Fokus hat) - "sofort" braucht es deshalb nicht.
@MainActor
@Observable
final class NexusWeatherModel {
    enum SearchState: Equatable {
        /// Kein Suchtext oder zu kurz - es wird nicht gefragt.
        case idle
        case searching
        case done
        case failed
    }

    private(set) var favorites = WeatherFavorites.empty
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    private(set) var results: [GeocodingPlace] = []
    private(set) var state = SearchState.idle
    private(set) var saveFailed = false

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(category: "nexus")
    /// Wie beim Wetter: kein Platten-Cache, kurze Wartezeit, ohne Netz sofort Fehler.
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// `url == nil`: nur im Speicher.
    init(url: URL?) {
        self.url = url
        live = true
    }

    private init(preview: Void) {
        url = nil
        live = false
    }

    /// Fuer Bildproben: fester Stand, fragt nie im Netz.
    static func preview(favorites: WeatherFavorites, query: String,
                        results: [GeocodingPlace], state: SearchState) -> NexusWeatherModel {
        let model = NexusWeatherModel(preview: ())
        model.favorites = favorites
        model.query = query
        model.results = results
        model.state = state
        return model
    }

    func reload() {
        guard live else { return }
        favorites = WeatherFavorites.load(from: ShellFiles.read(url))
    }

    /// Erst nach einer Tipppause fragen (`OpenMeteoGeocoding.debounce`), und
    /// nur wenn der Text lang genug ist. Jeder Tastendruck bricht die
    /// vorige Suche ab; so kommt nie eine alte Antwort nach einer neuen an.
    private func scheduleSearch() {
        task?.cancel()
        task = nil
        guard live else { return }
        guard let url = OpenMeteoGeocoding.url(for: query) else {
            results = []
            state = .idle
            return
        }
        task = Task { [weak self, session] in
            do {
                try await Task.sleep(for: OpenMeteoGeocoding.debounce)
            } catch {
                return // abgebrochen: es wurde weitergetippt
            }
            self?.state = .searching
            let outcome: Result<[GeocodingPlace], any Error>
            do {
                let (data, response) = try await session.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                outcome = .success(try OpenMeteoGeocoding.decode(data))
            } catch {
                outcome = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case .success(let places):
                self.results = places
                self.state = .done
            case .failure(let error):
                // Nur Domaene und Code: die Adresse enthaelt den Suchtext,
                // also moeglicherweise den Wohnort.
                let nsError = error as NSError
                self.log.error("Ortssuche fehlgeschlagen: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
                self.results = []
                self.state = .failed
            }
        }
    }

    func cancelSearch() {
        task?.cancel()
        task = nil
    }

    /// Treffer der Suche als neuen Favoriten anhaengen (Plus). War er schon
    /// Favorit, aendert sich nichts - kein zweiter Eintrag fuer denselben Ort.
    func addFavorite(_ place: GeocodingPlace) {
        var updated = favorites
        updated.add(place.location)
        write(updated)
    }

    func removeFavorite(_ id: WeatherLocation.ID) {
        var updated = favorites
        updated.remove(id: id)
        write(updated)
    }

    func moveFavorites(fromOffsets: IndexSet, toOffset: Int) {
        var updated = favorites
        updated.move(fromOffsets: fromOffsets, toOffset: toOffset)
        write(updated)
    }

    func selectFavorite(_ id: WeatherLocation.ID) {
        var updated = favorites
        updated.select(id: id)
        write(updated)
    }

    func isFavorite(_ place: GeocodingPlace) -> Bool {
        favorites.locations.contains { $0.latitude == place.latitude && $0.longitude == place.longitude }
    }

    private func write(_ new: WeatherFavorites) {
        favorites = new
        guard let url else { return }
        do {
            try ShellFiles.write(new.fileData(), to: url)
            if saveFailed { saveFailed = false }
        } catch {
            saveFailed = true
            log.error("weather.json nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Caelestia: Panels > Dashboard und Language & region > Weather (dort noch
/// "Location picker coming soon"). Oben der Baukasten (Reiter, Karten,
/// Vorlagen; NexusDashboardEditor.swift), darunter der Wetterort, unten fest
/// die Vorschau.
struct NexusDashboardPage: View {
    @Bindable var store: ShellSettingsStore
    @Bindable var model: NexusWeatherModel
    @State private var showsGallery = false
    @State private var pending: LayoutPresetReplacement<DashboardPreset>?
    /// Aufgeklappte Karten: bleiben beim Umsortieren offen.
    @State private var expanded: Set<DashboardCardKind>

    /// `expanded`: schon aufgeklappte Karten (Bildprobe).
    init(store: ShellSettingsStore, model: NexusWeatherModel, expanded: Set<DashboardCardKind> = []) {
        _store = Bindable(store)
        _model = Bindable(model)
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                NexusPageForm(page: .dashboard) {
                    NexusDashboardTabsSection(store: store)
                    NexusDashboardCardSections(store: store, expanded: $expanded,
                                               onAdd: { showsGallery = true }, onReplace: { pending = $0 })
                    weatherSections
                    NexusSaveWarning(failed: store.saveFailed)
                    NexusSaveWarning(failed: model.saveFailed, file: "weather.json")
                }
                Divider()
                NexusDashboardPreview(store: store)
                    .frame(height: NexusDashboardPreview.height(for: geometry.size.height))
            }
        }
        .sheet(isPresented: $showsGallery) {
            NexusDashboardGallery(cards: store.settings.dashboard.cards, onAdd: add, onCancel: { showsGallery = false })
        }
        .nexusPresetAlert($pending, title: NexusDashboardText.replacementTitle, message: NexusDashboardText.replacementMessage) { layout in
            store.settings.dashboard = layout
            expanded = []
        }
    }

    /// Aus der Galerie: an ihren Platz, mit Optionen gleich aufgeklappt.
    private func add(_ kind: DashboardCardKind) {
        showsGallery = false
        if store.settings.dashboard.cards.add(kind) != nil {
            expanded.insert(kind)
        }
    }

    @ViewBuilder private var weatherSections: some View {
            Section {
                if model.favorites.locations.isEmpty {
                    Text("No favorites yet – search for a place below and add it.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.favorites.locations) { place in
                    NexusWeatherFavoriteRow(model: model, place: place)
                }
                .onMove { model.moveFavorites(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Favorites")
            } footer: {
                Text("The selected favorite applies to the weather. Drag to reorder. The Dashboard shows a change the next time it opens.")
            }

            Section {
                NexusSearchField(prompt: "Search for a Place", text: $model.query, busy: model.state == .searching)
                ForEach(model.results) { place in
                    NexusWeatherSearchRow(model: model, place: place)
                }
                switch model.state {
                case .done where model.results.isEmpty:
                    Text("No place found.")
                        .foregroundStyle(.secondary)
                case .failed:
                    Label("Open-Meteo unreachable.", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            } header: {
                Text("Search for a Place")
            } footer: {
                Text("The search only asks Open-Meteo once you type.")
            }
    }
}

private struct NexusWeatherFavoriteRow: View {
    let model: NexusWeatherModel
    let place: WeatherLocation

    var body: some View {
        let selected = model.favorites.selectedID == place.id
        HStack(spacing: 10) {
            Button {
                model.selectFavorite(place.id)
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(selected ? "Selected Place" : "Set as Weather Location")
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name)
                Text(place.coordinateText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                model.removeFavorite(place.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove")
            .accessibilityLabel("Remove \(place.name)")
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }
}

private struct NexusWeatherSearchRow: View {
    let model: NexusWeatherModel
    let place: GeocodingPlace

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name)
                if !place.detail.isEmpty {
                    Text(place.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                model.addFavorite(place)
            } label: {
                Image(systemName: model.isFavorite(place) ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(model.isFavorite(place) ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
            }
            .buttonStyle(.borderless)
            .disabled(model.isFavorite(place))
            .help("Add as Favorite")
            .accessibilityLabel("Add \(place.name) as favorite")
        }
        .contentShape(.rect)
    }
}
