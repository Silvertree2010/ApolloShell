import Foundation

// The Marketplace as the app sees it: the types the server sends, a client
// for its API and the GitHub device flow for signing in. No UI here, and no
// Keychain - the app keeps the session and hands it in.

// MARK: - Types

public struct MarketUser: Codable, Equatable, Sendable {
    public let id: String
    public let login: String
    public let avatarURL: String?
    public let isAdmin: Bool
}

/// A theme as the Marketplace lists it. `css` is the live version in the
/// canonical form (`ThemeCanonical`).
public struct MarketTheme: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let slug: String
    public let name: String
    public let description: String
    public let author: String
    public let license: String
    public let attribution: String
    public let version: Int
    public let updatedAt: String
    public let css: String

    public init(id: String, slug: String, name: String, description: String, author: String,
                license: String, attribution: String, version: Int, updatedAt: String, css: String) {
        self.id = id
        self.slug = slug
        self.name = name
        self.description = description
        self.author = author
        self.license = license
        self.attribution = attribution
        self.version = version
        self.updatedAt = updatedAt
        self.css = css
    }
}

/// One of the signed-in user's own themes, with where it stands.
public struct MarketOwnTheme: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending, published, rejected, hidden
    }

    public let id: String
    public let slug: String
    public let name: String
    public let description: String
    public let author: String
    public let license: String
    public let attribution: String
    public let version: Int
    public let updatedAt: String
    public let css: String
    public let status: Status
    public let reason: String?
    public let liveVersion: Int?

    public var theme: MarketTheme {
        MarketTheme(id: id, slug: slug, name: name, description: description, author: author,
                    license: license, attribution: attribution, version: version,
                    updatedAt: updatedAt, css: css)
    }
}

public struct MarketReport: Codable, Equatable, Sendable {
    public let reason: String
    public let at: String
}

public struct MarketQueueItem: Codable, Equatable, Identifiable, Sendable {
    public let theme: MarketOwnTheme
    /// GitHub id of the author, for banning.
    public let ownerID: String?
    public let reports: [MarketReport]
    public let previousCSS: String?
    public var id: String { "\(theme.id)-\(theme.version)" }
}

/// What went wrong, with the server's own sentence when it sent one.
public enum MarketError: Error, Equatable, Sendable, LocalizedError {
    case server(code: String, message: String, status: Int)
    case unreadable(status: Int)
    case offline(String)

    public var code: String? {
        if case let .server(code, _, _) = self { return code }
        return nil
    }

    public var errorDescription: String? {
        switch self {
        case let .server(_, message, _): message
        case let .unreadable(status): "The Marketplace answered with something unexpected (\(status))."
        case let .offline(detail): "The Marketplace cannot be reached right now. \(detail)"
        }
    }
}

// MARK: - Client

/// Sends one request and returns the body and the status code.
public struct MarketTransport: Sendable {
    let send: @Sendable (URLRequest) async throws -> (Data, Int)

    public init(_ send: @escaping @Sendable (URLRequest) async throws -> (Data, Int)) {
        self.send = send
    }

    public static func live(session: URLSession = .shared) -> MarketTransport {
        MarketTransport { request in
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
}

public struct MarketplaceClient: Sendable {
    public static let productionURL = URL(string: "https://apolloshell-market.pages.dev")!

    public let baseURL: URL
    public var session: String?
    let transport: MarketTransport

    public init(baseURL: URL = MarketplaceClient.productionURL, session: String? = nil,
                transport: MarketTransport = .live()) {
        self.baseURL = baseURL
        self.session = session
        self.transport = transport
    }

    // Public
    public func themes() async throws -> [MarketTheme] {
        try await call("GET", "themes", as: ThemeList.self).themes
    }

    public func report(themeID: String, reason: String) async throws {
        try await call("POST", "themes/\(themeID)/report", body: ["reason": reason])
    }

    // Account
    public struct SignIn: Codable, Sendable {
        public let session: String
        public let user: MarketUser
    }

    public func signIn(gitHubToken: String) async throws -> SignIn {
        try await call("POST", "auth/github", body: ["accessToken": gitHubToken], as: SignIn.self)
    }

    public func me() async throws -> MarketUser { try await call("GET", "me", as: MarketUser.self) }
    public func signOut() async throws { try await call("POST", "auth/logout") }
    public func deleteAccount() async throws { try await call("DELETE", "me") }

    // Own themes
    public func mine() async throws -> [MarketOwnTheme] {
        try await call("GET", "mine", as: OwnList.self).themes
    }

    public func submit(css: String) async throws -> MarketOwnTheme {
        try await call("POST", "themes", body: ["css": css], as: MarketOwnTheme.self)
    }

    public func update(themeID: String, css: String) async throws -> MarketOwnTheme {
        try await call("PUT", "themes/\(themeID)", body: ["css": css], as: MarketOwnTheme.self)
    }

    public func delete(themeID: String) async throws { try await call("DELETE", "themes/\(themeID)") }

    // Admin
    public func queue() async throws -> [MarketQueueItem] {
        try await call("GET", "admin/queue", as: Queue.self).items
    }

    public enum Decision: String, Sendable { case approve, reject, hide, unhide }

    public func decide(_ decision: Decision, themeID: String, reason: String = "") async throws {
        let body: [String: String]? = reason.isEmpty ? nil : ["reason": reason]
        try await call("POST", "admin/themes/\(themeID)/\(decision.rawValue)", body: body)
    }

    public func ban(userID: String, reason: String) async throws {
        try await call("POST", "admin/users/\(userID)/ban", body: ["reason": reason])
    }

    // MARK: Plumbing

    private struct ThemeList: Decodable { let themes: [MarketTheme] }
    private struct OwnList: Decodable { let themes: [MarketOwnTheme] }
    private struct Queue: Decodable { let items: [MarketQueueItem] }
    private struct Failure: Decodable { let error: String; let message: String }

    public func request(_ method: String, _ path: String, body: [String: String]? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/" + path), timeoutInterval: 20)
        request.httpMethod = method
        // The edge caches the public list; the app always asks fresh, or
        // an approved or updated theme would stay invisible for a minute.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ApolloShell", forHTTPHeaderField: "User-Agent")
        if let session { request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func call(_ method: String, _ path: String, body: [String: String]? = nil) async throws {
        _ = try await send(method, path, body: body)
    }

    private func call<T: Decodable>(_ method: String, _ path: String, body: [String: String]? = nil,
                                    as type: T.Type) async throws -> T {
        let (data, status) = try await send(method, path, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MarketError.unreadable(status: status)
        }
    }

    /// The body of a successful answer; the server's error otherwise.
    private func send(_ method: String, _ path: String, body: [String: String]?) async throws -> (Data, Int) {
        let data: Data
        let status: Int
        do {
            (data, status) = try await transport.send(request(method, path, body: body))
        } catch {
            throw MarketError.offline(error.localizedDescription)
        }
        guard (200..<300).contains(status) else {
            if let failure = try? JSONDecoder().decode(Failure.self, from: data) {
                throw MarketError.server(code: failure.error, message: failure.message, status: status)
            }
            throw MarketError.unreadable(status: status)
        }
        return (data, status)
    }
}

// MARK: - GitHub sign-in

/// GitHub's device flow: the app shows a code, the user confirms it on
/// github.com, the app polls until GitHub hands out a token. No scopes, so
/// the token can read the public profile and nothing else. It goes to the
/// Marketplace once and is then thrown away.
public struct GitHubDeviceFlow: Sendable {
    /// The client id of the "ApolloShell Marketplace" OAuth app. Public by
    /// design: the device flow has no secret.
    public static let clientID = "Ov23liuDNoG1U7DcGF5q"

    public struct Code: Equatable, Sendable {
        public let deviceCode: String
        public let userCode: String
        public let verificationURL: URL
        public let interval: Int
        public let expiresIn: Int
    }

    public enum Poll: Equatable, Sendable {
        case token(String)
        case pending
        case slowDown
        case expired
        case denied
        case failed(String)
    }

    let clientID: String
    let transport: MarketTransport

    public init(clientID: String = GitHubDeviceFlow.clientID, transport: MarketTransport = .live()) {
        self.clientID = clientID
        self.transport = transport
    }

    public var isConfigured: Bool { !clientID.isEmpty }

    public func start() async throws -> Code {
        let (data, status) = try await transport.send(form("https://github.com/login/device/code",
                                                           ["client_id": clientID]))
        guard (200..<300).contains(status),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceCode = object["device_code"] as? String,
              let userCode = object["user_code"] as? String,
              let uri = (object["verification_uri"] as? String).flatMap(URL.init(string:))
        else { throw MarketError.unreadable(status: status) }
        return Code(deviceCode: deviceCode, userCode: userCode, verificationURL: uri,
                    interval: object["interval"] as? Int ?? 5,
                    expiresIn: object["expires_in"] as? Int ?? 900)
    }

    public func poll(_ code: Code) async -> Poll {
        do {
            let (data, _) = try await transport.send(form("https://github.com/login/oauth/access_token", [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ]))
            return Self.poll(from: data)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public static func poll(from data: Data) -> Poll {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed("GitHub answered with something unexpected.")
        }
        if let token = object["access_token"] as? String, !token.isEmpty { return .token(token) }
        switch object["error"] as? String {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "expired_token": return .expired
        case "access_denied": return .denied
        case let other: return .failed(other ?? "unknown")
        }
    }

    private func form(_ url: String, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }
}

// MARK: - Installing

/// Which Marketplace themes sit in the theme folder, and as which file.
/// Kept next to the folder (not in it), so the loader never sees it.
public struct MarketInstallIndex: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var fileName: String
        public var version: Int

        public init(fileName: String, version: Int) {
            self.fileName = fileName
            self.version = version
        }
    }

    public var entries: [String: Entry] = [:]

    public init(entries: [String: Entry] = [:]) { self.entries = entries }

    public static func load(from url: URL) -> MarketInstallIndex {
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(MarketInstallIndex.self, from: data)
        else { return MarketInstallIndex() }
        return index
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

public enum MarketInstall {
    /// The file as it lands in the theme folder: a comment with where it
    /// came from, the author put back (the Marketplace keeps it out of the
    /// canonical form), then the canonical CSS.
    public static func fileContents(for theme: MarketTheme) -> String {
        func comment(_ text: String) -> String {
            ThemeCanonical.cleanText(text).replacingOccurrences(of: "*/", with: "* /")
        }
        var header = "/* \(comment(theme.name)) by \(comment(theme.author)), from the ApolloShell Marketplace.\n"
        header += " * License: \(comment(theme.license))"
        if !theme.attribution.isEmpty { header += ". \(comment(theme.attribution))" }
        header += " */\n\n"
        let author = "  --apollo-theme-author: \"\(ThemeCanonical.cleanText(theme.author))\";\n"
        var css = theme.css
        if let range = css.range(of: ":root {\n") {
            css.insert(contentsOf: author, at: range.upperBound)
        } else {
            css = ":root {\n" + author + "}\n\n" + css
        }
        return header + css
    }

    /// A file name from the theme's name: letters, digits, spaces and
    /// dashes, never empty, never a path.
    public static func fileName(for theme: MarketTheme) -> String {
        let kept = theme.name.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-"
        }
        let base = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        return (base.isEmpty ? "Marketplace theme" : String(base.prefix(64))) + ".css"
    }
}
