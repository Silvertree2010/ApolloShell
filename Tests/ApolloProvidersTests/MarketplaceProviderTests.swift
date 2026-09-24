import Foundation
import Testing
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
final class FakeMarketplaceHost: MarketplaceHost {
    let root: URL
    let installer: MarketThemeInstaller
    var baseURL = URL(string: "https://market.test")!
    var activeTheme: String?
    var session: String?
    var opened: [URL] = []
    var copied: [String] = []
    var changed: [String?] = []

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("market-provider-\(UUID().uuidString)")
        installer = MarketThemeInstaller(themes: root.appendingPathComponent("config/themes"), legacyThemes: root.appendingPathComponent("support/themes"), indexFile: root.appendingPathComponent("support/marketplace.json"))
        try FileManager.default.createDirectory(at: installer.themes, withIntermediateDirectories: true)
    }

    func loadSession() -> String? { session }
    func saveSession(_ session: String) { self.session = session }
    func deleteSession() { session = nil }
    func open(_ url: URL) { opened.append(url) }
    func copy(_ text: String) { copied.append(text) }
    func localThemes() -> [Theme] { ThemeLoader.themes(in: installer.themes) }
    func selectTheme(_ id: String?) throws { activeTheme = id }
    func themesChanged(identifier: String?) { changed.append(identifier) }

    func writeLocal(_ name: String, _ css: String) throws {
        try css.write(to: installer.themes.appendingPathComponent(name + ".css"), atomically: true, encoding: .utf8)
    }
}

final class MarketFake: @unchecked Sendable {
    static let css = ":root {\n  --apollo-theme-name: \"Dusk\";\n  --apollo-accent-color: #ff8a3d;\n}\n"
    private let lock = NSLock()
    private var log: [String] = []
    private var bodies: [String: [String: Any]] = [:]
    var themesAnswer: (Int, String)
    var failAll = false

    init() {
        themesAnswer = (200, Self.json(["themes": [Self.theme(), Self.theme(id: "bad", slug: "../x", name: "Bad")]]))
    }

    static let pictures = ":root {\n  --apollo-theme-name: \"Pics\";\n  --apollo-wallpaper: url(\"x.png\");\n}\n"

    static func theme(id: String = "t1", slug: String = "dusk", name: String = "Dusk", version: Int = 2, css: String = css) -> [String: Any] {
        ["id": id, "slug": slug, "name": name, "description": "Warm", "author": "octo", "license": "CC0-1.0",
         "attribution": "", "version": version, "updatedAt": "2026-09-21T12:00:00Z", "css": css]
    }

    static func json(_ object: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    var requests: [String] {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    func body(_ key: String) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return bodies[key]
    }

    var transport: MarketTransport {
        MarketTransport { request in self.answer(request) }
    }

    func answer(_ request: URLRequest) -> (Data, Int) {
        let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
        lock.lock()
        log.append(key)
        if let body = request.httpBody, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] { bodies[key] = object }
        lock.unlock()
        if failAll { return (Data(Self.json(["error": "server_error", "message": "Down for a moment."]).utf8), 503) }
        let own = Self.theme().merging(["status": "pending", "reason": NSNull(), "liveVersion": NSNull()]) { _, new in new }
        let (status, text): (Int, String) = switch key {
        case "GET /api/v1/themes": themesAnswer
        case "POST /login/device/code": (200, Self.json(["device_code": "dev", "user_code": "ABCD-1234", "verification_uri": "https://github.com/login/device", "interval": 5, "expires_in": 900]))
        case "POST /login/oauth/access_token": (200, Self.json(["access_token": "gho_ok"]))
        case "POST /api/v1/auth/github": (200, Self.json(["session": "s3cret", "user": ["id": "42", "login": "octo", "avatarURL": "", "isAdmin": true]]))
        case "GET /api/v1/me": (200, Self.json(["id": "42", "login": "octo", "avatarURL": "", "isAdmin": true]))
        case "GET /api/v1/mine": (200, Self.json(["themes": [
            Self.theme().merging(["status": "rejected", "reason": "Copy", "liveVersion": 1]) { _, new in new },
            Self.theme(id: "t9", slug: "pics", name: "Pics", css: Self.pictures).merging(["status": "pending", "reason": NSNull(), "liveVersion": NSNull()]) { _, new in new },
        ]]))
        case "GET /api/v1/admin/queue": (200, Self.json(["items": [
            ["theme": own, "ownerID": "7", "reports": [["reason": "spam", "at": "2026-09-22"]], "previousCSS": Self.css],
            ["theme": Self.theme(id: "t9", slug: "pics", name: "Pics", css: Self.pictures).merging(["status": "pending", "reason": NSNull(), "liveVersion": NSNull()]) { _, new in new }, "ownerID": "7", "reports": [], "previousCSS": NSNull()],
        ]]))
        case "POST /api/v1/themes": (200, Self.json(own))
        case "PUT /api/v1/themes/t1": (200, Self.json(own.merging(["status": "published"]) { _, new in new }))
        case "POST /api/v1/themes/t1/report": (403, Self.json(["error": "rate_limited", "message": "Too many reports today."]))
        default: (204, "")
        }
        return (Data(text.utf8), status)
    }
}

@MainActor
@Suite("Provider marketplace")
struct MarketplaceProviderTests {
    @MainActor
    struct Setup {
        let harness: ProviderHarness
        let host: FakeMarketplaceHost
        let fake = MarketFake()
        let provider: MarketplaceProvider

        init() throws {
            harness = ProviderHarness()
            host = try FakeMarketplaceHost()
            provider = MarketplaceProvider(host: host, transport: fake.transport, clock: harness.clock)
            harness.register(provider)
            harness.demand("marketplace")
        }

        func run(_ action: String, _ arguments: [Value] = [], _ properties: Record = Record()) async throws {
            _ = try await harness.perform("marketplace", action, arguments, properties: properties)
        }

        func field(_ name: String) -> Value { harness.value("marketplace", name) }

        func item(_ index: Int = 0) -> Record {
            guard case .list(let items) = field("items"), items.indices.contains(index), case .record(let record) = items[index] else { return Record() }
            return record
        }
    }

    @Test("starts idle and conforms to the registry")
    func idle() throws {
        let setup = try Setup()
        #expect(setup.field("status") == .string("idle"))
        #expect(setup.harness.conformanceProblems(BuiltinProviderSchemas.schema("marketplace"), strict: true).isEmpty)
    }

    @Test("refresh loads items with state and leaves out broken entries")
    func refresh() async throws {
        let setup = try Setup()
        try await setup.run("refresh")
        #expect(setup.field("status") == .string("loaded"))
        guard case .list(let items) = setup.field("items") else { Issue.record("no items"); return }
        #expect(items.count == 1)
        let item = setup.item()
        #expect(item["kind"] == .string("theme"))
        #expect(item["state"] == .string("get"))
        #expect(item["css"] == .string(MarketFake.css))
        #expect(item["updated"] == .string("2026-09-21T12:00:00Z"))
        #expect(setup.harness.conformanceProblems(BuiltinProviderSchemas.schema("marketplace"), strict: true).isEmpty)
    }

    @Test("failed load: status failed with load-error, action errors stay apart in error, Try again recovers")
    func failed() async throws {
        let setup = try Setup()
        setup.fake.themesAnswer = (500, "<html>")
        try await setup.run("refresh")
        #expect(setup.field("status") == .string("failed"))
        #expect(setup.field("load-error") != .null)
        #expect(setup.field("error") == .null)
        try await setup.run("report", [.string("t1"), .string("copied")])
        #expect(setup.field("error") == .string("Too many reports today."))
        #expect(setup.field("load-error") != .null)
        #expect(setup.field("status") == .string("failed"))
        setup.fake.themesAnswer = (200, MarketFake.json(["themes": []]))
        try await setup.run("refresh")
        #expect(setup.field("status") == .string("loaded"))
        #expect(setup.field("load-error") == .null)
        #expect(setup.field("error") == .string("Too many reports today."))
        #expect(setup.field("items") == .list([]))
    }

    @Test("get, update, use and remove go through the installer and the host")
    func install() async throws {
        let setup = try Setup()
        try await setup.run("refresh")
        try await setup.run("get", [.string("t1")])
        #expect(setup.item()["state"] == .string("use"))
        #expect(setup.host.changed == ["dusk"])
        try await setup.run("use", [.string("t1")])
        #expect(setup.host.activeTheme == "dusk")
        try await setup.run("remove", [.string("t1")])
        #expect(setup.host.activeTheme == nil)
        #expect(setup.item()["state"] == .string("get"))
        try await setup.run("use", [.string("t1")])
        #expect(setup.host.activeTheme == "dusk")
        #expect(setup.item()["state"] == .string("use"))
    }

    @Test("sign-in: device code, browser, copy, poll, session in the host; sign-out forgets it")
    func signIn() async throws {
        let setup = try Setup()
        try await setup.run("sign-in")
        for _ in 0..<20 where setup.host.opened.isEmpty { await Task.yield() }
        setup.harness.flush()
        #expect(setup.host.opened == [URL(string: "https://github.com/login/device")!])
        guard case .record(let waiting) = setup.field("sign-in") else { Issue.record("no sign-in"); return }
        #expect(waiting["status"] == .string("waiting"))
        #expect(waiting["code"] == .string("ABCD-1234"))
        try await setup.run("copy-code")
        #expect(setup.host.copied == ["ABCD-1234"])
        setup.harness.advance(5)
        for _ in 0..<50 where setup.host.session == nil { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        setup.harness.flush()
        #expect(setup.host.session == "s3cret")
        guard case .record(let user) = setup.field("user") else { Issue.record("no user"); return }
        #expect(user["login"] == .string("octo"))
        #expect(user["is-admin"] == .bool(true))
        #expect(setup.fake.body("POST /api/v1/auth/github")?["accessToken"] as? String == "gho_ok")
        try await setup.run("sign-out")
        #expect(setup.host.session == nil)
        #expect(setup.field("user") == .null)
    }

    @Test("cancel stops a waiting sign-in")
    func cancel() async throws {
        let setup = try Setup()
        try await setup.run("sign-in")
        for _ in 0..<20 where setup.host.opened.isEmpty { await Task.yield() }
        try await setup.run("cancel-sign-in")
        setup.harness.advance(6)
        for _ in 0..<20 { await Task.yield() }
        #expect(setup.host.session == nil)
        #expect(!setup.fake.requests.contains("POST /login/oauth/access_token"))
        guard case .record(let state) = setup.field("sign-in") else { return }
        #expect(state["status"] == .string("idle"))
    }

    @Test("mine and queue for an admin with a stored session")
    func account() async throws {
        let setup = try Setup()
        setup.host.session = "s3cret"
        try await setup.run("refresh")
        guard case .list(let mine) = setup.field("mine"), case .record(let own) = mine.first else { Issue.record("no mine"); return }
        #expect(own["status"] == .string("rejected"))
        #expect(own["reason"] == .string("Copy"))
        #expect(own["live-version"] == .number(1))
        guard case .list(let queue) = setup.field("queue"), case .record(let entry) = queue.first else { Issue.record("no queue"); return }
        #expect(entry["update-note"] == .string("Update: name or description changed."))
        #expect(entry["owner-id"] == .string("7"))
        guard case .list(let reports) = entry["reports"] ?? .null, case .record(let report) = reports.first else { Issue.record("no reports"); return }
        #expect(report["reason"] == .string("spam"))
        try await setup.run("approve", [.string("t1"), .string("2")])
        #expect(setup.fake.body("POST /api/v1/admin/themes/t1/approve")?["version"] as? Int == 2)
        try await setup.run("reject", [.string("t1"), .string("2"), .string("Copy")])
        #expect(setup.fake.body("POST /api/v1/admin/themes/t1/reject")?["reason"] as? String == "Copy")
        try await setup.run("hide", [.string("t1"), .string("Reported")])
        try await setup.run("unhide", [.string("t1")])
        try await setup.run("ban", [.string("7"), .string("Spam")])
        #expect(setup.fake.requests.contains("POST /api/v1/admin/users/7/ban"))
        await #expect(throws: ProviderActionError.self) { try await setup.run("reject", [.string("t1"), .string("2"), .string("  ")]) }
        try await setup.run("delete-account")
        #expect(setup.host.session == nil)
    }

    @Test("submit needs accepted terms, refuses themes with images or without a name, and reports success")
    func submit() async throws {
        let setup = try Setup()
        setup.host.session = "s3cret"
        try setup.host.writeLocal("mine", MarketFake.css)
        try setup.host.writeLocal("pictures", ":root {\n  --apollo-theme-name: \"P\";\n  --apollo-wallpaper: url(\"x.png\");\n}\n")
        try setup.host.writeLocal("nameless", ":root {\n  --apollo-accent-color: #ff8a3d;\n}\n")
        try await setup.run("refresh")
        guard case .list(let local) = setup.field("local") else { Issue.record("no local"); return }
        let problems = Dictionary(uniqueKeysWithValues: local.compactMap { value -> (String, Value)? in
            guard case .record(let record) = value, case .string(let id) = record["id"] ?? .null else { return nil }
            return (id, record["problem"] ?? .null)
        })
        #expect(problems["mine"] == .null)
        #expect(problems["nameless"] == .string("no-name"))
        await #expect(throws: ProviderActionError.self) { try await setup.run("submit", [.string("mine")]) }
        try await setup.run("submit", [.string("nameless")], Record([("accept-terms", .bool(true))]))
        #expect(setup.field("error") == .string("Give it a name first: --apollo-theme-name in the file."))
        try await setup.run("dismiss")
        #expect(setup.field("error") == .null)
        try await setup.run("submit", [.string("mine")], Record([("accept-terms", .bool(true))]))
        #expect(setup.field("message") == .string("Dusk is waiting for review."))
        #expect(setup.fake.body("POST /api/v1/themes")?["css"] as? String == MarketFake.css)
        try await setup.run("new-version", [.string("t1"), .string("mine")], Record([("accept-terms", .bool(true))]))
        #expect(setup.field("message") == .string("Dusk is updated."))
        try await setup.run("delete", [.string("t1")])
        #expect(setup.fake.requests.contains("DELETE /api/v1/themes/t1"))
    }

    @Test("mine and queue: only entries that pass the installer check keep their css for the preview")
    func previewChecked() async throws {
        let setup = try Setup()
        setup.host.session = "s3cret"
        try await setup.run("refresh")
        guard case .list(let mine) = setup.field("mine"), case .list(let queue) = setup.field("queue") else { Issue.record("no lists"); return }
        let css = { (list: [Value]) -> [String: Value] in
            Dictionary(uniqueKeysWithValues: list.compactMap { value -> (String, Value)? in
                guard case .record(let record) = value, case .string(let id) = record["id"] ?? .null else { return nil }
                return (id, record["css"] ?? .null)
            })
        }
        #expect(css(mine) == ["t1": .string(MarketFake.css), "t9": .string("")])
        #expect(css(queue) == ["t1": .string(MarketFake.css), "t9": .string("")])
    }

    @Test("action errors land in error, report success in message")
    func messages() async throws {
        let setup = try Setup()
        try await setup.run("refresh")
        try await setup.run("report", [.string("t1"), .string("copied")])
        #expect(setup.field("error") == .string("Too many reports today."))
        #expect(setup.field("status") == .string("loaded"))
        setup.fake.failAll = true
        try await setup.run("refresh")
        #expect(setup.field("status") == .string("loaded"))
    }
}
