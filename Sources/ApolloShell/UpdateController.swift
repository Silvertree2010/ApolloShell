import AppKit
import ApolloShellCore
import Sparkle
import SwiftUI

/// Self-updating of the shell (Nexus > Updates).
///
/// Two ways, depending on where the installation came from (`InstallKind`):
///
/// - Out of the DMG: Sparkle checks daily, downloads in the background and
///   installs on quit. Because a shell is practically never quit, this class
///   catches the installing (`willInstallUpdateOnQuit`) and holds on to the
///   block: Nexus shows "Restart now", and whoever does not click gets the
///   update at the next logout.
/// - From Homebrew: there the app belongs to Homebrew. It does not renew
///   itself but asks GitHub for the newest version and names
///   `brew upgrade apolloshell`.
///
/// Sparkle's windows never appear by themselves
/// (`standardUserDriverShouldHandleShowingScheduledUpdate` = `false`): in a
/// background app (`LSUIElement`) a window that pushes itself to the front
/// unasked would be an overreach. The notice stands in Nexus, and only
/// "Check now" opens Sparkle's window on purpose.
@MainActor
@Observable
final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// What the user sees on the page.
    enum Status: Equatable {
        /// Nothing done yet.
        case idle
        /// Running right now.
        case checking
        /// Nothing new.
        case upToDate
        /// Found, and downloading (DMG) or merely reported (Homebrew).
        case found(version: String, page: URL?)
        /// Downloaded, waiting to be installed.
        case ready(version: String)
        /// Failed; the text comes from Sparkle or from the network.
        case failed(String)
        /// No update possible: no bundle (`swift run`) or no public key in
        /// the bundle.
        case unavailable
    }

    private(set) var status: Status = .idle
    /// When it last looked. In the Homebrew build the time stands in the
    /// settings, so that "at most once a day" holds across a restart too;
    /// in the DMG build Sparkle keeps the books itself.
    private(set) var lastCheck: Date?
    let installKind: InstallKind

    private let settings: ShellSettingsStore
    private var updaterController: SPUStandardUpdaterController?
    /// Handed over by Sparkle as soon as a downloaded update waits for the quit.
    private var installNow: (() -> Void)?
    private var checkTask: Task<Void, Never>?
    /// Follows the two switches, wherever they are changed (the menu bar).
    private var settingsObservation: Task<Void, Never>?

    /// Checks the Homebrew build at most once a day by itself.
    private static let checkInterval: TimeInterval = 86400

    init(settings: ShellSettingsStore,
         installKind: InstallKind = .detect(resourcesURL: Bundle.main.resourceURL)) {
        self.settings = settings
        self.installKind = installKind
        super.init()
        lastCheck = settings.settings.updates.lastCheck

        guard installKind.updatesItself, Self.bundleCanUpdate else {
            status = .unavailable
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self,
                                                     userDriverDelegate: self)
        updaterController = controller
        applySettings()
        lastCheck = controller.updater.lastUpdateCheckDate
        // Delivers the current value first, then every change; lives as
        // long as the app (AppDelegate holds the controller).
        settingsObservation = Task { [weak self, settings] in
            for await _ in Observations({ settings.settings.updates }) {
                self?.applySettings()
            }
        }
    }

    /// Sparkle needs a bundle with an Info.plist and a public key. Without the
    /// key (not generated yet, see scripts/make-release-keys.sh) Sparkle turns
    /// down every update anyway - then do not even start it, instead of
    /// failing daily.
    private static var bundleCanUpdate: Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return !(key ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Can this installation update itself at all?
    var canUpdateItself: Bool { updaterController != nil }

    /// The command for the Homebrew build.
    var upgradeCommand: String { InstallKind.homebrewUpgradeCommand }

    /// Takes over the two switches from Nexus. Call after every change.
    func applySettings() {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = settings.settings.updates.checkAutomatically
        updater.automaticallyDownloadsUpdates = settings.settings.updates.installAutomatically
        updater.updateCheckInterval = Self.checkInterval
    }

    /// "Check now". In the DMG build Sparkle takes over with its window -
    /// on purpose here, because the user has just clicked.
    func checkNow() {
        rememberCheck(at: Date())
        if let updaterController {
            // When an update lies ready already, Sparkle only brings that one
            // back up (its window offers the install) - "Restart now" keeps
            // standing while it does.
            if installNow == nil { status = .checking }
            updaterController.updater.checkForUpdates()
            return
        }
        checkViaGitHub()
    }

    /// Background check on the start, only for the Homebrew build and only
    /// when the switch is on. Sparkle brings a schedule of its own.
    func checkInBackgroundIfDue() {
        guard updaterController == nil, installKind == .homebrew else { return }
        guard settings.settings.updates.checkAutomatically else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        checkViaGitHub()
    }

    /// "Restart now": installs the downloaded update right away. Sparkle quits
    /// the app for that and starts it again.
    func installNowIfReady() {
        guard let installNow else { return }
        self.installNow = nil
        installNow()
    }

    var isReadyToInstall: Bool {
        if case .ready = status { return true }
        return false
    }

    /// Remember the time - in memory and, with Homebrew, on the disk too.
    private func rememberCheck(at date: Date) {
        lastCheck = date
        guard updaterController == nil else { return }
        settings.settings.updates.lastCheck = date
    }

    private func checkViaGitHub() {
        checkTask?.cancel()
        status = .checking
        let current = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        checkTask = Task { [weak self] in
            let outcome = await UpdateCheck.live().run(current: current)
            guard !Task.isCancelled else { return }
            self?.rememberCheck(at: Date())
            switch outcome {
            case .current: self?.status = .upToDate
            case let .newer(release): self?.status = .found(version: release.version.description, page: release.page)
            case let .failed(message): self?.status = .failed(message)
            }
        }
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        // Sparkle reports an update it has downloaded already as found again
        // on the next check (SPUBasicUpdateDriver picks it up instead of
        // looking anew). Ready stays ready.
        if installNow != nil {
            status = .ready(version: item.displayVersionString)
            return
        }
        status = .found(version: item.displayVersionString, page: item.releaseNotesURL ?? item.infoURL)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status = .upToDate
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        status = .ready(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        status = .failed(error.localizedDescription)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        // A cancel by the user is no error that has to stand on the page -
        // but the page must not go on showing "checking" forever after it
        // either.
        guard (error as NSError).code != Int(SUError.installationCanceledError.rawValue) else {
            if case .checking = status { status = .idle }
            return
        }
        status = .failed(error.localizedDescription)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastCheck = updater.lastUpdateCheckDate
        if case .checking = status, error == nil { status = .upToDate }
    }

    /// Sparkle wants to install on quit. We say yes ("yes, we take care of
    /// it") and lift the block, so "Restart now" can set it off. Without a
    /// click Sparkle installs on the next quit.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installNow = immediateInstallHandler
        status = .ready(version: item.displayVersionString)
        return true
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// Yes: we show the notice ourselves (Nexus), Sparkle does not push in.
    ///
    /// `nonisolated`, because Sparkle does not put this protocol on the main
    /// actor (unlike `SPUUpdaterDelegate`). Both answers are fixed values and
    /// read no state, so that is safe.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                         andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }
}
