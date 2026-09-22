import AppKit
import ApolloShellCore
import Darwin
import os

@main
@MainActor
enum LauncherApp {
    // Statisch gehalten: NSApplication.delegate ist weak.
    private static let delegate = AppDelegate()

    static func main() {
        // Nur eine Instanz: eine zweite zeigt die laufende und endet, bevor
        // sie Fenster, Kuerzel oder Apples Dock anfasst (SingleInstance).
        if SingleInstanceGuard.otherInstanceKeepsRunning() {
            SingleInstanceGuard.showRunningInstance()
            exit(0)
        }
        let app = NSApplication.shared
        app.delegate = delegate
        // Kein Dock-Icon, keine eigene Menueleiste.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(category: "app")
    private var controller: LauncherController?
    private var sidebar: Sidebar?
    private var windowGuard: WindowGuard?
    private var fullscreenMonitor: FullscreenMonitor?
    private var sessionMenu: SessionMenu?
    private var dashboard: Dashboard?
    private var utilities: UtilitiesPanel?
    /// Lautstaerke-Anzeige; lebt fuer sich (reagiert auf Aenderungen).
    private var osd: OSD?
    private var desktopClock: DesktopClock?
    /// Kurzmeldungen unten rechts und wer sie ausloest.
    private var toaster: Toaster?
    private var toastWindow: ToastWindow?
    private var powerToasts: ToastPowerMonitor?
    private var audioToasts: ToastAudioMonitor?
    /// Einstellungen der Shell (settings.json) - eine Instanz fuer alle, damit
    /// ein Schalter in Nexus ueberall sofort gilt.
    private var settings: ShellSettingsStore?
    /// Globale Tastenkuerzel aus settings.json (Nexus > Tastenkürzel).
    private var hotKeys: HotKeyCenter?
    /// Einstellungsfenster (Caelestia: Nexus).
    private var nexus: Nexus?
    private var updates: UpdateController?
    private var crashReporter: CrashReporter?
    private var themes: ThemeStore?
    /// Einfuehrung beim ersten Start.
    private var onboarding: Onboarding?
    /// Apples eigenes Dock ausblenden, solange ApolloShell laeuft.
    private var appleDockHiding: AppleDockHidingController?
    /// Faengt SIGTERM ab (z. B. `launchctl stop`), damit `terminate()` das
    /// Dock wiederherstellt statt es versteckt zurueckzulassen - der
    /// Standard-Handler von SIGTERM raeumt nicht auf.
    private var sigterm: DispatchSourceSignal?
    /// Zweiter Start (Finder, Launchpad): Die neue Instanz endet sofort und
    /// meldet sich hier, siehe `SingleInstanceGuard`.
    private var secondLaunchObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSigtermHandling()
        secondLaunchObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(SingleInstance.showNotification), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showAfterSecondLaunch() }
        }
        // Auch im Nur-Launcher-Modus gelesen: das Launcher-Kuerzel steht
        // dort. Geschrieben wird erst, wenn sich etwas aendert.
        let settings = ShellSettingsStore(url: NexusPaths.live.settings)
        self.settings = settings
        // Themes: auch im Nur-Launcher-Modus, damit der Launcher mitfaerbt.
        themes = ThemeStore(settings: settings)
        let hotKeys = HotKeyCenter(store: settings)
        self.hotKeys = hotKeys
        appleDockHiding = AppleDockHidingController(settings: settings)

        let controller = LauncherController()
        self.controller = controller
        hotKeys.setHandler(.launcher) { [weak controller] in controller?.toggle() }

        // Nur-Launcher-Modus: Leiste, Fensterwache, Dashboard, Utilities,
        // OSD, Uhr, Toasts und Einfuehrung entstehen gar nicht - fuer den
        // Fall, dass jemand nur den Launcher will oder ein Teil der Shell
        // stoert. Ein: `defaults write <Bundle-ID> launcherOnly -bool true`,
        // dann neu starten. Der fruehere Schluessel `nurLauncher` gilt weiter.
        if LauncherOnlyFlag.isOn({ UserDefaults.standard.object(forKey: $0) }) {
            log.notice("Nur-Launcher-Modus: Shell-Teile aus")
            hotKeys.start()
            return
        }

        let autostart = OnboardingAutostartModel()
        let permissions = OnboardingPermissions()
        // Selbstaktualisierung: startet Sparkle nur, wenn diese Installation
        // sich selbst erneuern darf (DMG, nicht Homebrew).
        let updates = UpdateController(settings: settings)
        self.updates = updates
        // Die Homebrew-Fassung sucht selbst; Sparkle hat seinen eigenen
        // Zeitplan. Ohne das hier erfuehre man von einer neuen Fassung erst
        // beim Oeffnen von Nexus > Updates.
        updates.checkInBackgroundIfDue()
        let nexus = Nexus(settings: settings, hotKeys: hotKeys, autostart: autostart, permissions: permissions,
                          updates: updates, themes: themes)
        self.nexus = nexus
        hotKeys.setHandler(.nexus) { [weak nexus] in nexus?.show() }
        let sidebar = Sidebar(settings: settings)
        self.sidebar = sidebar
        let sessionMenu = SessionMenu()
        self.sessionMenu = sessionMenu
        sidebar.onPower = { [weak sessionMenu] in sessionMenu?.toggle() }
        osd = OSD()
        desktopClock = DesktopClock(settings: settings)
        let dashboard = Dashboard(settings: settings)
        self.dashboard = dashboard
        sidebar.onDashboard = { [weak dashboard] in dashboard?.toggle() }
        sidebar.onDashboardTab = { [weak dashboard] tab in dashboard?.show(tab: tab) }
        hotKeys.setHandler(.dashboard) { [weak dashboard] in dashboard?.toggle() }
        // Wetter ohne Ort: der Hinweis im Dashboard oeffnet Nexus direkt bei
        // Wetter (Nexus > Dashboard).
        dashboard.onOpenNexus { [weak nexus] in nexus?.show(page: .dashboard) }
        let utilities = UtilitiesPanel(settings: settings)
        self.utilities = utilities
        sidebar.onUtilities = { [weak utilities] in utilities?.toggle() }
        // Caelestia: der Einstellungs-Knopf der Utilities oeffnet Nexus.
        utilities.onOpenSettings = { [weak nexus] in nexus?.show() }
        hotKeys.setHandler(.utilities) { [weak utilities] in utilities?.toggle() }
        // Alle Handler gesetzt: jetzt registrieren (und bei Aenderungen in
        // Nexus neu abgleichen).
        hotKeys.start()
        // Kurzmeldungen: Ladegeraet, Akku-Warnstufen, Audiogeraete. Beim
        // Start keine - erst Aenderungen danach.
        let toaster = Toaster()
        self.toaster = toaster
        // Farbpipette der Utilities meldet "Color Copied".
        utilities.onToast = { [weak toaster] content in toaster?.toast(content) }
        let toastWindow = ToastWindow(toaster: toaster, utilitiesHeight: utilities.height)
        self.toastWindow = toastWindow
        utilities.onVisibilityChange = { [weak toastWindow] open in toastWindow?.utilitiesChanged(open: open) }
        // Karten oder Reihen in Nexus geaendert: der Stapel sitzt weiter
        // genau ueber dem Panel.
        utilities.onHeightChange = { [weak toastWindow] height in toastWindow?.utilitiesHeight = height }
        powerToasts = ToastPowerMonitor(toaster: toaster, settings: settings)
        audioToasts = ToastAudioMonitor(toaster: toaster, settings: settings)

        // Frische Installation: die Einfuehrung erklaert die Freigaben und
        // fragt dann selbst - die Fensterwache fragt deshalb nicht zusaetzlich.
        let showOnboarding = OnboardingRule.shouldShow(settings.settings, launcherOnly: false)
        // Haelt Fenster aus dem Streifen der Leiste. Ohne
        // Bedienungshilfen-Freigabe tut sie nichts.
        let windowGuard = WindowGuard(askForAccess: !showOnboarding)
        // Blendet die Leiste auf Bildschirmen mit Vollbild-App aus.
        fullscreenMonitor = FullscreenMonitor {
            [weak sidebar, weak toaster, weak dashboard, weak utilities] fullscreenScreens in
            // Nur die Leiste des Bildschirms tritt ab, auf dem Vollbild ist.
            sidebar?.setFullscreenScreens(fullscreenScreens)
            // Kantenfenster klappen auf dem Vollbild-Bildschirm nicht mehr
            // auf, auf den anderen schon. Die Kurzmeldungen kennen keinen
            // Bildschirm: sie bleiben aus, sobald irgendwo Vollbild ist.
            dashboard?.setFullscreen(fullscreenScreens)
            utilities?.setFullscreen(fullscreenScreens)
            toaster?.setHiddenForFullscreen(!fullscreenScreens.isEmpty)
        }
        self.windowGuard = windowGuard
        // Die Wache haelt den Streifen auf jedem Bildschirm frei, der eine
        // Leiste hat - und erfaehrt jede Aenderung daran (Bildschirm dazu,
        // weg, die Einstellung in Nexus geaendert oder eine neue Breite aus
        // dem Theme).
        windowGuard.setBarScreens(Set(sidebar.screens.map(\.key)), barWidth: Sidebar.width)
        sidebar.onScreensChange = { [weak windowGuard] screens in
            windowGuard?.setBarScreens(Set(screens.map(\.key)), barWidth: Sidebar.width)
        }

        let onboarding = Onboarding(settings: settings, hotKeys: hotKeys, autostart: autostart, permissions: permissions)
        self.onboarding = onboarding
        nexus.onShowOnboarding = { [weak onboarding] in onboarding?.show() }
        if showOnboarding { onboarding.show() }

        // Abgestuerzt seit dem letzten Mal? Nicht zusammen mit der
        // Einfuehrung - zwei Fenster auf einmal waeren zu viel.
        let crashReporter = CrashReporter(settings: settings)
        self.crashReporter = crashReporter
        if !showOnboarding { crashReporter.checkAfterLaunch() }
    }

    /// ApolloShell ein zweites Mal geoeffnet: Nexus zeigen, im
    /// Nur-Launcher-Modus (kein Nexus) den Launcher.
    private func showAfterSecondLaunch() {
        if let nexus {
            nexus.show()
        } else {
            controller?.toggle()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Das Dock zuerst: geht schnell, und `utilities.shutdown()` wartet
        // womoeglich auf eine Administrator-Frage. Bricht launchd das Ende
        // dabei hart ab, ist das Dock schon wieder da.
        appleDockHiding?.terminate()
        controller?.close()
        dashboard?.shutdown()
        utilities?.shutdown()
    }

    /// Ignoriert das Standard-SIGTERM (sonst beendet es den Prozess sofort,
    /// ohne `applicationWillTerminate`) und leitet stattdessen auf dem
    /// Hauptthread an `NSApp.terminate(nil)` weiter - der normale, saubere
    /// Weg, ueber den auch ein Quit aus dem Menue laeuft.
    private func installSigtermHandling() {
        signal(SIGTERM, SIG_IGN)
        // Nicht auf `.main`: waehrend eines modalen Dialogs (z. B. der
        // Absturzbericht-Frage) arbeitet AppKit den Main-Queue nicht ab, das
        // Signal bliebe liegen. Deshalb eigener Queue und von dort ausdruecklich
        // auch im Modal-Modus auf den Main-Runloop (gemessen 22.09. in der VM).
        let source = DispatchSource.makeSignalSource(signal: SIGTERM,
                                                     queue: DispatchQueue(label: AppIdentity.scoped("sigterm")))
        source.setEventHandler {
            RunLoop.main.perform(inModes: [.common, .modalPanel]) {
                MainActor.assumeIsolated {
                    // Ein offener modaler Dialog laesst `terminate` sonst ins
                    // Leere laufen: erst abbrechen, dann beenden.
                    if NSApp.modalWindow != nil {
                        NSApp.abortModal()
                        DispatchQueue.main.async { NSApp.terminate(nil) }
                    } else {
                        NSApp.terminate(nil)
                    }
                }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        source.resume()
        sigterm = source
    }
}
