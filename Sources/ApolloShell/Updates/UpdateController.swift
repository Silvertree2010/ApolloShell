import AppKit
import ApolloControl
import ApolloShellCore
import Sparkle

@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private(set) var status: UpdateStatus = .idle {
        didSet { if status != oldValue { onChange?() } }
    }
    private(set) var releaseNotes: URL?
    private(set) var lastCheck: Date?
    let installKind: InstallKind
    var onChange: (() -> Void)?

    private let settings: SettingsStore
    private let machine: MachineState
    private var updaterController: SPUStandardUpdaterController?
    private var installNow: (() -> Void)?
    private var checkTask: Task<Void, Never>?
    private var settingsToken: ObservationToken?

    private static let checkInterval: TimeInterval = 86400

    init(settings: SettingsStore,
         machine: MachineState,
         installKind: InstallKind = .detect(resourcesURL: Bundle.main.resourceURL)) {
        self.settings = settings
        self.machine = machine
        self.installKind = installKind
        super.init()
        lastCheck = machine.lastUpdateCheck
        settingsToken = settings.observe { [weak self] old, new in
            guard old.autoCheckUpdates != new.autoCheckUpdates || old.autoInstallUpdates != new.autoInstallUpdates else { return }
            Task { @MainActor in self?.applySettings() }
        }

        guard installKind.updatesItself, Self.bundleCanUpdate else {
            status = .unavailable
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self,
                                                     userDriverDelegate: self)
        updaterController = controller
        applySettings()
        lastCheck = controller.updater.lastUpdateCheckDate
    }

    private static var bundleCanUpdate: Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return !(key ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canUpdateItself: Bool { updaterController != nil }

    var upgradeCommand: String { InstallKind.homebrewUpgradeCommand }

    var autoCheck: Bool { settings.settings.autoCheckUpdates }

    var autoInstall: Bool { settings.settings.autoInstallUpdates }

    func setAutoCheck(_ enabled: Bool) throws {
        try settings.apply(.updates(autoCheck: enabled, autoInstall: autoInstall))
    }

    func setAutoInstall(_ enabled: Bool) throws {
        try settings.apply(.updates(autoCheck: autoCheck, autoInstall: enabled))
    }

    func applySettings() {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = autoCheck
        updater.automaticallyDownloadsUpdates = autoInstall
        updater.updateCheckInterval = Self.checkInterval
        onChange?()
    }

    func checkNow() {
        rememberCheck(at: Date())
        if let updaterController {
            if installNow == nil { status = .checking }
            updaterController.updater.checkForUpdates()
            return
        }
        checkViaGitHub()
    }

    func checkInBackgroundIfDue() {
        guard updaterController == nil, installKind == .homebrew else { return }
        guard UpdateSchedule.isDue(lastCheck: lastCheck, now: Date(), autoCheck: autoCheck, interval: Self.checkInterval) else { return }
        checkViaGitHub()
    }

    func installNowIfReady() {
        guard let installNow else { return }
        self.installNow = nil
        installNow()
    }

    var isReadyToInstall: Bool {
        if case .ready = status { return true }
        return false
    }

    private func rememberCheck(at date: Date) {
        lastCheck = date
        guard updaterController == nil else { return }
        machine.lastUpdateCheck = date
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
            case let .newer(release):
                self?.releaseNotes = release.page
                self?.status = .available(version: release.version.description)
            case let .failed(message): self?.status = .failed(message)
            }
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        if installNow != nil {
            status = .ready(version: item.displayVersionString)
            return
        }
        releaseNotes = item.releaseNotesURL ?? item.infoURL
        status = .available(version: item.displayVersionString)
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
        guard (error as NSError).code != Int(SUError.installationCanceledError.rawValue) else {
            if case .checking = status { status = .idle }
            return
        }
        status = .failed(error.localizedDescription)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastCheck = updater.lastUpdateCheckDate
        onChange?()
        if case .checking = status, error == nil { status = .upToDate }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installNow = immediateInstallHandler
        status = .ready(version: item.displayVersionString)
        return true
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                         andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }
}
