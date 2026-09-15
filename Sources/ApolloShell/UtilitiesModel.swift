import AppKit
import CoreAudio
import CoreWLAN
import Foundation
import IOKit.pwr_mgt
import ApolloShellCore
import Observation
import os

/// Zustand und Aktionen des Utilities-Panels: "Wach halten", die Ton-Karte
/// und die Schnellschalter (WLAN, Mikrofon, Bluetooth, Dunkelmodus, Night
/// Shift) samt Aktionen (Bildschirmfoto, Schreibtisch, Farbpipette, Sperren,
/// Einstellungen).
///
/// Alles ohne Freigabe-Dialog: IOKit-Zusicherung, CoreWLAN (an/aus braucht
/// keine Ortung), CoreAudio-Eigenschaften (nur Aufnehmen braucht die
/// Mikrofon-Freigabe, Lesen, Stummschalten und Geraetewahl nicht), Bluetooth
/// ueber system_profiler (siehe `BluetoothState`), SkyLight und
/// CoreBrightness (siehe UtilitiesSystem), Tastendruecke ueber die schon
/// erteilte Bedienungshilfen-Freigabe, NSColorSampler.
///
/// Kein eigener Dauer-Timer: `start()`/`stop()` rufen die Koordinatoren beim
/// Oeffnen und Schliessen, abgefragt wird nur, solange man es sieht.
@MainActor
@Observable
final class UtilitiesModel {
    /// Seit wann "Wach halten" laeuft; `nil` = aus.
    private(set) var keepAwakeSince: Date?
    /// Stand des Deckel-Teils von "Wach halten" (`LidAwake`, pmset disablesleep).
    private(set) var lid: KeepAwakeLid = .off
    /// `nil`: kein WLAN-Interface.
    private(set) var wifiOn: Bool?
    /// Stummschaltung des Standard-Eingangs; `nil`: kein Eingang.
    private(set) var micMuted: Bool?
    private(set) var micSettable = false
    /// `nil`: noch nicht gelesen oder nicht lesbar.
    private(set) var bluetoothOn: Bool?
    /// `nil`: noch nicht gelesen.
    private(set) var darkMode: Bool?
    /// `nil`: nicht verfuegbar (oder noch nicht gelesen).
    private(set) var nightShift: Bool?
    /// Kurzbefehl "Schreibtisch anzeigen" in Mission Control an.
    private(set) var showDesktopAvailable = true

    // Ton-Karte
    private(set) var volume: Float = 0
    private(set) var outputMuted = false
    private(set) var volumeSettable = false
    private(set) var muteSettable = false
    /// Alle Geraete ungefiltert; die Menues filtern (ApolloShellCore).
    private(set) var audioDevices: [UtilitiesAudioDevice] = []
    private(set) var defaultOutput: UInt32?
    private(set) var defaultInput: UInt32?

    var outputs: [UtilitiesAudioDevice] { UtilitiesAudioDevices.devices(audioDevices, for: .output) }
    var inputs: [UtilitiesAudioDevice] { UtilitiesAudioDevices.devices(audioDevices, for: .input) }
    var outputLabel: String { UtilitiesAudioDevices.label(defaultID: defaultOutput, in: audioDevices) }
    var inputLabel: String { UtilitiesAudioDevices.label(defaultID: defaultInput, in: audioDevices) }

    /// Fuer den Schalter der Karte.
    var keepAwake: Bool {
        get { keepAwakeSince != nil }
        set { setKeepAwake(newValue) }
    }

    /// Alle 2 s, solange das Panel offen ist: WLAN (~3 ms), Mikrofon,
    /// Dunkelmodus, Night Shift und die Audiogeraete sind billig. Bluetooth
    /// kostet ~165 ms (eigener Prozess, nicht auf dem Hauptthread) - dafuer
    /// nur jede fuenfte Runde, also alle 10 s. Lautstaerke und Stumm kommen
    /// ohne Abfrage ueber CoreAudio-Listener (VolumeMonitor).
    @ObservationIgnored private static let interval: TimeInterval = 2
    @ObservationIgnored private static let bluetoothEvery = 5
    /// Nach dem Wegblenden des Panels noch so lange warten, bis macOS die
    /// Tastatur wieder der App vorne gegeben hat - erst dann den Druck posten.
    @ObservationIgnored private static let keyHandBack: Duration = .milliseconds(100)

    /// `false` fuer die Vorschau: dann liest und schaltet das Modell nichts,
    /// egal wer welche Aktion aufruft.
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var assertion: PowerAssertion?
    /// Hat die App `disablesleep` selbst gesetzt? Nur dann setzt sie es
    /// zurueck. Stand es schon vorher auf 1 (von jemand anderem), bleibt es,
    /// wie es war.
    @ObservationIgnored private var lidAwakeOwned = false
    /// Einstellung "Auch bei zugeklapptem Deckel" (settings.json keepAwake).
    @ObservationIgnored private let lidAllowed: @MainActor () -> Bool
    /// macOS fragt gerade nach einem Administrator (laeuft als eigener
    /// Prozess). Bis zur Antwort keine zweite Frage; danach wird abgeglichen.
    @ObservationIgnored private var lidPromptRunning = false
    /// Akku-Schutz, solange Wach halten laeuft: jede Minute nachsehen.
    @ObservationIgnored private var batteryGuard: Timer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private let bluetooth = BluetoothState()
    @ObservationIgnored private var volumeMonitor: VolumeMonitor?
    @ObservationIgnored private var nightShiftClient: UtilitiesNightShiftClient?
    @ObservationIgnored private var nightShiftLookedUp = false
    /// Haelt die Pipette am Leben, bis sie eine Farbe liefert.
    @ObservationIgnored private var colorSampler: NSColorSampler?
    @ObservationIgnored private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "utilities")

    /// Vom Panel: erst zu, dann `then` (siehe `EdgeDrawer.close(then:)`).
    @ObservationIgnored var closePanel: (_ then: @escaping @MainActor () -> Void) -> Void = { $0() }
    /// Vom Panel: eine Kurzmeldung zeigen (Farbpipette).
    @ObservationIgnored var onToast: (ToastText.Content) -> Void = { _ in }

    /// `lidAllowed`: ob "Wach halten" auch zugeklappt gelten soll - wird bei
    /// jedem Einschalten neu gefragt, die Einstellung kann sich ja aendern.
    init(lidAllowed: @escaping @MainActor () -> Bool) {
        live = true
        self.lidAllowed = lidAllowed
        recoverLidAwake()
    }

    private init(live: Bool) {
        self.live = live
        lidAllowed = { false }
    }

    /// Modell mit festem Zustand, das nichts liest und nichts schaltet - fuer
    /// Vorschauen und Bildproben.
    static func preview(
        keepAwakeSince: Date? = nil,
        wifiOn: Bool? = true,
        micMuted: Bool? = false,
        micSettable: Bool = true,
        bluetoothOn: Bool? = true,
        darkMode: Bool? = true,
        nightShift: Bool? = false,
        showDesktopAvailable: Bool = true,
        volume: Float = 0.45,
        outputMuted: Bool = false,
        audioDevices: [UtilitiesAudioDevice] = [],
        defaultOutput: UInt32? = nil,
        defaultInput: UInt32? = nil
    ) -> UtilitiesModel {
        let model = UtilitiesModel(live: false)
        model.keepAwakeSince = keepAwakeSince
        model.wifiOn = wifiOn
        model.micMuted = micMuted
        model.micSettable = micSettable
        model.bluetoothOn = bluetoothOn
        model.darkMode = darkMode
        model.nightShift = nightShift
        model.showDesktopAvailable = showDesktopAvailable
        model.volume = volume
        model.outputMuted = outputMuted
        model.volumeSettable = true
        model.muteSettable = true
        model.audioDevices = audioDevices
        model.defaultOutput = defaultOutput
        model.defaultInput = defaultInput
        return model
    }

    // MARK: - Abfragen

    func start() {
        guard live, timer == nil else { return }
        startVolume()
        refresh()
        ticks = 0
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] timer in
            // Ist das Modell weg, haelt sich der Timer nicht selbst am Leben.
            guard self != nil else { return timer.invalidate() }
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Hoert nur mit dem Abfragen auf. "Wach halten" bleibt an - genau dafuer
    /// ist es da, auch bei geschlossenem Panel. Die Lautstaerke-Listener
    /// bleiben auch: sie kosten nichts, solange sich nichts aendert.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Alles neu lesen, Bluetooth und den Schreibtisch-Kurzbefehl
    /// eingeschlossen (der aendert sich nur in den Systemeinstellungen).
    func refresh() {
        guard live else { return }
        readWifi()
        readMicrophone()
        readBluetooth()
        readAppearance()
        readNightShift()
        readShowDesktop()
        readVolume()
        readAudioDevices()
    }

    private func tick() {
        ticks += 1
        readWifi()
        readMicrophone()
        readAppearance()
        readNightShift()
        readAudioDevices()
        if ticks % Self.bluetoothEvery == 0 { readBluetooth() }
    }

    private func readWifi() {
        let on = CWWiFiClient.shared().interface().map { $0.powerOn() }
        if on != wifiOn { wifiOn = on }
    }

    private func readMicrophone() {
        let state = Microphone.defaultInput().flatMap(Microphone.muteState(of:))
        let muted = state?.muted
        let settable = state?.settable ?? false
        if muted != micMuted { micMuted = muted }
        if settable != micSettable { micSettable = settable }
    }

    private func readBluetooth() {
        bluetooth.readOnce { [weak self] on in
            guard let self, on != self.bluetoothOn else { return }
            self.bluetoothOn = on
        }
    }

    private func readAppearance() {
        let dark = UtilitiesAppearance.isDark()
        if dark != darkMode { darkMode = dark }
    }

    /// Den Client erst beim ersten Oeffnen anlegen: CoreBrightness laden
    /// kostet, und wer das Panel nie oeffnet, braucht es nicht.
    private func readNightShift() {
        if !nightShiftLookedUp {
            nightShiftLookedUp = true
            nightShiftClient = UtilitiesNightShiftClient()
        }
        let enabled = nightShiftClient?.enabled()
        if enabled != nightShift { nightShift = enabled }
    }

    private func readShowDesktop() {
        let available = UtilitiesKeys.symbolic(id: UtilitiesHotKey.showDesktopID, fallback: .showDesktopDefault) != nil
        if available != showDesktopAvailable { showDesktopAvailable = available }
    }

    private func startVolume() {
        guard volumeMonitor == nil else { return }
        let monitor = VolumeMonitor()
        monitor.onChange = { [weak self] _, _ in self?.readVolume() }
        monitor.start()
        volumeMonitor = monitor
    }

    private func readVolume() {
        guard let monitor = volumeMonitor else { return }
        if monitor.volume != volume { volume = monitor.volume }
        if monitor.muted != outputMuted { outputMuted = monitor.muted }
        if monitor.volumeSettable != volumeSettable { volumeSettable = monitor.volumeSettable }
        if monitor.muteSettable != muteSettable { muteSettable = monitor.muteSettable }
    }

    /// Nur zuweisen, was sich geaendert hat: sonst baut SwiftUI die
    /// Karte alle 2 s neu, auch wenn alles gleich ist.
    private func readAudioDevices() {
        let devices = UtilitiesAudioHardware.devices()
        if devices != audioDevices { audioDevices = devices }
        let output = UtilitiesAudioHardware.defaultDevice(.output)
        if output != defaultOutput { defaultOutput = output }
        let input = UtilitiesAudioHardware.defaultDevice(.input)
        if input != defaultInput { defaultInput = input }
    }

    // MARK: - Aktionen

    func setKeepAwake(_ on: Bool) {
        guard live, on != keepAwake else { return }
        if on {
            do {
                assertion = try PowerAssertion(reason: "ApolloShell: Wach halten")
                keepAwakeSince = Date()
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
            keepAwakeSince = nil
            batteryGuard?.invalidate()
            batteryGuard = nil
            reconcileLid()
        }
    }

    /// Beim Beenden der App: nichts wach zuruecklassen. Braucht das
    /// Zuruecksetzen einen Administrator, wird hier auf die Antwort gewartet -
    /// danach lebt die App nicht mehr, um sie abzuholen, und ein zugeklappter
    /// Mac in der Tasche schliefe sonst nie.
    func shutdown() {
        guard live else { return }
        assertion = nil
        keepAwakeSince = nil
        batteryGuard?.invalidate()
        batteryGuard = nil
        guard lidAwakeOwned, !lidPromptRunning else { return }
        if Self.sudoSleepDisabled(false) || Self.run(LidAwake.osascript, LidAwake.osascriptArguments(disableSleep: false)).status == 0 {
            lidReleased()
        }
    }

    /// Nexus hat "Auch bei zugeklapptem Deckel" umgeschaltet: gilt sofort,
    /// auch waehrend "Wach halten" laeuft.
    func lidSettingChanged() {
        guard live, keepAwake else { return }
        reconcileLid()
    }

    /// Im Akkubetrieb bei 10 % aus - und sagen, warum.
    private func checkBattery() {
        guard LidAwake.shouldStop(battery: StatusModel.readBattery()) else { return }
        setKeepAwake(false)
        onToast(ToastText.Content(
            title: String(localized: "Wach halten beendet"),
            message: String(localized: "Akku bei \(LidAwake.batteryFloor) % – der Mac darf wieder schlafen"),
            symbol: "battery.25percent",
            kind: .warning
        ))
    }

    // MARK: Zugeklappt wach (pmset disablesleep, siehe LidAwake)

    /// Soll der Deckel-Teil gerade gelten?
    private var lidWanted: Bool { keepAwake && lidAllowed() }

    /// Bringt den Deckel-Teil auf den gewuenschten Stand. Laeuft noch eine
    /// Administrator-Frage, erst deren Antwort abwarten - `lidPromptFinished`
    /// gleicht danach erneut ab.
    private func reconcileLid() {
        guard !lidPromptRunning else {
            lid = lidWanted ? .pending : .off
            return
        }
        if lidWanted { enableLid() } else { releaseLid() }
    }

    private func enableLid() {
        guard lid != .on else { return }
        let current = LidAwake.sleepDisabled(pmsetOutput: Self.run(LidAwake.pmset, ["-g"]).output)
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
        lidPromptRunning = true
        Self.launch(LidAwake.osascript, LidAwake.osascriptArguments(disableSleep: disableSleep)) { [weak self] status in
            self?.lidPromptFinished(disableSleep: disableSleep, ok: status == 0)
        }
    }

    /// Antwort auf die Administrator-Frage. Abgebrochen gibt osascript einen
    /// Fehler (-128) zurueck; dann bleibt "Wach halten" ohne Deckel-Teil.
    private func lidPromptFinished(disableSleep: Bool, ok: Bool) {
        lidPromptRunning = false
        if disableSleep {
            guard ok else {
                log.notice("disablesleep 1: Administrator abgelehnt, wach nur aufgeklappt")
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
        FileManager.default.createFile(atPath: Self.lidMarker.path, contents: Data())
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
        let current = LidAwake.sleepDisabled(pmsetOutput: Self.run(LidAwake.pmset, ["-g"]).output)
        lidAwakeOwned = true
        if current == false || Self.sudoSleepDisabled(false) {
            lidReleased()
            return
        }
        askAdmin(disableSleep: false)
    }

    private static var lidMarker: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ApolloShell/lid-awake")
    }

    /// `sudo -n`: ohne Passwort oder gar nicht - wartet nie auf eine Eingabe.
    private static func sudoSleepDisabled(_ on: Bool) -> Bool {
        run(LidAwake.sudo, LidAwake.sudoArguments(disableSleep: on)).status == 0
    }

    private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func toggleWifi() {
        guard live, let interface = CWWiFiClient.shared().interface() else { return }
        let target = !interface.powerOn()
        do {
            try interface.setPower(target)
        } catch {
            log.error("WLAN schalten fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
        readWifi()
    }

    func toggleMicMute() {
        guard live,
              let device = Microphone.defaultInput(),
              let state = Microphone.muteState(of: device), state.settable
        else { return }
        let status = Microphone.setMuted(!state.muted, device: device)
        if status != noErr {
            log.error("Mikrofon stummschalten fehlgeschlagen: OSStatus \(status, privacy: .public)")
        }
        readMicrophone()
    }

    /// Bluetooth selbst schalten ginge nur ueber private Schnittstellen; der
    /// Knopf fuehrt deshalb direkt in die Einstellungen (Bereich gemessen:
    /// Bluetooth.appex meldet com.apple.BluetoothSettings).
    func openBluetoothSettings() {
        guard live, let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Das Panel bleibt offen: es faerbt sich mit um, das ist die
    /// Bestaetigung. Sofort umschalten (SkyLight meldet nichts zurueck),
    /// nach einer halben Sekunde den echten Zustand nachlesen.
    func toggleDarkMode() {
        guard live, let current = darkMode else { return }
        UtilitiesAppearance.setDark(!current)
        darkMode = !current
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.readAppearance()
        }
    }

    func toggleNightShift() {
        guard live, let client = nightShiftClient, let current = nightShift else { return }
        if !client.setEnabled(!current) {
            log.error("Night Shift schalten fehlgeschlagen")
        }
        readNightShift()
    }

    /// Apples Leiste fuer Bildschirmfoto und Aufnahme (⌘⇧5, bzw. was
    /// unter Tastaturkurzbefehle eingestellt ist). Ist der Kurzbefehl aus
    /// oder fehlt die Freigabe, dieselbe Leiste ueber Screenshot.app.
    func takeScreenshot() {
        guard live else { return }
        let key = UtilitiesKeys.symbolic(id: UtilitiesHotKey.screenshotToolbarID, fallback: .screenshotToolbarDefault)
        closePanel {
            if let key, UtilitiesKeys.post(key) { return }
            let app = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func showDesktop() {
        guard live, let key = UtilitiesKeys.symbolic(id: UtilitiesHotKey.showDesktopID, fallback: .showDesktopDefault)
        else { return }
        postAfterClose(key)
    }

    /// ⌃⌘Q geht an die App vorne (Apple-Menue) - deshalb muss das Panel
    /// vorher weg sein, sonst bekaeme es unser Panel.
    func lockScreen() {
        guard live else { return }
        postAfterClose(.lockScreen)
    }

    private func postAfterClose(_ key: UtilitiesHotKey) {
        closePanel {
            Task { @MainActor in
                try? await Task.sleep(for: Self.keyHandBack)
                UtilitiesKeys.post(key)
            }
        }
    }

    /// Apples Pipette (NSColorSampler, oeffentlich, keine Freigabe). Erst das
    /// Panel weg, damit man auch die Stelle darunter treffen kann.
    func pickColor() {
        guard live else { return }
        closePanel { [weak self] in
            guard let self else { return }
            let sampler = NSColorSampler()
            colorSampler = sampler
            sampler.show { color in
                // In sRGB wie im Web und in Figma; ohne Farbe (Esc) nil.
                let hex = color?.usingColorSpace(.sRGB).map {
                    UtilitiesColorHex.hex(red: Double($0.redComponent), green: Double($0.greenComponent),
                                          blue: Double($0.blueComponent))
                }
                // Stark gehalten, bis gewaehlt ist: das Modell lebt ohnehin
                // so lange wie die App.
                Task { @MainActor in self.colorPicked(hex) }
            }
        }
    }

    private func colorPicked(_ hex: String?) {
        colorSampler = nil
        guard let hex else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hex, forType: .string)
        onToast(ToastText.colorCopied(hex))
    }

    // MARK: - Neue Aktionen und eigene Knoepfe

    /// `pmset displaysleepnow`: nur die Bildschirme aus, der Mac laeuft
    /// weiter (Downloads, Musik). Braucht kein sudo. Erst das Panel weg -
    /// sonst stuende es beim Aufwachen noch halb da.
    func sleepDisplay() {
        guard live else { return }
        closePanel { Self.launch("/usr/bin/pmset", ["displaysleepnow"]) }
    }

    /// Jede normale App ausblenden (`NSRunningApplication.hide`, oeffentlich,
    /// ohne Freigabe) - die Shell selbst nie, sonst verschwaenden Leiste und
    /// Panels. Die Regel steht in `UtilitiesHideApps`.
    func hideApps(_ options: UtilitiesHideAppsOptions) {
        guard live else { return }
        closePanel {
            let own = ProcessInfo.processInfo.processIdentifier
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            for app in NSWorkspace.shared.runningApplications where UtilitiesHideApps.shouldHide(
                pid: app.processIdentifier, isRegular: app.activationPolicy == .regular, ownPID: own,
                frontmostPID: front, keepFrontmost: options.keepFrontmost
            ) {
                app.hide()
            }
        }
    }

    /// Wie ein Klick im Dock (`BarApps.open`). Panel erst zu: die App kommt
    /// nach vorne, und das Panel soll dann nicht darueber liegen.
    func openApp(_ options: UtilitiesAppOptions) {
        let bundleID = options.bundleID.trimmingCharacters(in: .whitespaces)
        guard live, !bundleID.isEmpty else { return }
        closePanel { BarApps.open(bundleID) }
    }

    /// Im Standardprogramm fuer die Adresse (Browser, Mail, ...).
    func openLink(_ options: UtilitiesLinkOptions) {
        guard live, let url = UtilitiesLink.url(from: options.url) else { return }
        closePanel { NSWorkspace.shared.open(url) }
    }

    /// `shortcuts run` als eigener Prozess, ohne darauf zu warten: ein
    /// Kurzbefehl kann Sekunden laufen oder nachfragen. Endet er mit Fehler,
    /// sagt es eine Kurzmeldung - sonst waere ein Klick ohne Wirkung ein
    /// Raetsel. So schaltet man z. B. einen Fokus, ohne private Schnittstellen.
    func runShortcut(_ options: UtilitiesShortcutOptions) {
        guard live, let arguments = UtilitiesShortcuts.runArguments(options) else { return }
        let name = options.title.isEmpty ? options.name : options.title
        closePanel { [weak self] in
            Self.launch(UtilitiesShortcuts.tool, arguments) { status in
                guard status != 0 else { return }
                self?.log.error("Kurzbefehl fehlgeschlagen: Status \(status, privacy: .public)")
                self?.onToast(ToastText.shortcutFailed(name))
            }
        }
    }

    /// Startet ein Werkzeug und wartet nicht; `done` bekommt den
    /// Rueckgabewert auf dem Hauptthread (-1: liess sich nicht starten).
    private static func launch(_ path: String, _ arguments: [String],
                               done: @escaping @MainActor (Int32) -> Void = { _ in }) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor in done(status) }
        }
        do {
            try process.run()
        } catch {
            done(-1)
        }
    }

    // MARK: - Ton

    /// Beim Ziehen am Regler. Sofort anzeigen, der Listener bestaetigt.
    /// Ueber 0 hebt es Stumm auf (VolumeMonitor.setVolume, wie die Tasten).
    func setVolume(_ value: Float) {
        guard live, volumeSettable, let monitor = volumeMonitor else { return }
        let clamped = min(max(value, 0), 1)
        monitor.setVolume(clamped)
        volume = clamped
        if clamped > 0 { outputMuted = false }
    }

    func toggleOutputMute() {
        guard live, muteSettable, let monitor = volumeMonitor else { return }
        monitor.setMuted(!outputMuted)
        readVolume()
    }

    func selectDevice(_ device: UInt32, scope: UtilitiesAudioScope) {
        guard live else { return }
        let status = UtilitiesAudioHardware.setDefault(device, scope)
        if status != noErr {
            log.error("Audiogeraet waehlen fehlgeschlagen: OSStatus \(status, privacy: .public)")
        }
        readAudioDevices()
        readVolume()
    }

    /// Setzt das Panel: oeffnet Nexus (Caelestias Knopf "Settings" oeffnet
    /// das eigene Einstellungsfenster). Die Systemeinstellungen sind von
    /// dort eine Zeile entfernt.
    @ObservationIgnored var onOpenSettings: () -> Void = {}

    func openSettings() {
        guard live else { return }
        onOpenSettings()
    }
}

/// Eine IOKit-Energiezusicherung "kein Ruhezustand bei Untaetigkeit" (wie
/// `caffeinate -i`: der Mac bleibt wach, der Bildschirm darf ausgehen).
///
/// Lebt genau so lange wie dieses Objekt. So kann sie nicht haengen bleiben:
/// Ausschalten, das Modell verschwindet, die App endet - jedes Mal geht sie
/// mit (beim Beenden raeumt macOS Zusicherungen des Prozesses ohnehin ab).
final class PowerAssertion {
    struct Failure: Error {
        let code: IOReturn
    }

    private let id: IOPMAssertionID

    init(reason: String) throws(Failure) {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { throw Failure(code: result) }
        self.id = id
    }

    deinit {
        IOPMAssertionRelease(id)
    }
}

/// Stummschaltung des Standard-Eingangs ueber CoreAudio.
///
/// Nur Eigenschaften lesen und setzen, kein Ton - deshalb ohne
/// Mikrofon-Freigabe. Gemessen 14.09.: das eingebaute "MacBook
/// Pro-Mikrofon" hat die Eigenschaft auf dem Hauptelement und sie ist
/// schreibbar. Andere Geraete (USB, Bluetooth) koennen sie fehlen lassen;
/// dann `nil` bzw. nicht schreibbar, und der Knopf ist aus.
enum Microphone {
    static func defaultInput() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func muteState(of device: AudioObjectID) -> (muted: Bool, settable: Bool)? {
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        var settable: DarwinBoolean = false
        let settableStatus = AudioObjectIsPropertySettable(device, &address, &settable)
        return (value != 0, settableStatus == noErr && settable.boolValue)
    }

    static func setMuted(_ muted: Bool, device: AudioObjectID) -> OSStatus {
        var address = muteAddress
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
