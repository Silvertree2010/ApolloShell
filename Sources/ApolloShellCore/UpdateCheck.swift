import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let page: URL

    public init(version: AppVersion, page: URL) {
        self.version = version
        self.page = page
    }
}

public enum UpdateCheckOutcome: Equatable, Sendable {
    case current
    case newer(ReleaseInfo)
    case failed(String)
}

public struct UpdateCheck: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    public static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/Silvertree2010/ApolloShell/releases/latest")!

    private let fetch: Fetch
    private let url: URL

    public init(url: URL = UpdateCheck.latestReleaseURL, fetch: @escaping Fetch) {
        self.url = url
        self.fetch = fetch
    }

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

    public static func release(from data: Data) -> ReleaseInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if object["draft"] as? Bool == true || object["prerelease"] as? Bool == true { return nil }
        guard let tag = object["tag_name"] as? String, let version = AppVersion(tag) else { return nil }
        let page = (object["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/Silvertree2010/ApolloShell/releases/latest")!
        return ReleaseInfo(version: version, page: page)
    }

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
