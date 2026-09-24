import AppKit
import ApolloShellCore
import Sparkle
import SwiftUI

@MainActor
@Observable
final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case found(version: String, page: URL?)
        case ready(version: String)
        case failed(String)
        case unavailable
    }

    private(set) var status: Status = .idle
    private(set) var lastCheck: Date?
    let installKind: InstallKind

    private let settings: ShellSettingsStore
    private var updaterController: SPUStandardUpdaterController?
    private var installNow: (() -> Void)?
    private var checkTask: Task<Void, Never>?

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
    }

    private static var bundleCanUpdate: Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return !(key ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canUpdateItself: Bool { updaterController != nil }

    var upgradeCommand: String { InstallKind.homebrewUpgradeCommand }

    func applySettings() {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = settings.settings.updates.checkAutomatically
        updater.automaticallyDownloadsUpdates = settings.settings.updates.installAutomatically
        updater.updateCheckInterval = Self.checkInterval
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
        guard settings.settings.updates.checkAutomatically else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
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

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
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
