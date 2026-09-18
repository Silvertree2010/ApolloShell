import ApolloShellCore
import Foundation
import Observation
import os

/// "Wach halten": die IOKit-Zusicherung, der Akku-Schutz und der Deckel-Teil
/// (`pmset disablesleep`, siehe `LidAwake`) samt Administrator-Frage und
/// Merker fuer den Absturzfall.
///
/// Eine eigene Zustandsmaschine; das Utilities-Modell reicht nur weiter.
@MainActor
@Observable
final class KeepAwakeController {
    /// Seit wann "Wach halten" laeuft; `nil` = aus.
    private(set) var since: Date?
    /// Stand des Deckel-Teils.
    private(set) var lid: KeepAwakeLid = .off

    var isOn: Bool { since != nil }

    /// Eine Kurzmeldung zeigen (Akku-Schutz, abgelehnte Freigabe).
    @ObservationIgnored var onToast: (ToastText.Content) -> Void = { _ in }

    /// `false` fuer Vorschauen: schaltet nichts.
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var assertion: PowerAssertion?
    /// Hat die App `disablesleep` selbst gesetzt? Nur dann setzt sie es
    /// zurueck. Stand es schon vorher auf 1 (von jemand anderem), bleibt es,
    /// wie es war.
    @ObservationIgnored private var lidAwakeOwned = false
    /// Einstellung "Auch bei zugeklapptem Deckel" (settings.json keepAwake).
    /// Wird bei jedem Einschalten neu gefragt, sie kann sich ja aendern.
    @ObservationIgnored private let lidAllowed: @MainActor () -> Bool
    /// Der osascript-Prozess der offenen Administrator-Frage und wofuer sie
    /// ist. Solange er laeuft, keine zweite Frage; danach wird abgeglichen.
    /// Beim Beenden der App wird eine Einschalt-Frage abgebrochen.
    @ObservationIgnored private var lidPrompt: (process: Process, disableSleep: Bool)?
    /// Akku-Schutz, solange Wach halten laeuft: jede Minute nachsehen.
    @ObservationIgnored private var batteryGuard: Timer?
    @ObservationIgnored private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "utilities")

    init(lidAllowed: @escaping @MainActor () -> Bool) {
        live = true
        self.lidAllowed = lidAllowed
        recoverLidAwake()
    }

    /// Fester Stand fuer Vorschauen und Bildproben.
    init(preview since: Date?) {
        live = false
        self.since = since
        lidAllowed = { false }
    }

    func set(_ on: Bool) {
        guard live, on != isOn else { return }
        if on {
            do {
                assertion = try PowerAssertion(reason: "ApolloShell: Wach halten")
                since = Date()
                reconcileLid()
                batteryGuard = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.checkBattery() }
                }
            } catch {
                log.error("Wach halten nicht moeglich: IOReturn \(error.code, privacy: .public)")
            }
        } else {
            // Loslassen = Objekt weg, siehe PowerAssertion.deinit.
            assertion = nil
            since = nil
            batteryGuard?.invalidate()
            batteryGuard = nil
            reconcileLid()
        }
    }

    /// Beim Beenden der App: nichts wach zuruecklassen. Braucht das
    /// Zuruecksetzen einen Administrator, wird hier auf die Antwort gewartet -
    /// danach lebt die App nicht mehr, um sie abzuholen, und ein zugeklappter
    /// Mac in der Tasche schliefe sonst nie.
    ///
    /// Ist gerade eine Administrator-Frage offen, wird nicht gewartet: Eine
    /// Einschalt-Frage wird abgebrochen, eine Ausschalt-Frage bleibt stehen.
    /// Der Merker liegt in beiden Faellen schon, der naechste Start gleicht ab.
    func shutdown() {
        guard live else { return }
        assertion = nil
        since = nil
        batteryGuard?.invalidate()
        batteryGuard = nil
        if let prompt = lidPrompt {
            if prompt.disableSleep { prompt.process.terminate() }
            return
        }
        guard lidAwakeOwned else { return }
        // Hier wird gewartet (siehe oben) - auch auf eine Administrator-Frage.
        if Self.sudoSleepDisabled(false)
            || Subprocess.runAndWait(LidAwake.osascript, LidAwake.osascriptArguments(disableSleep: false))?.status == 0 {
            lidReleased()
        }
    }

    /// Nexus hat "Auch bei zugeklapptem Deckel" umgeschaltet: gilt sofort,
    /// auch waehrend "Wach halten" laeuft.
    func lidSettingChanged() {
        guard live, isOn else { return }
        reconcileLid()
    }

    /// Im Akkubetrieb bei 10 % aus - und sagen, warum.
    private func checkBattery() {
        guard LidAwake.shouldStop(battery: StatusModel.readBattery()) else { return }
        set(false)
        onToast(ToastText.Content(
            title: String(localized: "Wach halten beendet"),
            message: String(localized: "Akku bei \(LidAwake.batteryFloor) % – der Mac darf wieder schlafen"),
            symbol: "battery.25percent",
            kind: .warning
        ))
    }

    // MARK: Zugeklappt wach (pmset disablesleep, siehe LidAwake)

    /// Soll der Deckel-Teil gerade gelten?
    private var lidWanted: Bool { isOn && lidAllowed() }

    /// Bringt den Deckel-Teil auf den gewuenschten Stand. Laeuft noch eine
    /// Administrator-Frage, erst deren Antwort abwarten - `lidPromptFinished`
    /// gleicht danach erneut ab.
    private func reconcileLid() {
        guard lidPrompt == nil else {
            lid = lidWanted ? .pending : .off
            return
        }
        if lidWanted { enableLid() } else { releaseLid() }
    }

    private func enableLid() {
        guard lid != .on else { return }
        let current = LidAwake.sleepDisabled(pmsetOutput: Self.pmsetSettings())
        if current == true {
            // Schon an. Liegt unser Merker noch da (ein Zuruecksetzen wurde
            // abgelehnt), ist es unseres - sonst hat es jemand anderes gesetzt
            // und es bleibt nachher, wie es war.
            lidAwakeOwned = FileManager.default.fileExists(atPath: Self.lidMarker.path)
            lid = .on
            return
        }
        if Self.sudoSleepDisabled(true) {
            lidTaken()
            return
        }
        // Kein passwortloses sudo: macOS fragt nach einem Administrator.
        // Merker schon vorher: Endet die App, bevor die Antwort kommt, und
        // wird danach doch zugestimmt, setzt der naechste Start zurueck.
        Self.writeLidMarker()
        lid = .pending
        askAdmin(disableSleep: true)
    }

    private func releaseLid() {
        guard lidAwakeOwned else {
            lid = .off
            return
        }
        if Self.sudoSleepDisabled(false) {
            lidReleased()
            return
        }
        lid = .off
        askAdmin(disableSleep: false)
    }

    private func askAdmin(disableSleep: Bool) {
        // Beim ersten Einschalten legt dieselbe Frage die Regel ohne Passwort
        // an; danach klappt schon `sudo -n`, und es fragt niemand mehr.
        let arguments = LidAwake.osascriptArguments(
            disableSleep: disableSleep,
            installRuleFor: disableSleep ? LidAwakeRule.userToInstall : nil
        )
        let process = Subprocess.launch(LidAwake.osascript, arguments) { [weak self] status in
            self?.lidPromptFinished(disableSleep: disableSleep, ok: status == 0)
        }
        // Liess sich osascript nicht starten, gilt das wie eine Absage.
        guard let process else { return lidPromptFinished(disableSleep: disableSleep, ok: false) }
        lidPrompt = (process, disableSleep)
    }

    /// Antwort auf die Administrator-Frage. Abgebrochen gibt osascript einen
    /// Fehler (-128) zurueck; dann bleibt "Wach halten" ohne Deckel-Teil.
    private func lidPromptFinished(disableSleep: Bool, ok: Bool) {
        lidPrompt = nil
        if disableSleep {
            guard ok else {
                log.notice("disablesleep 1: Administrator abgelehnt, wach nur aufgeklappt")
                // Der vorab gelegte Merker gilt nicht mehr.
                if !lidAwakeOwned { try? FileManager.default.removeItem(at: Self.lidMarker) }
                lid = lidWanted ? .declined : .off
                return
            }
            lidTaken()
            // Waehrend der Frage ausgeschaltet: gleich wieder zuruecksetzen.
            if !lidWanted { releaseLid() }
        } else {
            guard ok else {
                // Merker bleibt: der naechste Start (oder das naechste Aus)
                // versucht es erneut. Und sagen, dass der Mac noch wach bleibt.
                log.error("disablesleep 0: Administrator abgelehnt")
                lid = lidWanted ? .on : .off
                if !lidWanted { onToast(Self.lidStillDisabledToast) }
                return
            }
            lidReleased()
            if lidWanted { enableLid() }
        }
    }

    private func lidTaken() {
        lidAwakeOwned = true
        lid = .on
        // Merker fuer den Absturzfall, siehe recoverLidAwake().
        Self.writeLidMarker()
    }

    /// Der Ordner fehlt bei einer frischen Installation womoeglich noch.
    private static func writeLidMarker() {
        let url = lidMarker
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    private func lidReleased() {
        lidAwakeOwned = false
        lid = .off
        try? FileManager.default.removeItem(at: Self.lidMarker)
    }

    private static let lidStillDisabledToast = ToastText.Content(
        title: String(localized: "Zugeklappt noch wach"),
        message: String(localized: "Ohne Freigabe bleibt der Ruhezustand beim Zuklappen aus – Wach halten ein- und ausschalten versucht es erneut"),
        symbol: "laptopcomputer",
        kind: .warning
    )

    /// Ist die App abgestuerzt, waehrend sie `disablesleep` gesetzt hatte,
    /// schliefe der Mac nie mehr - auch zugeklappt in der Tasche. Beim
    /// naechsten Start deshalb aufraeumen, wenn der Merker noch da ist. Steht
    /// es inzwischen ohnehin auf 0, genuegt es, den Merker zu loeschen.
    private func recoverLidAwake() {
        guard FileManager.default.fileExists(atPath: Self.lidMarker.path) else { return }
        let current = LidAwake.sleepDisabled(pmsetOutput: Self.pmsetSettings())
        lidAwakeOwned = true
        if current == false || Self.sudoSleepDisabled(false) {
            lidReleased()
            return
        }
        askAdmin(disableSleep: false)
    }

    private static var lidMarker: URL { ShellFiles.live.lidAwakeMarker }

    // Beide Werkzeuge laufen synchron auf dem Hauptthread: gemessen sind es
    // Millisekunden, und die Zustandsmaschine bleibt ohne Zwischenstaende.

    /// `sudo -n`: ohne Passwort oder gar nicht - wartet nie auf eine Eingabe.
    private static func sudoSleepDisabled(_ on: Bool) -> Bool {
        Subprocess.runAndWait(LidAwake.sudo, LidAwake.sudoArguments(disableSleep: on))?.status == 0
    }

    /// `pmset -g`, die aktiven Einstellungen.
    private static func pmsetSettings() -> String {
        Subprocess.runAndWait(LidAwake.pmset, ["-g"])?.text ?? ""
    }
}
