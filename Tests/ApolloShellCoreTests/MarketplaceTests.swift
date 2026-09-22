import Foundation
import Testing
@testable import ApolloShellCore

/// Records what the client sent and answers with a fixed body.
private final class FakeServer: @unchecked Sendable {
    var requests: [URLRequest] = []
    var answer: (Data, Int)

    init(_ body: String, status: Int = 200) {
        answer = (Data(body.utf8), status)
    }

    var transport: MarketTransport {
        MarketTransport { request in
            self.requests.append(request)
            return self.answer
        }
    }
}

private let themeJSON = """
{"id":"t1","slug":"dusk","name":"Dusk","description":"Warm","author":"octo",
 "license":"CC0-1.0","attribution":"","version":2,"updatedAt":"2026-09-21T12:00:00Z",
 "css":":root {\\n  --apollo-theme-name: \\"Dusk\\";\\n  --apollo-accent-color: #ff8a3d;\\n}\\n"}
"""

@Suite("Marketplace client")
struct MarketplaceClientTests {
    @Test("lists themes from /api/v1/themes")
    func listsThemes() async throws {
        let server = FakeServer(#"{"themes":[\#(themeJSON)]}"#)
        let client = MarketplaceClient(baseURL: URL(string: "https://market.test")!, transport: server.transport)
        let themes = try await client.themes()
        #expect(themes.map(\.name) == ["Dusk"])
        #expect(server.requests.first?.url?.absoluteString == "https://market.test/api/v1/themes")
        #expect(server.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(server.requests.first?.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("sends the session as a bearer token and the css as JSON")
    func submits() async throws {
        let own = themeJSON.dropLast(1) + #","status":"pending","reason":null,"liveVersion":null}"#
        let server = FakeServer(String(own))
        let client = MarketplaceClient(baseURL: URL(string: "https://market.test")!, session: "abc",
                                       transport: server.transport)
        let result = try await client.submit(css: ":root {}\n")
        #expect(result.status == .pending)
        let request = try #require(server.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(body == ["css": ":root {}\n"])
    }

    @Test("turns the server's error into its own sentence")
    func serverError() async {
        let server = FakeServer(#"{"error":"rate_limited","message":"Three uploads a day."}"#, status: 429)
        let client = MarketplaceClient(transport: server.transport)
        await #expect(throws: MarketError.server(code: "rate_limited", message: "Three uploads a day.", status: 429)) {
            try await client.submit(css: "")
        }
    }

    @Test("an empty 204 is fine for calls without an answer")
    func emptyAnswer() async throws {
        let server = FakeServer("", status: 204)
        let client = MarketplaceClient(transport: server.transport)
        try await client.report(themeID: "t1", reason: "spam")
        #expect(server.requests.first?.url?.path == "/api/v1/themes/t1/report")
    }

    @Test("approve names the version the admin reviewed")
    func approveSendsVersion() async throws {
        let server = FakeServer("", status: 204)
        let client = MarketplaceClient(session: "admin", transport: server.transport)
        try await client.decide(.approve, themeID: "t1", version: 3)
        let request = try #require(server.requests.first)
        #expect(request.url?.path == "/api/v1/admin/themes/t1/approve")
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["version"] as? Int == 3)
    }

    @Test("reads GitHub's device flow answers")
    func devicePoll() {
        #expect(GitHubDeviceFlow.poll(from: Data(#"{"access_token":"gho_x","token_type":"bearer"}"#.utf8)) == .token("gho_x"))
        #expect(GitHubDeviceFlow.poll(from: Data(#"{"error":"authorization_pending"}"#.utf8)) == .pending)
        #expect(GitHubDeviceFlow.poll(from: Data(#"{"error":"slow_down"}"#.utf8)) == .slowDown)
        #expect(GitHubDeviceFlow.poll(from: Data(#"{"error":"expired_token"}"#.utf8)) == .expired)
        #expect(GitHubDeviceFlow.poll(from: Data(#"{"error":"access_denied"}"#.utf8)) == .denied)
    }
}

@Suite("Installing Marketplace themes")
struct MarketInstallTests {
    private func theme(name: String = "Dusk", author: String = "octo",
                       css: String = ":root {\n  --apollo-accent-color: #ff8a3d;\n}\n") -> MarketTheme {
        MarketTheme(id: "t1", slug: "dusk", name: name, description: "", author: author,
                    license: "CC0-1.0", attribution: "", version: 1, updatedAt: "", css: css)
    }

    @Test("puts the author back and reads as a theme")
    func contentsLoad() {
        let text = MarketInstall.fileContents(for: theme())
        let loaded = Theme.make(identifier: "Dusk", styleSheet: ThemeStyleSheetParser.parse(text))
        #expect(loaded.author == "octo")
        #expect(loaded.value(ThemeColorToken.accent) == ThemeColor(hex: 0xFF8A3D))
    }

    @Test("a name cannot close the comment or smuggle in CSS")
    func hostileName() {
        let text = MarketInstall.fileContents(for: theme(name: "x */ :root { --apollo-accent-color: #000000; } /*"))
        let loaded = Theme.make(identifier: "x", styleSheet: ThemeStyleSheetParser.parse(text))
        #expect(loaded.value(ThemeColorToken.accent) == ThemeColor(hex: 0xFF8A3D))
    }

    @Test("file names stay plain")
    func fileNames() {
        #expect(MarketInstall.fileName(for: theme(name: "Dusk")) == "Dusk.css")
        #expect(MarketInstall.fileName(for: theme(name: "../../etc/passwd")) == "etcpasswd.css")
        #expect(MarketInstall.fileName(for: theme(name: "///")) == "Marketplace theme.css")
    }
}
