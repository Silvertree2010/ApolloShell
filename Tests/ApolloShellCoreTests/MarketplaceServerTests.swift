#if canImport(Network)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ApolloShellCore

enum FakeMarket {
    static let css = ":root {\n  --apollo-theme-name: \"Dusk\";\n  --apollo-accent-color: #ff8a3d;\n}\n"

    static func theme(id: String = "t1", slug: String = "dusk", name: String = "Dusk", version: Int = 2) -> [String: Any] {
        ["id": id, "slug": slug, "name": name, "description": "Warm", "author": "octo", "license": "CC0-1.0",
         "attribution": "", "version": version, "updatedAt": "2026-09-21T12:00:00Z", "css": css]
    }

    static func own(status: String, reason: Any = NSNull(), live: Any = NSNull()) -> [String: Any] {
        theme().merging(["status": status, "reason": reason, "liveVersion": live]) { _, new in new }
    }

    static func json(_ object: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!
    }

    static var user: [String: Any] { ["id": "42", "login": "octo", "avatarURL": "https://example.invalid/a.png", "isAdmin": true] }

    static func route(_ exchange: HTTPExchange) -> HTTPAnswer {
        let authorized = exchange.headers["authorization"] == "Bearer s3cret"
        let path = exchange.path
        switch (exchange.method, path) {
        case ("GET", "/api/v1/themes"):
            return HTTPAnswer(200, json(["themes": [theme()]]))
        case ("POST", "/api/v1/themes/t1/report"):
            return HTTPAnswer(204)
        case ("POST", "/api/v1/auth/github"):
            guard exchange.json?["accessToken"] as? String == "gho_ok" else {
                return HTTPAnswer(403, json(["error": "account_too_new", "message": "Your GitHub account is too new."]))
            }
            return HTTPAnswer(200, json(["session": "s3cret", "user": user]))
        default:
            break
        }
        guard authorized else { return HTTPAnswer(401, json(["error": "unauthorized", "message": "Sign in again."])) }
        switch (exchange.method, path) {
        case ("GET", "/api/v1/me"): return HTTPAnswer(200, json(user))
        case ("POST", "/api/v1/auth/logout"), ("DELETE", "/api/v1/me"), ("DELETE", "/api/v1/themes/t1"): return HTTPAnswer(204)
        case ("GET", "/api/v1/mine"): return HTTPAnswer(200, json(["themes": [own(status: "rejected", reason: "Copy of Nord", live: 1)]]))
        case ("POST", "/api/v1/themes"):
            guard exchange.json?["css"] as? String == css else { return HTTPAnswer(422, json(["error": "invalid_theme", "message": "Line 1 is not canonical."])) }
            return HTTPAnswer(200, json(own(status: "pending")))
        case ("PUT", "/api/v1/themes/t1"): return HTTPAnswer(200, json(own(status: "published", live: 3)))
        case ("GET", "/api/v1/admin/queue"):
            return HTTPAnswer(200, json(["items": [["theme": own(status: "pending"), "ownerID": "7", "reports": [["reason": "spam", "at": "2026-09-22"]], "previousCSS": css]]]))
        case ("POST", "/api/v1/admin/themes/t1/approve"), ("POST", "/api/v1/admin/themes/t1/reject"),
             ("POST", "/api/v1/admin/themes/t1/hide"), ("POST", "/api/v1/admin/themes/t1/unhide"),
             ("POST", "/api/v1/admin/users/7/ban"):
            return HTTPAnswer(204)
        case ("GET", "/api/v1/broken"):
            return HTTPAnswer(500, "<html>oops</html>")
        default:
            return HTTPAnswer(404, json(["error": "not_found", "message": "Not found."]))
        }
    }
}

@Suite("Marketplace client against a local HTTP server", .serialized)
struct MarketplaceServerTests {
    static func withServer(_ body: (URL, LocalHTTPServer) async throws -> Void) async throws {
        let server = try LocalHTTPServer(route: FakeMarket.route)
        let url = try await server.start()
        defer { server.stop() }
        try await body(url, server)
    }

    static func client(_ url: URL, session: String? = nil) -> MarketplaceClient {
        MarketplaceClient(baseURL: url, session: session, transport: .live(session: URLSession(configuration: .ephemeral)))
    }

    @Test("public routes: list and report, without a session header")
    func publicRoutes() async throws {
        try await Self.withServer { url, server in
            let client = Self.client(url)
            let themes = try await client.themes()
            #expect(themes.map(\.slug) == ["dusk"])
            #expect(themes.first?.version == 2)
            try await client.report(themeID: "t1", reason: "copied")
            let log = server.exchanges
            #expect(log.map { "\($0.method) \($0.path)" } == ["GET /api/v1/themes", "POST /api/v1/themes/t1/report"])
            #expect(log.allSatisfy { $0.headers["authorization"] == nil })
            #expect(log.allSatisfy { $0.headers["user-agent"] == "ApolloShell" })
            #expect(log[1].json?["reason"] as? String == "copied")
        }
    }

    @Test("sign-in hands the GitHub token over once and then sends the session")
    func signInAndAccount() async throws {
        try await Self.withServer { url, server in
            var client = Self.client(url)
            let result = try await client.signIn(gitHubToken: "gho_ok")
            #expect(result.session == "s3cret")
            #expect(result.user.isAdmin)
            client.session = result.session
            #expect(try await client.me().login == "octo")
            let mine = try await client.mine()
            #expect(mine.first?.status == .rejected)
            #expect(mine.first?.reason == "Copy of Nord")
            #expect(mine.first?.liveVersion == 1)
            try await client.signOut()
            try await client.deleteAccount()
            let log = server.exchanges
            #expect(log.first?.json?["accessToken"] as? String == "gho_ok")
            #expect(log.dropFirst().allSatisfy { $0.headers["authorization"] == "Bearer s3cret" })
            #expect(!log.dropFirst().contains { String(data: $0.body, encoding: .utf8)?.contains("gho_ok") == true })
        }
    }

    @Test("submit, new version and delete of an own theme")
    func ownThemes() async throws {
        try await Self.withServer { url, server in
            let client = Self.client(url, session: "s3cret")
            #expect(try await client.submit(css: FakeMarket.css).status == .pending)
            let updated = try await client.update(themeID: "t1", css: FakeMarket.css)
            #expect(updated.status == .published)
            #expect(updated.liveVersion == 3)
            try await client.delete(themeID: "t1")
            #expect(server.exchanges.map { "\($0.method) \($0.path)" } == ["POST /api/v1/themes", "PUT /api/v1/themes/t1", "DELETE /api/v1/themes/t1"])
            #expect(server.exchanges[0].headers["content-type"] == "application/json")
        }
    }

    @Test("admin queue and every decision")
    func admin() async throws {
        try await Self.withServer { url, server in
            let client = Self.client(url, session: "s3cret")
            let queue = try await client.queue()
            #expect(queue.first?.ownerID == "7")
            #expect(queue.first?.reports.map(\.reason) == ["spam"])
            #expect(queue.first?.previousCSS == FakeMarket.css)
            try await client.decide(.approve, themeID: "t1", version: 2)
            try await client.decide(.reject, themeID: "t1", version: 2, reason: "Copy")
            try await client.decide(.hide, themeID: "t1", version: 2, reason: "Reported")
            try await client.decide(.unhide, themeID: "t1", version: 2)
            try await client.ban(userID: "7", reason: "Spam")
            let bodies = server.exchanges.dropFirst().map { $0.json ?? [:] }
            #expect(bodies.map { $0["version"] as? Int } == [2, 2, 2, 2, nil])
            #expect(bodies.map { $0["reason"] as? String } == [nil, "Copy", "Reported", nil, "Spam"])
        }
    }

    @Test("server errors become the server's sentence, garbage and offline their own")
    func errors() async throws {
        try await Self.withServer { url, _ in
            await #expect(throws: MarketError.server(code: "unauthorized", message: "Sign in again.", status: 401)) {
                try await Self.client(url).me()
            }
            await #expect(throws: MarketError.server(code: "invalid_theme", message: "Line 1 is not canonical.", status: 422)) {
                try await Self.client(url, session: "s3cret").submit(css: ":root {}\n")
            }
            await #expect(throws: MarketError.server(code: "account_too_new", message: "Your GitHub account is too new.", status: 403)) {
                try await Self.client(url).signIn(gitHubToken: "gho_new")
            }
        }
        let server = try LocalHTTPServer(route: { _ in HTTPAnswer(500, "<html>oops</html>") })
        let url = try await server.start()
        await #expect(throws: MarketError.unreadable(status: 500)) { try await Self.client(url).themes() }
        server.stop()
        try await Task.sleep(for: .milliseconds(100))
        do {
            _ = try await Self.client(url).themes()
            Issue.record("a stopped server answered")
        } catch let error as MarketError {
            guard case .offline = error else { Issue.record("expected offline, got \(error)"); return }
        }
    }
}
#endif
