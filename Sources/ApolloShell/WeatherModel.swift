import Foundation
import ApolloShellCore
import Observation
import os

/// Wetter fuer Dashboard-Karte und Wetter-Reiter (Caelestia:
/// services/Weather.qml), Daten vom Anbieter aus Nexus > Anbieter (Vorgabe
/// Open-Meteo; siehe WeatherProvider.swift).
///
/// Abgerufen wird nur, solange das Dashboard offen ist: beim Oeffnen, wenn
/// die Daten aelter als 15 Minuten sind, danach alle 30 Minuten. Der letzte
/// Bericht bleibt im Speicher. Schlaegt ein Abruf fehl, bleibt er stehen und
/// die Oberflaeche zeigt dezent "Stand HH:MM" statt einer Fehlermeldung -
/// ein Bericht von vor einer Stunde ist immer noch nuetzlich.
///
/// Ort und Favoriten kommen aus weather.json (siehe `WeatherFavorites.load`),
/// im Wetter-Reiter waehlbar. Ohne Favoriten (frische Installation) gibt es
/// keinen Ort und keinen Abruf. Keine Ortung: CoreLocation wuerde einen
/// Freigabe-Dialog zeigen.
/// Woher ein Wetter-Modell seine Orte hat. `.file`: weather.json (Leiste,
/// Nexus, bisher auch das Dashboard). `.widget`: die Orte eines Wetter-
/// Widgets (0.2), gelesen und geschrieben ueber die Seite in settings.json.
enum WeatherPlacesSource {
    case file
    case widget(read: @MainActor () -> WeatherFavorites, write: @MainActor (WeatherFavorites) -> Void)
}

@MainActor
@Observable
final class WeatherModel {
    private(set) var report: WeatherReport?
    /// Zeitpunkt des letzten erfolgreichen Abrufs.
    private(set) var fetchedAt: Date?
    private(set) var lastAttemptFailed = false
    /// `nil`: keine Favoriten oder keiner gewaehlt - dann wird nichts abgerufen.
    private(set) var location: WeatherLocation?
    /// Fuer die Kapseln im Wetter-Reiter.
    private(set) var favorites = WeatherFavorites.empty
    /// Oeffnet Nexus bei Wetter, wenn es (noch) keinen Ort gibt - vom
    /// Aufrufer gesetzt (siehe `Dashboard`).
    @ObservationIgnored var onOpenNexus: () -> Void = {}
    /// Nach `select(_:)`: andere Wetter-Widgets derselben Seite mit
    /// demselben Ort (gleiche Koordinaten) uebernehmen ihn ebenfalls, statt
    /// auseinanderzulaufen (`WeatherModels.propagateSelection`).
    @ObservationIgnored var onSelect: (WeatherLocation) -> Void = { _ in }
    /// Von wem `report` stammt. Die Quellenangabe gehoert zu den gezeigten
    /// Daten, nicht zur Einstellung: nach einem Wechsel bleiben die alten
    /// Daten stehen, bis die neuen da sind, und nennen bis dahin ihre Quelle.
    private(set) var source = WeatherProviderID.standard

    /// Feste Uhr fuer Bildproben; `nil` = echte Zeit.
    @ObservationIgnored let fixedNow: Date?

    /// `false` fuer Bildproben: dann ruft das Modell nichts ab.
    @ObservationIgnored private let live: Bool
    /// Welcher Anbieter gefragt wird (Nexus > Anbieter); `nil` in Bildproben.
    @ObservationIgnored private let settings: ShellSettingsStore?
    /// Der Anbieter, bei dem gerade gefragt wird.
    @ObservationIgnored private var provider = WeatherProviderID.standard
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Fehlschlaege in Folge; bestimmt, wann es nochmal versucht wird.
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var retryTimer: Timer?
    @ObservationIgnored private let log = Logger(category: "weather")
    /// Woher Orte kommen und wohin die Wahl geschrieben wird.
    @ObservationIgnored private let placesSource: WeatherPlacesSource
    /// Berichte je Anbieter und Ort, geteilt zwischen allen Modellen - zwei
    /// Widgets fuer denselben Ort fragen so nur einmal.
    @MainActor private static var reportCache: [String: (report: WeatherReport, fetchedAt: Date)] = [:]
    /// Laufende Abrufe je Anbieter und Ort: kommen zwei Modelle im selben
    /// Zug dran (leerer Cache beim Oeffnen), teilen sie sich den einen
    /// Netzwerk-Abruf, statt ihn zu verdoppeln.
    @MainActor private static var inFlightFetches: [String: Task<Result<WeatherReport, any Error>, Never>] = [:]

    /// Eigene fluechtige Sitzung: kein Platten-Cache (die Daten sollen frisch
    /// sein, und alte haelt das Modell ohnehin), kurze Wartezeit statt der
    /// Standard-60 s, und ohne Netz sofort ein Fehler statt Warten.
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// Kennung fuer alle Anfragen (MET Norway verlangt sie), einmal gebaut.
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

    /// Schluessel fuer `reportCache`: Anbieter und Ort, nichts sonst - zwei
    /// Widgets mit demselben Ort und Anbieter treffen denselben Eintrag.
    nonisolated private static func cacheKey(provider: WeatherProviderID, location: WeatherLocation) -> String {
        "\(provider.rawValue)|\(location.latitude)|\(location.longitude)"
    }

    /// Modell mit festem Bericht, das nichts abruft - fuer Vorschauen und
    /// Bildproben.
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

    /// "Wetterdaten: Open-Meteo" samt Link - fuer die angezeigten Daten.
    var attribution: WeatherAttribution {
        source.provider().attribution
    }

    /// "Stand HH:MM", falls die Daten nicht frisch sind, sonst `nil`.
    func standText(now: Date) -> String? {
        guard let report, let fetchedAt,
              WeatherRefresh.showsStand(fetchedAt: fetchedAt, lastAttemptFailed: lastAttemptFailed, now: now)
        else { return nil }
        return WeatherText.stand(fetchedAt, calendar: report.calendar)
    }

    // MARK: - Abrufen

    func start() {
        guard live else { return }
        // Bei jedem Oeffnen neu gelesen (ein paar Byte): so gilt eine
        // geaenderte weather.json ohne Neustart.
        let wantedFavorites: WeatherFavorites
        switch placesSource {
        case .file: wantedFavorites = WeatherFavorites.load(from: try? Data(contentsOf: ShellFiles.live.weather))
        case .widget(let read, _): wantedFavorites = read()
        }
        favorites = wantedFavorites
        let wanted = wantedFavorites.selected
        if wanted != location { switchTo(wanted) }
        // Der Anbieter ebenso beim Oeffnen: Nexus und Dashboard sind nie
        // gleichzeitig offen (das Dashboard schliesst, sobald ein anderes
        // Fenster den Fokus hat), eine Wahl in Nexus gilt also ab hier.
        let wantedProvider = settings?.settings.providers.weather ?? .standard
        let providerChanged = wantedProvider != provider
        if providerChanged { switchProvider(to: wantedProvider) }
        // Kein Ort: nichts abzurufen - erst ein Favorit macht das Wetter abrufbar.
        if let location {
            // Ein anderes Widget fuer denselben Ort hat vielleicht schon
            // frischer abgerufen - dessen Bericht uebernehmen statt neu zu fragen.
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

    /// Ein laufender Abruf darf zu Ende laufen: sein Ergebnis ist beim
    /// naechsten Oeffnen willkommen.
    func stop() {
        timer?.invalidate()
        timer = nil
        retryTimer?.invalidate()
        retryTimer = nil
    }

    /// Auswahl im Wetter-Reiter, einer der Favoriten: sofort umschalten und
    /// abrufen, und in weather.json merken - dieselbe Datei, die Nexus
    /// schreibt und `start()` liest, damit alle drei denselben Ort meinen.
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
                log.error("weather.json nicht gespeichert: \((error as NSError).code, privacy: .public)")
            }
        case .widget(_, let write):
            write(favorites)
        }
        onSelect(wanted)
    }

    /// Anderer Ort (oder keiner mehr): das alte Wetter gilt nicht mehr, auch
    /// nicht als "Stand". Ein laufender Abruf fuer den alten Ort wird
    /// abgebrochen - sonst blockierte er den neuen (`fetch()` startet nur,
    /// wenn keiner laeuft).
    private func switchTo(_ wanted: WeatherLocation?) {
        location = wanted
        report = nil
        fetchedAt = nil
        lastAttemptFailed = false
        failures = 0
        cancelFetch()
    }

    /// Anderer Anbieter: gleich fragen, auch wenn die Daten frisch sind. Das
    /// Wetter gilt weiter fuer denselben Ort und bleibt bis dahin stehen
    /// (mit seiner eigenen Quellenangabe). Fehlschlaege zaehlen neu.
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

    /// Alle Anfragen des Anbieters nacheinander (hoechstens zwei). Scheitert
    /// eine optionale (MET: Sonnenzeiten), gilt der Bericht ohne sie. Prueft
    /// den Bericht-Cache selbst (ein anderes Widget hat vielleicht schon
    /// abgerufen) und teilt einen laufenden Abruf desselben Anbieters/Orts
    /// mit anderen Modellen, statt ihn zu verdoppeln.
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
            // Nur der Anleger raeumt auf - danach macht ein neuer Abruf
            // wieder eine eigene Anfrage.
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

    /// 200, dazu 203: so meldet MET Norway eine veraltete Schnittstellen-
    /// Fassung - die Daten gelten trotzdem.
    nonisolated private static func load(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 203 else { throw HTTPStatus(code: status) }
        return data
    }

    private func finish(_ result: Result<WeatherReport, any Error>, for requested: WeatherLocation,
                        from id: WeatherProviderID) {
        // Ort oder Anbieter waehrend des Abrufs gewechselt: Ergebnis gehoert
        // nicht hierher, und `task` ist schon der neue Abruf.
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
            // Nur der erste Fehler einer Serie ins Log: ohne Netz scheitert
            // jeder Versuch gleich, das braucht nicht jede halbe Stunde eine Zeile.
            if !lastAttemptFailed {
                // Nur Anbieter, Domaene und Code: die Beschreibung eines
                // URLError enthaelt die Adresse samt Koordinaten, also den
                // Wohnort - der gehoert nicht ins Systemprotokoll.
                let nsError = error as NSError
                let status = (error as? HTTPStatus)?.code ?? nsError.code
                log.error("Wetter nicht abgerufen: \(id.rawValue, privacy: .public) \(nsError.domain, privacy: .public) \(status, privacy: .public)")
            }
            lastAttemptFailed = true
        }
    }

    /// Nur solange offen (`timer` laeuft): zu, braucht niemand das Wetter;
    /// beim naechsten Oeffnen ruft `start()` ohnehin neu ab.
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
