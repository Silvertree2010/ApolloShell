import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class MarketplaceProvider: BaseProvider {
    enum SignIn: Equatable {
        case idle
        case starting
        case waiting(GitHubDeviceFlow.Code)
        case done
        case failed(String)
    }

    static let updateNote = "Update: name or description changed."
    static let reportSent = "Thanks. The report was sent."

    private let host: any MarketplaceHost
    private let transport: MarketTransport
    private let flow: GitHubDeviceFlow
    private var client: MarketplaceClient
    private var sessionLoaded = false
    private var themes: [MarketTheme] = []
    private var status = "idle"
    private var loadError: String?
    private var actionError: String?
    private var message: String?
    private var user: MarketUser?
    private var mine: [MarketOwnTheme] = []
    private var queue: [MarketQueueItem] = []
    private var signIn = SignIn.idle
    private var signInGeneration = 0
    private var pollInterval = 5
    private var pollDeadline = Date.distantPast
    private var local: [Theme] = []
    private var refreshGeneration = 0

    public init(host: any MarketplaceHost, transport: MarketTransport = .live(), flow: GitHubDeviceFlow? = nil, clock: any RuntimeClock) {
        self.host = host
        self.transport = transport
        self.flow = flow ?? GitHubDeviceFlow(transport: transport)
        client = MarketplaceClient(baseURL: host.baseURL, transport: transport)
        super.init(schema: BuiltinProviderSchemas.schema("marketplace"), clock: clock)
    }

    override func didStart() {
        publishAll()
    }

    override func didStop() {
        signInGeneration += 1
        switch signIn {
        case .starting, .waiting: signIn = .idle
        case .idle, .done, .failed: break
        }
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        let action = arguments.action.hasPrefix("marketplace.") ? String(arguments.action.dropFirst("marketplace.".count)) : arguments.action
        loadSessionOnce()
        switch action {
        case "refresh":
            await refresh()
        case "get", "update":
            try install(try arguments.string(0), action: arguments.action)
        case "use":
            try use(try arguments.string(0), action: arguments.action)
        case "remove":
            try remove(try arguments.string(0), action: arguments.action)
        case "sign-in":
            startSignIn()
        case "cancel-sign-in":
            cancelSignIn()
        case "copy-code":
            if case .waiting(let code) = signIn { host.copy(code.userCode) }
        case "sign-out":
            await signOut()
        case "delete-account":
            await deleteAccount()
        case "submit":
            try await submit(try arguments.string(0), replacing: nil, arguments: arguments)
        case "new-version":
            try await submit(try arguments.string(1), replacing: try arguments.string(0), arguments: arguments)
        case "delete":
            await attempt { [self] in
                try await client.delete(themeID: try arguments.string(0))
                await refreshAll()
            }
        case "report":
            let id = try arguments.string(0)
            let reason = try arguments.string(1)
            await attempt { [self] in
                try await client.report(themeID: id, reason: reason)
                message = Self.reportSent
            }
        case "approve":
            try await decide(.approve, arguments, versionIndex: 1, reasonIndex: nil)
        case "reject":
            try await decide(.reject, arguments, versionIndex: 1, reasonIndex: 2)
        case "hide":
            try await decide(.hide, arguments, versionIndex: nil, reasonIndex: 1)
        case "unhide":
            try await decide(.unhide, arguments, versionIndex: nil, reasonIndex: nil)
        case "ban":
            let userID = try arguments.string(0)
            let reason = try Self.reason(arguments, 1)
            await attempt { [self] in
                try await client.ban(userID: userID, reason: reason)
                await refreshAll()
            }
        case "dismiss":
            message = nil
            actionError = nil
        case "open":
            throw ProviderActionError.unavailable(action: arguments.action, reason: "the shell opens the Marketplace window")
        default:
            throw ProviderActionError.unknownAction(arguments.action)
        }
        publishAll()
        return .null
    }

    private func loadSessionOnce() {
        guard !sessionLoaded else { return }
        sessionLoaded = true
        client.session = host.loadSession()
    }

    func refresh() async {
        loadSessionOnce()
        refreshGeneration += 1
        let generation = refreshGeneration
        if themes.isEmpty { status = "loading" }
        publishAll()
        do {
            let list = try await client.themes()
            guard generation == refreshGeneration else { return }
            themes = Self.usable(list) { [weak self] in self?.note($0) }
            status = "loaded"
            loadError = nil
            if actionError == Self.offlineNote { actionError = nil }
        } catch {
            guard generation == refreshGeneration else { return }
            if themes.isEmpty {
                status = "failed"
                loadError = error.localizedDescription
            } else {
                status = "loaded"
                actionError = Self.offlineNote
            }
        }
        local = host.localThemes()
        await refreshAccount()
        publishAll()
    }

    static func usable(_ list: [MarketTheme], note: (String) -> Void) -> [MarketTheme] {
        list.filter { theme in
            do {
                try MarketThemeInstaller.check(theme)
                return true
            } catch {
                note("marketplace: left out \"\(theme.name)\": \(error)")
                return false
            }
        }
    }

    func refreshAccount() async {
        guard client.session != nil else { return }
        do {
            user = try await client.me()
            mine = try await client.mine()
            queue = user?.isAdmin == true ? try await client.queue() : []
        } catch MarketError.server(code: "unauthorized", _, _) {
            forgetSession()
        } catch {
        }
    }

    private func refreshAll() async {
        await refreshAccount()
        await refresh()
    }

    private func attempt(_ work: @MainActor () async throws -> Void) async {
        do {
            try await work()
        } catch {
            actionError = Self.text(error)
        }
    }

    static let offlineNote = "Offline, list may be outdated."

    static func text(_ error: Error) -> String {
        if let problem = error as? MarketInstallProblem { return problem.description }
        if let failure = error as? ProviderActionError { return failure.description }
        return error.localizedDescription
    }

    private func theme(_ id: String, action: String) throws -> MarketTheme {
        guard let theme = themes.first(where: { $0.id == id }) else {
            throw ProviderActionError.invalidArgument(action: action, message: "no Marketplace theme with id \"\(id)\"")
        }
        return theme
    }

    private func install(_ id: String, action: String) throws {
        let theme = try theme(id, action: action)
        do {
            let identifier = try host.installer.install(theme)
            host.themesChanged(identifier: identifier)
            local = host.localThemes()
        } catch {
            actionError = Self.text(error)
        }
    }

    private func use(_ id: String, action: String) throws {
        let theme = try theme(id, action: action)
        do {
            if host.installer.state(of: theme) != .use {
                let identifier = try host.installer.install(theme)
                host.themesChanged(identifier: identifier)
            }
            guard let identifier = host.installer.installedIdentifier(of: theme.id) else { throw MarketInstallProblem.notInstalled }
            try host.selectTheme(identifier)
            local = host.localThemes()
        } catch {
            actionError = Self.text(error)
        }
    }

    private func remove(_ id: String, action: String) throws {
        do {
            if let identifier = host.installer.installedIdentifier(of: id), host.activeTheme == identifier {
                try host.selectTheme(nil)
            }
            let identifier = try host.installer.remove(id)
            host.themesChanged(identifier: identifier)
            local = host.localThemes()
        } catch {
            actionError = Self.text(error)
        }
    }

    private func startSignIn() {
        switch signIn {
        case .starting, .waiting: return
        case .idle, .done, .failed: break
        }
        guard flow.isConfigured else {
            signIn = .failed("Sign-in is not set up in this build yet.")
            return
        }
        signInGeneration += 1
        let generation = signInGeneration
        signIn = .starting
        publishAll()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let code = try await self.flow.start()
                guard generation == self.signInGeneration else { return }
                self.signIn = .waiting(code)
                self.pollInterval = max(1, code.interval)
                self.pollDeadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
                self.host.open(code.verificationURL)
                self.publishAll()
                self.schedulePoll(code, generation: generation)
            } catch {
                guard generation == self.signInGeneration else { return }
                self.signIn = .failed(Self.text(error))
                self.publishAll()
            }
        }
    }

    private func schedulePoll(_ code: GitHubDeviceFlow.Code, generation: Int) {
        timers.once("sign-in", after: Double(pollInterval)) { [weak self] in
            guard let self, generation == self.signInGeneration else { return }
            Task { @MainActor [weak self] in await self?.poll(code, generation: generation) }
        }
    }

    private func poll(_ code: GitHubDeviceFlow.Code, generation: Int) async {
        guard generation == signInGeneration else { return }
        guard Date() < pollDeadline else {
            signIn = .failed("The code expired. Try again.")
            publishAll()
            return
        }
        let answer = await flow.poll(code)
        guard generation == signInGeneration else { return }
        switch answer {
        case .pending:
            schedulePoll(code, generation: generation)
        case .slowDown:
            pollInterval += 5
            schedulePoll(code, generation: generation)
        case .token(let token):
            await finishSignIn(gitHubToken: token, generation: generation)
        case .expired:
            signIn = .failed("The code expired. Try again.")
        case .denied:
            signIn = .failed("Sign-in was cancelled on GitHub.")
        case .failed(let text):
            signIn = .failed(text)
        }
        publishAll()
    }

    private func finishSignIn(gitHubToken: String, generation: Int) async {
        signIn = .starting
        publishAll()
        do {
            let result = try await client.signIn(gitHubToken: gitHubToken)
            guard generation == signInGeneration else { return }
            host.saveSession(result.session)
            client.session = result.session
            user = result.user
            signIn = .done
            await refreshAccount()
        } catch {
            guard generation == signInGeneration else { return }
            signIn = .failed(Self.text(error))
        }
    }

    private func cancelSignIn() {
        signInGeneration += 1
        timers.cancel("sign-in")
        signIn = .idle
    }

    private func signOut() async {
        try? await client.signOut()
        forgetSession()
    }

    private func deleteAccount() async {
        await attempt { [self] in
            try await client.deleteAccount()
            forgetSession()
            await refresh()
        }
    }

    private func forgetSession() {
        host.deleteSession()
        client.session = nil
        user = nil
        mine = []
        queue = []
        if case .done = signIn { signIn = .idle }
    }

    private func submit(_ source: String, replacing id: String?, arguments: ActionArguments) async throws {
        guard arguments.property("accept-terms") == .bool(true) else {
            throw ProviderActionError.invalidArgument(action: arguments.action, message: "accept the terms first (accept-terms=#true)")
        }
        local = host.localThemes()
        guard let theme = local.first(where: { $0.identifier == source }) else {
            throw ProviderActionError.invalidArgument(action: arguments.action, message: "no local theme \"\(source)\"")
        }
        if let problem = Self.problem(theme) {
            actionError = Self.problemText(problem)
            return
        }
        guard case .success(let css) = ThemeCanonical.css(for: theme) else { return }
        do {
            try MarketThemeInstaller.checkCSS(css, identifier: theme.identifier)
        } catch {
            actionError = error.description
            return
        }
        await attempt { [self] in
            let result = if let id {
                try await client.update(themeID: id, css: css)
            } else {
                try await client.submit(css: css)
            }
            message = result.status == .published ? "\(result.name) is updated." : "\(result.name) is waiting for review."
            await refreshAll()
        }
    }

    private func decide(_ decision: MarketplaceClient.Decision, _ arguments: ActionArguments, versionIndex: Int?, reasonIndex: Int?) async throws {
        let id = try arguments.string(0)
        let version: Int?
        if let versionIndex {
            let text = try arguments.string(versionIndex)
            guard let number = Int(text), number >= 1 else {
                throw ProviderActionError.invalidArgument(action: arguments.action, message: "version must be a whole number")
            }
            version = number
        } else {
            version = queue.first(where: { $0.theme.id == id })?.theme.version
        }
        let reason = try reasonIndex.map { try Self.reason(arguments, $0) } ?? ""
        await attempt { [self] in
            do {
                try await client.decide(decision, themeID: id, version: version, reason: reason)
            } catch {
                await refreshAccount()
                throw error
            }
            await refreshAll()
        }
    }

    static func reason(_ arguments: ActionArguments, _ index: Int) throws -> String {
        let text = try arguments.string(index).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ProviderActionError.invalidArgument(action: arguments.action, message: "a reason is required")
        }
        return text
    }

    static func problem(_ theme: Theme) -> String? {
        switch ThemeCanonical.css(for: theme) {
        case .failure(.usesFiles): return "uses-files"
        case .failure(.noTokens): return "no-tokens"
        case .success:
            return (theme.value(ThemeTextToken.themeName) ?? "").isEmpty ? "no-name" : nil
        }
    }

    static func problemText(_ problem: String) -> String {
        switch problem {
        case "uses-files": "This theme uses images. The Marketplace takes plain CSS themes only for now."
        case "no-tokens": "There is nothing in this theme the shell knows."
        default: "Give it a name first: --apollo-theme-name in the file."
        }
    }

    private var signInValue: Value {
        let (state, code, url): (String, String?, String?) = switch signIn {
        case .idle: ("idle", nil, nil)
        case .starting: ("waiting", nil, nil)
        case .waiting(let code): ("waiting", code.userCode, code.verificationURL.absoluteString)
        case .done: ("done", nil, nil)
        case .failed: ("failed", nil, nil)
        }
        var fields: [(String, Value)] = [("status", .string(state)), ("code", ProviderValue.string(code)), ("url", ProviderValue.string(url))]
        if case .failed(let text) = signIn { fields.append(("error", .string(text))) } else { fields.append(("error", .null)) }
        return .record(Record(fields))
    }

    func publishAll() {
        guard isRunning else { return }
        let index = host.installer.index()
        publish("status", .string(status))
        publish("error", ProviderValue.string(actionError))
        publish("offline", .bool(actionError == Self.offlineNote))
        publish("load-error", ProviderValue.string(status == "failed" ? loadError : nil))
        publish("items", .list(themes.map { Self.item($0, state: host.installer.state(of: $0, index: index)) }))
        publish("user", user.map { .record(Record([("id", .string($0.id)), ("login", .string($0.login)), ("is-admin", .bool($0.isAdmin))])) } ?? .null)
        publish("sign-in", signInValue)
        publish("mine", .list(mine.map { Self.own($0, state: host.installer.state(of: $0.theme, index: index)) }))
        publish("queue", .list(queue.map(Self.queued)))
        publish("message", ProviderValue.string(message))
        publish("local", .list(local.map(Self.localTheme)))
    }

    static func fields(_ theme: MarketTheme, css: String? = nil) -> [(String, Value)] {
        [
            ("id", .string(theme.id)),
            ("kind", .string("theme")),
            ("slug", .string(theme.slug)),
            ("name", .string(theme.name)),
            ("author", .string(theme.author)),
            ("version", .number(Double(theme.version))),
            ("description", .string(theme.description)),
            ("license", .string(theme.license)),
            ("attribution", .string(theme.attribution)),
            ("updated", .string(theme.updatedAt)),
            ("css", .string(css ?? theme.css)),
        ]
    }

    static func item(_ theme: MarketTheme, state: MarketThemeInstaller.State) -> Value {
        .record(Record(fields(theme) + [("state", .string(state.rawValue))]))
    }

    static func statusName(_ status: MarketOwnTheme.Status) -> String {
        switch status {
        case .pending: "waiting"
        case .published: "live"
        case .rejected: "rejected"
        case .hidden: "hidden"
        }
    }

    static func previewCSS(_ theme: MarketTheme) -> String {
        do {
            try MarketThemeInstaller.check(theme)
            return theme.css
        } catch {
            return ""
        }
    }

    static func ownFields(_ own: MarketOwnTheme) -> [(String, Value)] {
        fields(own.theme, css: previewCSS(own.theme)) + [
            ("status", .string(statusName(own.status))),
            ("reason", ProviderValue.string(own.reason.flatMap { $0.isEmpty ? nil : $0 })),
            ("live-version", ProviderValue.number(own.liveVersion)),
        ]
    }

    static func own(_ own: MarketOwnTheme, state: MarketThemeInstaller.State) -> Value {
        .record(Record(ownFields(own) + [("state", .string(state.rawValue))]))
    }

    static func queued(_ item: MarketQueueItem) -> Value {
        .record(Record(ownFields(item.theme) + [
            ("reports", .list(item.reports.map { .record(Record([("reason", .string($0.reason)), ("at", .string($0.at))])) })),
            ("update-note", item.previousCSS == nil ? .null : .string(updateNote)),
            ("previous-css", ProviderValue.string(item.previousCSS)),
            ("owner-id", ProviderValue.string(item.ownerID)),
        ]))
    }

    static func localTheme(_ theme: Theme) -> Value {
        let css: String = if case .success(let text) = ThemeCanonical.css(for: theme) { text } else { "" }
        return .record(Record([
            ("id", .string(theme.identifier)),
            ("name", .string(theme.title)),
            ("problem", ProviderValue.string(problem(theme))),
            ("css", .string(css)),
        ]))
    }
}
