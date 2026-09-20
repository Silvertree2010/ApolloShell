import AppKit
import ApolloShellCore
import Sparkle
import SwiftUI

/// Selbstaktualisierung der Shell (Nexus > Updates).
///
/// Zwei Wege, je nach Herkunft der Installation (`InstallKind`):
///
/// - Aus dem DMG: Sparkle prueft taeglich, laedt im Hintergrund und spielt
///   beim Beenden ein. Weil eine Shell praktisch nie beendet wird, faengt
///   diese Klasse das Einspielen ab (`willInstallUpdateOnQuit`) und haelt den
///   Block fest: Nexus zeigt "Jetzt neu starten", und wer nicht klickt,
///   bekommt das Update beim naechsten Abmelden.
/// - Von Homebrew: Dort gehoert die App Homebrew. Sie erneuert sich nicht
///   selbst, sondern fragt GitHub nach der neuesten Fassung und nennt
///   `brew upgrade apolloshell`.
///
/// Sparkles Fenster erscheinen nie von selbst
/// (`standardUserDriverShouldHandleShowingScheduledUpdate` = `false`): In
/// einer Hintergrund-App (`LSUIElement`) waere ein Fenster, das sich
/// unaufgefordert nach vorne schiebt, ein Uebergriff. Der Hinweis steht in
/// Nexus, und nur "Check now" oeffnet Sparkles Fenster ausdruecklich.
@MainActor
@Observable
final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// Was der Benutzer auf der Seite sieht.
    enum Status: Equatable {
        /// Noch nichts getan.
        case idle
        /// Laeuft gerade.
        case checking
        /// Nichts Neues.
        case upToDate
        /// Gefunden und wird geladen (DMG) beziehungsweise nur gemeldet (Homebrew).
        case found(version: String, page: URL?)
        /// Geladen, wartet aufs Einspielen.
        case ready(version: String)
        /// Fehlgeschlagen; Text von Sparkle oder vom Netz.
        case failed(String)
        /// Kein Update moeglich: kein Bundle (`swift run`) oder kein
        /// oeffentlicher Schluessel im Bundle.
        case unavailable
    }

    private(set) var status: Status = .idle
    /// Wann zuletzt gesucht wurde. Bei der Homebrew-Fassung steht der
    /// Zeitpunkt in den Einstellungen, damit "hoechstens einmal am Tag" auch
    /// ueber einen Neustart hinweg gilt; bei der DMG-Fassung fuehrt Sparkle
    /// selbst Buch.
    private(set) var lastCheck: Date?
    let installKind: InstallKind

    private let settings: ShellSettingsStore
    private var updaterController: SPUStandardUpdaterController?
    /// Von Sparkle gereicht, sobald ein geladenes Update aufs Beenden wartet.
    private var installNow: (() -> Void)?
    private var checkTask: Task<Void, Never>?

    /// Prueft die Homebrew-Fassung hoechstens einmal pro Tag von selbst.
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

    /// Sparkle braucht ein Bundle mit Info.plist und einen oeffentlichen
    /// Schluessel. Fehlt der Schluessel (noch nicht erzeugt, siehe
    /// scripts/make-release-keys.sh), lehnt Sparkle jedes Update ohnehin ab -
    /// dann gar nicht erst starten, statt taeglich zu scheitern.
    private static var bundleCanUpdate: Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return !(key ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Kann diese Installation ueberhaupt selbst aktualisieren?
    var canUpdateItself: Bool { updaterController != nil }

    /// Der Befehl fuer die Homebrew-Fassung.
    var upgradeCommand: String { InstallKind.homebrewUpgradeCommand }

    /// Uebernimmt die beiden Schalter aus Nexus. Nach jeder Aenderung rufen.
    func applySettings() {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = settings.settings.updates.checkAutomatically
        updater.automaticallyDownloadsUpdates = settings.settings.updates.installAutomatically
        updater.updateCheckInterval = Self.checkInterval
    }

    /// "Check now". Bei der DMG-Fassung uebernimmt Sparkle mit seinem
    /// Fenster - hier ausdruecklich gewollt, weil der Benutzer gerade
    /// geklickt hat.
    func checkNow() {
        rememberCheck(at: Date())
        if let updaterController {
            // Liegt schon ein Update bereit, holt Sparkle nur dieses wieder
            // hervor (sein Fenster bietet das Einspielen an) - "Jetzt neu
            // starten" bleibt dabei stehen.
            if installNow == nil { status = .checking }
            updaterController.updater.checkForUpdates()
            return
        }
        checkViaGitHub()
    }

    /// Hintergrundpruefung beim Start, nur fuer die Homebrew-Fassung und nur
    /// wenn der Schalter an ist. Sparkle bringt seinen eigenen Zeitplan mit.
    func checkInBackgroundIfDue() {
        guard updaterController == nil, installKind == .homebrew else { return }
        guard settings.settings.updates.checkAutomatically else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        checkViaGitHub()
    }

    /// "Jetzt neu starten": spielt das geladene Update sofort ein. Sparkle
    /// beendet die App dabei und startet sie neu.
    func installNowIfReady() {
        guard let installNow else { return }
        self.installNow = nil
        installNow()
    }

    var isReadyToInstall: Bool {
        if case .ready = status { return true }
        return false
    }

    /// Zeitpunkt merken - im Speicher und, bei Homebrew, auch auf der Platte.
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
        // Ein schon geladenes Update meldet Sparkle beim erneuten Pruefen
        // noch einmal als gefunden (SPUBasicUpdateDriver nimmt es wieder
        // auf, statt neu zu suchen). Bereit bleibt bereit.
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
        // Abbruch durch den Benutzer ist kein Fehler, der auf der Seite stehen
        // muss - aber die Seite darf danach auch nicht ewig "wird geprüft"
        // zeigen.
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

    /// Sparkle will beim Beenden einspielen. Wir sagen zu ("ja, wir kuemmern
    /// uns") und heben den Block auf, damit "Jetzt neu starten" ihn ausloesen
    /// kann. Ohne Klick spielt Sparkle beim naechsten Beenden ein.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installNow = immediateInstallHandler
        status = .ready(version: item.displayVersionString)
        return true
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// Ja: Wir zeigen den Hinweis selbst (Nexus), Sparkle draengt sich nicht vor.
    ///
    /// `nonisolated`, weil Sparkle dieses Protokoll (anders als
    /// `SPUUpdaterDelegate`) nicht dem Hauptakteur zuordnet. Beide Antworten
    /// sind feste Werte und lesen keinen Zustand, also ist das gefahrlos.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                         andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }
}
