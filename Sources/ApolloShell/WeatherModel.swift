import Foundation
import ApolloShellCore
import Observation
import os

/// Weather for the dashboard card and the weather tab (Caelestia:
/// services/Weather.qml), data from the provider chosen in Nexus >
/// Providers (default Open-Meteo; see WeatherProvider.swift).
///
/// Only fetched while the dashboard is open: on opening, if the data is
/// older than 15 minutes, then every 30 minutes after that. The last
/// report stays in memory. If a fetch fails, it stays as is and the
/// interface subtly shows "As of HH:MM" instead of an error message - a
/// report from an hour ago is still useful.
///
/// Location and favorites come from weather.json (see
/// `WeatherFavorites.load`), selectable in the weather tab. Without
/// favorites (fresh install) there is no location and no fetch. No
/// geolocation: CoreLocation would show a permission dialog.
/// Where a weather model gets its locations from. `.file`: weather.json
/// (bar, Nexus, so far also the dashboard). `.widget`: the locations of a
/// weather widget (0.2), read and written via the page in settings.json.
enum WeatherPlacesSource {
    case file
    case widget(read: @MainActor () -> WeatherFavorites, write: @MainActor (WeatherFavorites) -> Void)
}

@MainActor
@Observable
final class WeatherModel {
    private(set) var report: WeatherReport?
    /// Timestamp of the last successful fetch.
    private(set) var fetchedAt: Date?
    private(set) var lastAttemptFailed = false
    /// `nil`: no favorites or none selected - then nothing is fetched.
    private(set) var location: WeatherLocation?
    /// For the capsules in the weather tab.
    private(set) var favorites = WeatherFavorites.empty
    /// Opens Nexus at Weather if there is (still) no location - set by
    /// the caller (see `Dashboard`).
    @ObservationIgnored var onOpenNexus: () -> Void = {}
    /// After `select(_:)`: other weather widgets on the same page with
    /// the same location (same coordinates) adopt it as well, instead of
    /// drifting apart (`WeatherModels.propagateSelection`).
    @ObservationIgnored var onSelect: (WeatherLocation) -> Void = { _ in }
    /// Who `report` came from. The source attribution belongs to the
    /// shown data, not to the setting: after a change the old data stays
    /// on screen until the new data arrives, and names its source until
    /// then.
    private(set) var source = WeatherProviderID.standard

    /// Fixed clock for image samples; `nil` = real time.
    @ObservationIgnored let fixedNow: Date?

    /// `false` for image samples: then the model does not fetch anything.
    @ObservationIgnored private let live: Bool
    /// Which provider is being asked (Nexus > Providers); `nil` in image
    /// samples.
    @ObservationIgnored private let settings: ShellSettingsStore?
    /// The provider currently being asked.
    @ObservationIgnored private var provider = WeatherProviderID.standard
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Consecutive failures; determines when it is retried.
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var retryTimer: Timer?
    @ObservationIgnored private let log = Logger(category: "weather")
    /// Where locations come from and where the selection is written.
    @ObservationIgnored private let placesSource: WeatherPlacesSource
    /// Reports per provider and location, shared between all models - two
    /// widgets for the same location thus only ask once.
    @MainActor private static var reportCache: [String: (report: WeatherReport, fetchedAt: Date)] = [:]
    /// Running fetches per provider and location: if two models come up
    /// in the same run (empty cache on opening), they share the one
    /// network fetch instead of duplicating it.
    @MainActor private static var inFlightFetches: [String: Task<Result<WeatherReport, any Error>, Never>] = [:]

    /// Its own ephemeral session: no disk cache (the data should be
    /// fresh, and the model holds on to old data anyway), a short timeout
    /// instead of the default 60 s, and an immediate error instead of
    /// waiting without a network.
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// Identifier for all requests (MET Norway requires it), built once.
    private static let userAgent = WeatherUserAgent.value(
        version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    )

    init(settings: ShellSettingsStore, places: WeatherPlacesSource = .file) {
        live = true
        fixedNow = nil
        self.settings = settings
        placesSource = places
    }

    private init(live: Bool, fixedNow: Date?) {
        self.live = live
        self.fixedNow = fixedNow
        settings = nil
        placesSource = .file
    }

    /// Key for `reportCache`: provider and location, nothing else - two
    /// widgets with the same location and provider hit the same entry.
    nonisolated private static func cacheKey(provider: WeatherProviderID, location: WeatherLocation) -> String {
        "\(provider.rawValue)|\(location.latitude)|\(location.longitude)"
    }

    /// Model with a fixed report that fetches nothing - for previews and
    /// image samples.
    static func preview(
        report: WeatherReport?,
        location: WeatherLocation? = WeatherLocation(name: "Berlin", latitude: 52.52, longitude: 13.405),
        source: WeatherProviderID = .standard,
        fetchedAt: Date?,
        lastAttemptFailed: Bool = false,
        now: Date
    ) -> WeatherModel {
        let model = WeatherModel(live: false, fixedNow: now)
        model.report = report
        model.location = location
        model.source = source
        model.fetchedAt = fetchedAt
        model.lastAttemptFailed = lastAttemptFailed
        return model
    }

    /// "Weather data: Open-Meteo" including a link - for the displayed
    /// data.
    var attribution: WeatherAttribution {
        source.provider().attribution
    }

    /// "As of HH:MM", if the data is not fresh, otherwise `nil`.
    func standText(now: Date) -> String? {
        guard let report, let fetchedAt,
              WeatherRefresh.showsStand(fetchedAt: fetchedAt, lastAttemptFailed: lastAttemptFailed, now: now)
        else { return nil }
        return WeatherText.stand(fetchedAt, calendar: report.calendar)
    }

    // MARK: - Fetching

    func start() {
        guard live else { return }
        // Re-read on every opening (a few bytes): so a changed
        // weather.json applies without a restart.
        let wantedFavorites: WeatherFavorites
        switch placesSource {
        case .file: wantedFavorites = WeatherFavorites.loadLive()
        case .widget(let read, _): wantedFavorites = read()
        }
        favorites = wantedFavorites
        let wanted = wantedFavorites.selected
        if wanted != location { switchTo(wanted) }
        // The provider likewise on opening: Nexus and the dashboard are
        // never open at the same time (the dashboard closes as soon as
        // another window gets focus), a choice in Nexus thus applies from
        // here on.
        let wantedProvider = settings?.settings.providers.weather ?? .standard
        let providerChanged = wantedProvider != provider
        if providerChanged { switchProvider(to: wantedProvider) }
        // No location: nothing to fetch - only a favorite makes the
        // weather fetchable.
        if let location {
            // Another widget for the same location may have already
            // fetched more recently - adopt its report instead of asking
            // again.
            let key = Self.cacheKey(provider: provider, location: location)
            if let cached = Self.reportCache[key], cached.fetchedAt > (fetchedAt ?? .distantPast) {
                report = cached.report
                fetchedAt = cached.fetchedAt
                lastAttemptFailed = false
                source = provider
            }
            if providerChanged || WeatherRefresh.needsFetch(fetchedAt: fetchedAt, now: Date()) { fetch() }
        }
        timer?.invalidate()
        timer = .repeating(every: WeatherRefresh.interval, owner: self) { $0.fetch() }
    }

    /// A running fetch is allowed to finish: its result is welcome the
    /// next time it opens.
    func stop() {
        timer?.invalidate()
        timer = nil
        retryTimer?.invalidate()
        retryTimer = nil
    }

    /// Selection in the weather tab, one of the favorites: switch and
    /// fetch immediately, and remember it in weather.json - the same file
    /// Nexus writes and `start()` reads, so all three mean the same
    /// location.
    func select(_ wanted: WeatherLocation) {
        guard live, wanted != location else { return }
        favorites.select(id: wanted.id)
        switchTo(wanted)
        fetch()
        switch placesSource {
        case .file:
            do {
                try ShellFiles.write(favorites.fileData(), to: ShellFiles.live.weather)
            } catch {
                log.error("weather.json not saved: \((error as NSError).code, privacy: .public)")
            }
        case .widget(_, let write):
            write(favorites)
        }
        onSelect(wanted)
    }

    /// Different location (or none anymore): the old weather no longer
    /// applies, not even as "as of". A running fetch for the old location
    /// is cancelled - otherwise it would block the new one (`fetch()`
    /// only starts if none is running).
    private func switchTo(_ wanted: WeatherLocation?) {
        location = wanted
        report = nil
        fetchedAt = nil
        lastAttemptFailed = false
        failures = 0
        cancelFetch()
    }

    /// Different provider: ask right away, even if the data is fresh. The
    /// weather still applies to the same location and stays on screen
    /// until then (with its own source attribution). Failures count
    /// again from zero.
    private func switchProvider(to id: WeatherProviderID) {
        provider = id
        lastAttemptFailed = false
        failures = 0
        cancelFetch()
    }

    private func cancelFetch() {
        task?.cancel()
        task = nil
        retryTimer?.invalidate()
        retryTimer = nil
    }

    /// All of the provider's requests, one after another (at most two).
    /// If an optional one fails (MET: sun times), the report applies
    /// without it. Checks the report cache itself (another widget may
    /// have already fetched) and shares a running fetch of the same
    /// provider/location with other models instead of duplicating it.
    private func fetch() {
        guard task == nil, let location else { return }
        let id = provider
        let key = Self.cacheKey(provider: id, location: location)
        if let cached = Self.reportCache[key], !WeatherRefresh.needsFetch(fetchedAt: cached.fetchedAt, now: Date()) {
            finish(.success(cached.report), for: location, from: id)
            return
        }
        let shared: Task<Result<WeatherReport, any Error>, Never>
        if let running = Self.inFlightFetches[key] {
            shared = running
        } else {
            let provider = id.provider()
            let requests = provider.requests(for: location, now: Date())
                .map { ($0.optional, $0.urlRequest(userAgent: Self.userAgent)) }
            let newTask = Task<Result<WeatherReport, any Error>, Never> { [session] in
                let result: Result<WeatherReport, any Error>
                do {
                    var bodies: [Data?] = []
                    for (optional, request) in requests {
                        do {
                            bodies.append(try await Self.load(request, session: session))
                        } catch {
                            guard optional, !Task.isCancelled else { throw error }
                            bodies.append(nil)
                        }
                    }
                    result = .success(try provider.decode(bodies, now: Date()))
                } catch {
                    result = .failure(error)
                }
                return result
            }
            Self.inFlightFetches[key] = newTask
            shared = newTask
            // Only the one who created it cleans up - after that a new
            // fetch makes its own request again.
            Task { [key] in
                _ = await newTask.value
                Self.inFlightFetches[key] = nil
            }
        }
        task = Task { [weak self] in
            let result = await shared.value
            self?.finish(result, for: location, from: id)
        }
    }

    /// 200, plus 203: this is how MET Norway reports an outdated API
    /// version - the data is still valid.
    nonisolated private static func load(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 203 else { throw HTTPStatus(code: status) }
        return data
    }

    private func finish(_ result: Result<WeatherReport, any Error>, for requested: WeatherLocation,
                        from id: WeatherProviderID) {
        // Location or provider changed during the fetch: the result does
        // not belong here, and `task` is already the new fetch.
        guard requested == location, id == provider else { return }
        task = nil
        switch result {
        case .success(let report):
            self.report = report
            source = id
            fetchedAt = Date()
            lastAttemptFailed = false
            failures = 0
            Self.reportCache[Self.cacheKey(provider: id, location: requested)] = (report, fetchedAt!)
        case .failure(let error):
            failures += 1
            scheduleRetry()
            // Only the first failure of a series goes into the log:
            // without a network every attempt fails the same way, that
            // does not need a line every half hour.
            if !lastAttemptFailed {
                // Only provider, domain, and code: the description of a
                // URLError contains the address including coordinates,
                // i.e. the home location - that does not belong in the
                // system log.
                let nsError = error as NSError
                let status = (error as? HTTPStatus)?.code ?? nsError.code
                log.error("Weather not fetched: \(id.rawValue, privacy: .public) \(nsError.domain, privacy: .public) \(status, privacy: .public)")
            }
            lastAttemptFailed = true
        }
    }

    /// Only while open (`timer` is running): closed, nobody needs the
    /// weather; on the next opening `start()` fetches again anyway.
    private func scheduleRetry() {
        guard timer != nil else { return }
        retryTimer?.invalidate()
        retryTimer = .once(after: WeatherRefresh.retryDelay(afterFailures: failures), owner: self) { model in
            model.retryTimer = nil
            model.fetch()
        }
    }

    private struct HTTPStatus: Error {
        let code: Int
    }
}
