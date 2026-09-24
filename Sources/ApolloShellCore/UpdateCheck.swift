import Foundation

/// Das neueste Release, wie GitHub es meldet.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    /// Seite des Releases mit den Notizen.
    public let page: URL

    public init(version: AppVersion, page: URL) {
        self.version = version
        self.page = page
    }
}

/// Was eine Pruefung ergeben hat.
public enum UpdateCheckOutcome: Equatable, Sendable {
    /// Die laufende Fassung ist die neueste (oder sogar neuer).
    case current
    /// Es gibt eine neuere Fassung.
    case newer(ReleaseInfo)
    /// Die Pruefung ist nicht durchgekommen. Der Text ist fuer die Anzeige,
    /// nicht fuer Entscheidungen.
    case failed(String)
}

/// Fragt GitHub nach dem neuesten Release.
///
/// Wird von der Homebrew-Fassung benutzt, die sich nicht selbst erneuern darf
/// (siehe `InstallKind`), und von der Schaltflaeche "Check now", solange
/// Sparkle nicht zustaendig ist. Die DMG-Fassung laesst Sparkle pruefen -
/// zwei Wege, aber nur einer ist pro Installation aktiv.
///
/// Der Netzzugriff steckt hinter `Fetch`, damit die Auswertung ohne Netz
/// geprueft werden kann.
public struct UpdateCheck: Sendable {
    /// Laedt die Antwort zu einer Adresse.
    public typealias Fetch = @Sendable (URL) async throws -> Data

    public static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/Silvertree2010/ApolloShell/releases/latest")!

    private let fetch: Fetch
    private let url: URL

    public init(url: URL = UpdateCheck.latestReleaseURL, fetch: @escaping Fetch) {
        self.url = url
        self.fetch = fetch
    }

    /// Fragt nach und vergleicht mit `current`.
    public func run(current: AppVersion?) async -> UpdateCheckOutcome {
        do {
            let data = try await fetch(url)
            guard let release = Self.release(from: data) else {
                return .failed(String(localized: "The reply from GitHub could not be read."))
            }
            guard let current else { return .newer(release) }
            return release.version > current ? .newer(release) : .current
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Liest `tag_name` und `html_url` aus der Antwort der GitHub-API.
    /// Entwuerfe und Vorabfassungen werden uebergangen: GitHub liefert unter
    /// `releases/latest` ohnehin nur fertige, aber verlassen wollen wir uns
    /// darauf nicht.
    public static func release(from data: Data) -> ReleaseInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if object["draft"] as? Bool == true || object["prerelease"] as? Bool == true { return nil }
        guard let tag = object["tag_name"] as? String, let version = AppVersion(tag) else { return nil }
        let page = (object["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/Silvertree2010/ApolloShell/releases/latest")!
        return ReleaseInfo(version: version, page: page)
    }

    /// Die Vorgabe: echter Netzzugriff, mit Kennung und kurzem Zeitlimit.
    public static func live(session: URLSession = .shared) -> UpdateCheck {
        UpdateCheck { url in
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("ApolloShell", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }
    }
}
