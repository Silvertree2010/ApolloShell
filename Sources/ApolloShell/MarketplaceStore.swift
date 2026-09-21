import AppKit
import ApolloShellCore
import Foundation
import Observation

/// Everything the Marketplace sheet shows and does: the list, the signed-in
/// account, the user's own themes, the review queue for the admin, and the
/// installed themes in the theme folder.
@MainActor
@Observable
final class MarketplaceStore {
    enum Load: Equatable {
        case idle, loading, loaded, failed(String)
    }

    /// Where the device flow stands while signing in.
    enum SignIn: Equatable {
        case idle
        case starting
        case waiting(GitHubDeviceFlow.Code)
        case failed(String)
    }

    private(set) var themes: [MarketTheme] = []
    private(set) var load: Load = .idle
    private(set) var user: MarketUser?
    private(set) var mine: [MarketOwnTheme] = []
    private(set) var queue: [MarketQueueItem] = []
    private(set) var signIn: SignIn = .idle
    private(set) var installed = MarketInstallIndex()
    /// The last thing that went wrong with an action, shown as an alert.
    var actionError: String?
    /// A short confirmation after an action ("Submitted for review").
    var notice: String?

    @ObservationIgnored private let themeStore: ThemeStore
    @ObservationIgnored private var client: MarketplaceClient
    @ObservationIgnored private let flow = GitHubDeviceFlow()
    @ObservationIgnored private var signInTask: Task<Void, Never>?

    /// A local server for development:
    /// `defaults write io.github.silvertree2010.apolloshell MarketplaceURL http://localhost:8788`
    private static var baseURL: URL {
        UserDefaults.standard.string(forKey: "MarketplaceURL").flatMap(URL.init(string:))
            ?? MarketplaceClient.productionURL
    }

    init(themeStore: ThemeStore) {
        self.themeStore = themeStore
        client = MarketplaceClient(baseURL: Self.baseURL, session: MarketplaceKeychain.load())
        installed = MarketInstallIndex.load(from: indexURL)
    }

    var signInAvailable: Bool { flow.isConfigured }
    var isSignedIn: Bool { user != nil }

    private var indexURL: URL {
        themeStore.folder.deletingLastPathComponent().appendingPathComponent("marketplace.json")
    }

    // MARK: Loading

    func refresh() async {
        load = .loading
        do {
            themes = try await client.themes()
            load = .loaded
        } catch {
            load = .failed(error.localizedDescription)
        }
        await refreshAccount()
    }

    func refreshAccount() async {
        guard client.session != nil else { return }
        do {
            user = try await client.me()
            mine = try await client.mine()
            if user?.isAdmin == true { queue = try await client.queue() }
        } catch MarketError.server(code: "unauthorized", _, _) {
            forgetSession()
        } catch {
            // Offline: keep what we had.
        }
    }

    // MARK: Installing

    enum InstallState { case notInstalled, installed, updateAvailable }

    func state(of theme: MarketTheme) -> InstallState {
        guard let entry = installed.entries[theme.id],
              FileManager.default.fileExists(atPath: themeStore.folder.appendingPathComponent(entry.fileName).path)
        else { return .notInstalled }
        return entry.version < theme.version ? .updateAvailable : .installed
    }

    func install(_ theme: MarketTheme) {
        let manager = FileManager.default
        let folder = themeStore.folder
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            // Update in place; a new install never overwrites a file that
            // is not ours.
            var fileName = installed.entries[theme.id]?.fileName ?? MarketInstall.fileName(for: theme)
            if installed.entries[theme.id] == nil {
                let base = String(fileName.dropLast(4))
                var counter = 2
                while manager.fileExists(atPath: folder.appendingPathComponent(fileName).path) {
                    fileName = "\(base) \(counter).css"
                    counter += 1
                }
            }
            try Data(MarketInstall.fileContents(for: theme).utf8)
                .write(to: folder.appendingPathComponent(fileName), options: .atomic)
            installed.entries[theme.id] = .init(fileName: fileName, version: theme.version)
            try installed.save(to: indexURL)
            themeStore.reload()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func apply(_ theme: MarketTheme) {
        if state(of: theme) != .installed { install(theme) }
        guard let entry = installed.entries[theme.id] else { return }
        themeStore.select(String(entry.fileName.dropLast(4)))
    }

    func uninstall(_ theme: MarketTheme) {
        guard let entry = installed.entries[theme.id] else { return }
        let name = String(entry.fileName.dropLast(4))
        if themeStore.selection == name { themeStore.select(nil) }
        try? FileManager.default.removeItem(at: themeStore.folder.appendingPathComponent(entry.fileName))
        installed.entries[theme.id] = nil
        try? installed.save(to: indexURL)
        themeStore.reload()
    }

    // MARK: Account

    func startSignIn() {
        // One sign-in at a time; a second click while waiting changes nothing.
        switch signIn {
        case .starting, .waiting: return
        case .idle, .failed: break
        }
        signInTask?.cancel()
        signIn = .starting
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let code = try await flow.start()
                guard !Task.isCancelled else { return }
                signIn = .waiting(code)
                NSWorkspace.shared.open(code.verificationURL)
                await poll(code)
            } catch {
                // A cancelled attempt must not overwrite the one after it.
                guard !Task.isCancelled else { return }
                signIn = .failed(error.localizedDescription)
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signIn = .idle
    }

    private func poll(_ code: GitHubDeviceFlow.Code) async {
        var interval = code.interval
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        while !Task.isCancelled, Date() < deadline {
            try? await Task.sleep(for: .seconds(interval))
            if Task.isCancelled { return }
            switch await flow.poll(code) {
            case .pending: continue
            case .slowDown: interval += 5
            case let .token(token):
                await finishSignIn(gitHubToken: token)
                return
            case .expired:
                signIn = .failed(String(localized: "The code expired. Try again."))
                return
            case .denied:
                signIn = .failed(String(localized: "Sign-in was cancelled on GitHub."))
                return
            case let .failed(message):
                if Task.isCancelled { return }
                signIn = .failed(message)
                return
            }
        }
        if !Task.isCancelled { signIn = .failed(String(localized: "The code expired. Try again.")) }
    }

    private func finishSignIn(gitHubToken: String) async {
        signIn = .starting
        do {
            let result = try await client.signIn(gitHubToken: gitHubToken)
            MarketplaceKeychain.save(result.session)
            client.session = result.session
            user = result.user
            signIn = .idle
            await refreshAccount()
        } catch {
            signIn = .failed(error.localizedDescription)
        }
    }

    func signOut() async {
        try? await client.signOut()
        forgetSession()
    }

    func deleteAccount() async {
        do {
            try await client.deleteAccount()
            forgetSession()
            await refresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func forgetSession() {
        MarketplaceKeychain.delete()
        client.session = nil
        user = nil
        mine = []
        queue = []
    }

    // MARK: Submitting

    /// The canonical form of a local theme, or why it cannot go up.
    func canonical(for theme: Theme) -> Result<String, ThemeCanonicalProblem> {
        ThemeCanonical.css(for: theme)
    }

    func submit(_ theme: Theme, replacing existing: MarketOwnTheme? = nil) async {
        guard case let .success(css) = canonical(for: theme) else { return }
        do {
            let result = if let existing {
                try await client.update(themeID: existing.id, css: css)
            } else {
                try await client.submit(css: css)
            }
            notice = result.status == .published
                ? String(localized: "\(result.name) is updated.")
                : String(localized: "\(result.name) is waiting for review.")
            await refreshAccount()
            await refresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func delete(_ theme: MarketOwnTheme) async {
        do {
            try await client.delete(themeID: theme.id)
            await refreshAccount()
            await refresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func report(_ theme: MarketTheme, reason: String) async {
        do {
            try await client.report(themeID: theme.id, reason: reason)
            notice = String(localized: "Thanks. The report was sent.")
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: Review

    func decide(_ decision: MarketplaceClient.Decision, _ item: MarketQueueItem, reason: String = "") async {
        do {
            try await client.decide(decision, themeID: item.theme.id, reason: reason)
            await refreshAccount()
            await refresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func ban(authorOf item: MarketQueueItem, reason: String) async {
        guard let owner = item.ownerID else { return }
        do {
            try await client.ban(userID: owner, reason: reason)
            await refreshAccount()
            await refresh()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
