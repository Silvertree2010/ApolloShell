import AppKit
import ApolloShellCore
import Darwin
import os

@main
@MainActor
enum LauncherApp {
    // Kept static: NSApplication.delegate is weak.
    private static let delegate = AppDelegate()

    static func main() {
        // Image samples (--render-dashboard): draw and end before anything
        // of the shell starts.
        RenderMode.runIfRequested()
        #if DEBUG
        // Invisible self-test of the edit mode (--selftest-edit).
        EditModeSelfTest.runIfRequested()
        #endif
        // Only one instance: a second one shows the running one and ends
        // before it touches windows, shortcuts or Apple's Dock (SingleInstance).
        if SingleInstanceGuard.otherInstanceKeepsRunning() {
            SingleInstanceGuard.showRunningInstance()
            exit(0)
        }
        let app = NSApplication.shared
        app.delegate = delegate
        // No Dock icon, no menu bar of its own.
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
    /// Volume display; lives on its own (reacts to changes).
    private var osd: OSD?
    private var desktopClock: DesktopClock?
    /// Toasts at the bottom right and whoever sets them off.
    private var toaster: Toaster?
    private var toastWindow: ToastWindow?
    private var powerToasts: ToastPowerMonitor?
    private var audioToasts: ToastAudioMonitor?
    /// Settings of the shell (settings.json) - one instance for all, so a
    /// switch in Nexus takes hold everywhere right away.
    private var settings: ShellSettingsStore?
    /// Global keyboard shortcuts out of settings.json (Nexus > Shortcuts).
    private var hotKeys: HotKeyCenter?
    /// Settings window (Caelestia: Nexus).
    private var nexus: Nexus?
    /// One editing session of the bento pages (Nexus > Dashboard > Edit),
    /// shared between Nexus and the dashboard window.
    private var dashboardEditor: DashboardEditor?
    /// The global edit mode (Nexus > “Edit Interface”, spec section 4):
    /// dashboard pages and the control centre in one go.
    private var shellEditor: ShellEditor?
    /// Scrim, toolbar and gallery of the edit mode (task 3).
    private var editModeWindows: EditModeWindows?
    private var updates: UpdateController?
    private var themes: ThemeStore?
    /// Introduction on the first start.
    private var onboarding: Onboarding?
    /// Hide Apple's own Dock while ApolloShell runs.
    private var appleDockHiding: AppleDockHidingController?
    /// Catches SIGTERM (`launchctl stop`, say), so `terminate()` restores the
    /// Dock instead of leaving it hidden - the default SIGTERM handler does
    /// not clean up.
    private var sigterm: DispatchSourceSignal?
    /// A second start (Finder, Launchpad): the new instance ends right away
    /// and reports here, see `SingleInstanceGuard`.
    private var secondLaunchObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSigtermHandling()
        secondLaunchObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(SingleInstance.showNotification), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showAfterSecondLaunch() }
        }
        // Read in launcher-only mode as well: the launcher shortcut lives
        // there. Nothing is written until something changes.
        let settings = ShellSettingsStore(url: NexusPaths.live.settings)
        self.settings = settings
        let dashboardEditor = DashboardEditor(store: settings)
        self.dashboardEditor = dashboardEditor
        let shellEditor = ShellEditor(store: settings, dashboard: dashboardEditor)
        self.shellEditor = shellEditor
        // Themes: in launcher-only mode too, so the launcher takes the colors.
        themes = ThemeStore(settings: settings)
        let hotKeys = HotKeyCenter(store: settings)
        self.hotKeys = hotKeys
        appleDockHiding = AppleDockHidingController(settings: settings)

        let controller = LauncherController()
        self.controller = controller
        // While the global editing runs (task 6) the shortcut does nothing:
        // the launcher would have no room next to the scrim and the toolbar
        // anyway, and one more window above everything would only get in the way.
        hotKeys.setHandler(.launcher) { [weak controller, weak shellEditor] in
            guard shellEditor?.isEditing != true else { return }
            controller?.toggle()
        }

        // Launcher-only mode: bar, window watch, dashboard, utilities, OSD,
        // clock, toasts and introduction never come about - for the case that
        // someone wants only the launcher or one part of the shell gets in
        // the way. On: `defaults write <bundle ID> launcherOnly -bool true`,
        // then restart. The earlier key `nurLauncher` still counts.
        if LauncherOnlyFlag.isOn({ UserDefaults.standard.object(forKey: $0) }) {
            log.notice("Launcher-only mode: shell parts off")
            hotKeys.start()
            return
        }

        let autostart = OnboardingAutostartModel()
        let permissions = OnboardingPermissions()
        // Self-updating: starts Sparkle only when this installation may
        // renew itself (DMG, not Homebrew).
        let updates = UpdateController(settings: settings)
        self.updates = updates
        // The Homebrew build looks by itself; Sparkle has a schedule of its
        // own. Without this one would only learn of a new version when
        // opening Nexus > Updates.
        updates.checkInBackgroundIfDue()
        let nexus = Nexus(settings: settings, hotKeys: hotKeys, autostart: autostart, permissions: permissions,
                          updates: updates, themes: themes, shellEditor: shellEditor)
        self.nexus = nexus
        // While editing (task 6) the shortcut does nothing: Nexus stands
        // aside for exactly that reason (`ShellEditor.begin` orders it out),
        // and the shortcut should not fetch it back.
        hotKeys.setHandler(.nexus) { [weak nexus, weak shellEditor] in
            guard shellEditor?.isEditing != true else { return }
            nexus?.show()
        }
        let sidebar = Sidebar(settings: settings)
        self.sidebar = sidebar
        let sessionMenu = SessionMenu()
        self.sessionMenu = sessionMenu
        // The session menu cannot open while editing (task 6, spec section 4:
        // "the session menu cannot open") - logging out or shutting down in
        // the middle of an open working copy would be risky.
        sidebar.onPower = { [weak sessionMenu, weak shellEditor] in
            guard shellEditor?.isEditing != true else { return }
            sessionMenu?.toggle()
        }
        osd = OSD()
        desktopClock = DesktopClock(settings: settings)
        let dashboard = Dashboard(settings: settings, editor: dashboardEditor)
        self.dashboard = dashboard
        // The global edit mode starts on the page the dashboard shows right
        // now (or showed last); before the first opening `nil` - then
        // `ShellEditor.begin` takes the first page.
        shellEditor.dashboardStartPageID = { [weak dashboard] in dashboard?.currentPageID }
        sidebar.onDashboard = { [weak dashboard] in dashboard?.toggle() }
        sidebar.onDashboardTab = { [weak dashboard] tab in dashboard?.show(tab: tab) }
        hotKeys.setHandler(.dashboard) { [weak dashboard] in dashboard?.toggle() }
        // Weather without a place: the note in the dashboard opens Nexus
        // right at weather (Nexus > Dashboard).
        dashboard.onOpenNexus { [weak nexus] in nexus?.show(page: .bar) }
        let utilities = UtilitiesPanel(settings: settings, editor: shellEditor)
        self.utilities = utilities
        let editModeWindows = EditModeWindows(editor: shellEditor)
        self.editModeWindows = editModeWindows
        editModeWindows.utilitiesFrame = { [weak utilities] in utilities?.openFrame }
        editModeWindows.dashboardFrame = { [weak dashboard] in dashboard?.openFrame }
        sidebar.onUtilities = { [weak utilities] in utilities?.toggle() }
        // Caelestia: the settings button of the utilities opens Nexus.
        utilities.onOpenSettings = { [weak nexus] in nexus?.show() }
        hotKeys.setHandler(.utilities) { [weak utilities] in utilities?.toggle() }
        // All handlers set: register now (and match up again on changes in
        // Nexus).
        hotKeys.start()
        // Toasts: charger, battery warning levels, audio devices. None on
        // the start - only changes after it.
        let toaster = Toaster()
        self.toaster = toaster
        // The color picker of the utilities reports "Color Copied".
        utilities.onToast = { [weak toaster] content in toaster?.toast(content) }
        let toastWindow = ToastWindow(toaster: toaster, utilitiesHeight: utilities.height)
        self.toastWindow = toastWindow
        utilities.onVisibilityChange = { [weak toastWindow] open in toastWindow?.utilitiesChanged(open: open) }
        // Cards or rows changed (Nexus before 0.2, or live while editing,
        // task 5): the stack goes on sitting exactly above the panel, and
        // the toolbar of the edit mode goes on getting out of the panel's
        // way.
        utilities.onHeightChange = { [weak toastWindow, weak editModeWindows] height in
            toastWindow?.utilitiesHeight = height
            editModeWindows?.utilitiesHeightChanged()
        }
        powerToasts = ToastPowerMonitor(toaster: toaster, settings: settings)
        audioToasts = ToastAudioMonitor(toaster: toaster, settings: settings)

        // A fresh installation: the introduction explains the permissions and
        // then asks by itself - so the window watch does not ask on top.
        let showOnboarding = OnboardingRule.shouldShow(settings.settings, launcherOnly: false)
        // Keeps windows out of the strip of the bar. Without the
        // accessibility permission it does nothing.
        let windowGuard = WindowGuard(askForAccess: !showOnboarding)
        // Hides the bar on screens with a full-screen app.
        fullscreenMonitor = FullscreenMonitor {
            [weak sidebar, weak toaster, weak dashboard, weak utilities] fullscreenScreens in
            // Only the bar of the screen that is in full screen steps aside.
            sidebar?.setFullscreenScreens(fullscreenScreens)
            // The edge windows no longer open on the full-screen screen, on
            // the others they do. The toasts know no screen: they stay off as
            // soon as something is full screen anywhere.
            dashboard?.setFullscreen(fullscreenScreens)
            utilities?.setFullscreen(fullscreenScreens)
            toaster?.setHiddenForFullscreen(!fullscreenScreens.isEmpty)
        }
        self.windowGuard = windowGuard
        // The watch keeps the strip free on every screen that has a bar - and
        // learns of every change to that (a screen added, removed, the setting
        // in Nexus changed or a new width out of the theme).
        // dem Theme).
        windowGuard.setBarScreens(Set(sidebar.screens.map(\.key)), barWidth: Sidebar.width)
        sidebar.onScreensChange = { [weak windowGuard] screens in
            windowGuard?.setBarScreens(Set(screens.map(\.key)), barWidth: Sidebar.width)
        }

        let onboarding = Onboarding(settings: settings, hotKeys: hotKeys, autostart: autostart, permissions: permissions)
        self.onboarding = onboarding
        nexus.onShowOnboarding = { [weak onboarding] in onboarding?.show() }
        if showOnboarding { onboarding.show() }
    }

    /// ApolloShell opened a second time: show Nexus, or the launcher in
    /// launcher-only mode (no Nexus).
    private func showAfterSecondLaunch() {
        if let nexus {
            nexus.show()
        } else {
            controller?.toggle()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The Dock first: it is quick, and `utilities.shutdown()` may well
        // wait on an administrator prompt. If launchd cuts the end short,
        // the Dock is already back.
        appleDockHiding?.terminate()
        controller?.close()
        dashboard?.shutdown()
        utilities?.shutdown()
    }

    /// Ignores the default SIGTERM (which would otherwise end the process
    /// right away, without `applicationWillTerminate`) and hands over to
    /// `NSApp.terminate(nil)` on the main thread instead - the normal, clean
    /// way a Quit from the menu takes too.
    private func installSigtermHandling() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApp.terminate(nil)
        }
        source.resume()
        sigterm = source
    }
}
