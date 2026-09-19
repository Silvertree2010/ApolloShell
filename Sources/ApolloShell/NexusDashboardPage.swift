import Foundation
import ApolloShellCore
import Observation
import SwiftUI
import os

/// Wetter-Favoriten fuer ein Widget (0.2: je Wetter-Widget eine eigene
/// Liste, `WidgetOptions.places`) oder, mit `.file`, fuer die alte,
/// gemeinsame weather.json (Umzug, Wetter-Reiter vor 0.2). `read`/`write`
/// sind der Sink: `NexusWidgetPlacesSection` (NexusWidgetOptions.swift)
/// gibt eigene, die in genau das eine Widget schreiben.
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
    /// Wie beim Wetter: kein Platten-Cache, kurze Wartezeit, ohne Netz sofort Fehler.
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// Eigener Sink, z. B. das eine Widget einer Bearbeitung
    /// (`NexusWidgetPlacesSection`). `write` liefert `false`, wenn es nicht
    /// geschrieben werden konnte (zeigt `NexusSaveWarning`).
    init(read: @escaping @MainActor () -> WeatherFavorites, write: @escaping @MainActor (WeatherFavorites) -> Bool) {
        readFavorites = read
        writeFavorites = write
        live = true
        favorites = read()
    }

    /// Die Datei weather.json - vor 0.2 der einzige Ort, heute nur noch fuer
    /// den Umzug gelesen (`Dashboard.init`, `DashboardPages.migrated`).
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

    /// Frisch vom Sink lesen (Nexus-Fenster oeffnen: die Datei koennte sich
    /// seither geaendert haben; ein Widget aendert sich nur durch die
    /// laufende Sitzung selbst, das Neulesen schadet dort aber nicht).
    func reload() {
        guard live, let readFavorites else { return }
        favorites = readFavorites()
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
        guard let writeFavorites else { return }
        saveFailed = !writeFavorites(new)
    }
}

/// Die globalen Orte (weather.json), auf Nexus > Leiste. Gelten fuer
/// das Wetter-Baustein der Leiste und als Vorgabe fuer neu aus der Galerie
/// abgelegte Wetter-Widgets.
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
