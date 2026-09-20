import Foundation
import ApolloShellCore
import Observation
import SwiftUI
import os

/// The weather favourites for one widget (0.2: a list of its own per weather
/// widget, `WidgetOptions.places`) or, with `.file`, for the old shared
/// weather.json (the migration, the weather tab before 0.2). `read`/`write`
/// are the sink: `NexusWidgetPlacesSection` (NexusWidgetOptions.swift) brings
/// its own, which write into exactly that one widget.
@MainActor
@Observable
final class NexusWeatherModel {
    enum SearchState: Equatable {
        /// No search text or too short - nothing is asked.
        case idle
        case searching
        case done
        case failed
    }

    private(set) var favorites: WeatherFavorites
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    private(set) var results: [GeocodingPlace] = []
    private(set) var state = SearchState.idle
    private(set) var saveFailed = false

    @ObservationIgnored private let readFavorites: (@MainActor () -> WeatherFavorites)?
    @ObservationIgnored private let writeFavorites: (@MainActor (WeatherFavorites) -> Bool)?
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(category: "nexus")
    /// As with the weather: no disk cache, a short wait, an error right away without a network.
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// A sink of its own, the one widget of an editing session, say
    /// (`NexusWidgetPlacesSection`). `write` hands back `false` when it could
    /// not be written (which shows `NexusSaveWarning`).
    init(read: @escaping @MainActor () -> WeatherFavorites, write: @escaping @MainActor (WeatherFavorites) -> Bool) {
        readFavorites = read
        writeFavorites = write
        live = true
        favorites = read()
    }

    /// The file weather.json - before 0.2 the only place, today only read for
    /// the migration (`Dashboard.init`, `DashboardPages.migrated`).
    static func file(url: URL?) -> NexusWeatherModel {
        NexusWeatherModel(
            read: { WeatherFavorites.load(from: ShellFiles.read(url)) },
            write: { new in
                guard let url else { return true }
                do {
                    try ShellFiles.write(new.fileData(), to: url)
                    return true
                } catch {
                    return false
                }
            }
        )
    }

    private init(preview: Void) {
        readFavorites = nil
        writeFavorites = nil
        live = false
        favorites = .empty
    }

    /// For image samples: a fixed state, never asks the network.
    static func preview(favorites: WeatherFavorites, query: String,
                        results: [GeocodingPlace], state: SearchState) -> NexusWeatherModel {
        let model = NexusWeatherModel(preview: ())
        model.favorites = favorites
        model.query = query
        model.results = results
        model.state = state
        return model
    }

    /// Read fresh from the sink (opening the Nexus window: the file could have
    /// changed since; a widget only changes through the running session itself,
    /// but reading again does no harm there).
    func reload() {
        guard live, let readFavorites else { return }
        favorites = readFavorites()
    }

    /// Only ask after a pause in the typing (`OpenMeteoGeocoding.debounce`),
    /// and only when the text is long enough. Every key press cancels the
    /// previous search; so an old answer never arrives after a new one.
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
                // Only the domain and the code: the address holds the search
                // text, so possibly where the user lives.
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

    /// Append a hit of the search as a new favourite (plus). When it was a
    /// favourite already, nothing changes - no second entry for the same place.
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
        guard let writeFavorites else { return }
        saveFailed = !writeFavorites(new)
    }
}

/// The global places (weather.json), on Nexus > Bar. They hold for the weather
/// block of the bar and as the default for weather widgets newly dropped out
/// of the gallery.
struct NexusDashboardWeatherSection: View {
    let model: NexusWeatherModel

    var body: some View {
        Section {
            if model.favorites.locations.isEmpty {
                Text("No favorites yet – search for a place below and add it.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.favorites.locations) { place in
                NexusWeatherFavoriteRow(model: model, place: place)
            }
            NexusSearchField(prompt: "Search for a Place", text: Binding(get: { model.query }, set: { model.query = $0 }),
                            busy: model.state == .searching)
            ForEach(model.results) { place in
                NexusWeatherSearchRow(model: model, place: place)
            }
        } header: {
            Text("Places for the bar and new weather widgets")
        }
    }
}

struct NexusWeatherFavoriteRow: View {
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

struct NexusWeatherSearchRow: View {
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
