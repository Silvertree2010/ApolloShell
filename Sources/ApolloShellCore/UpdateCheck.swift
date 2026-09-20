import Foundation

/// The newest release the way GitHub reports it.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    /// The page of the release with the notes.
    public let page: URL

    public init(version: AppVersion, page: URL) {
        self.version = version
        self.page = page
    }
}

/// What a check came up with.
public enum UpdateCheckOutcome: Equatable, Sendable {
    /// The running version is the newest one (or even newer).
    case current
    /// There is a newer version.
    case newer(ReleaseInfo)
    /// The check did not get through. The text is for the display, not for
    /// decisions.
    case failed(String)
}

/// Asks GitHub for the newest release.
///
/// Used by the Homebrew build, which may not renew itself (see `InstallKind`),
/// and by the "Check now" button while Sparkle is not in charge. The DMG build
/// lets Sparkle check - two ways, but only one is active per installation.
/// zwei Wege, aber nur einer ist pro Installation aktiv.
/// The network access sits behind `Fetch`, so that the evaluation can be
/// checked without a network.
///
public struct UpdateCheck: Sendable {
    /// Loads the answer for an address.
    public typealias Fetch = @Sendable (URL) async throws -> Data

    public static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/Silvertree2010/ApolloShell/releases/latest")!

    private let fetch: Fetch
    private let url: URL

    public init(url: URL = UpdateCheck.latestReleaseURL, fetch: @escaping Fetch) {
        self.url = url
        self.fetch = fetch
    }

    /// Asks and compares with `current`.
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

    /// Reads `tag_name` and `html_url` out of the answer of the GitHub API.
    /// Drafts and prereleases are passed over: GitHub delivers only finished
    /// ones under `releases/latest` anyway, but we do not want to rely on that.
    /// darauf nicht.
    public static func release(from data: Data) -> ReleaseInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if object["draft"] as? Bool == true || object["prerelease"] as? Bool == true { return nil }
        guard let tag = object["tag_name"] as? String, let version = AppVersion(tag) else { return nil }
        let page = (object["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/Silvertree2010/ApolloShell/releases/latest")!
        return ReleaseInfo(version: version, page: page)
    }

    /// The default: real network access, with the identifier and a short time limit.
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
