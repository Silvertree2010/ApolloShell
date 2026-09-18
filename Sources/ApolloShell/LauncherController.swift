import AppKit
import ApolloShellCore
import QuartzCore
import SwiftUI
import os

/// Oeffnet und schliesst den Launcher: Panel unten mittig, dort wo frueher
/// der Dock sass. Apples Dock laesst der Launcher in Ruhe: frueher liess er
/// ihn beim Oeffnen wegfahren - einen dauerhaft ausgeblendeten Dock wuerde
/// das beim Schliessen wieder hervorholen.
@MainActor
final class LauncherController {
    /// Sichtbare Groesse.
    static let size = NSSize(width: 560, height: 520)
    /// Buendig an der Unterkante wie die Kantenfenster (frueher schwebte er
    /// 12 pt ueber dem Rand - ohne sichtbaren Apple-Dock wirkte das
    /// losgeloest): das Fenster ragt um den Eckenradius unter den Bildschirm
    /// - die unteren Ecken liegen ausserhalb (`EdgeDrawer`, Kante unten).
    static let cornerRadius: CGFloat = 26

    /// Startet der Launcher selbst eine App, meldet macOS das kurz danach
    /// noch einmal als Programmstart. Innerhalb dieses Fensters nicht doppelt
    /// zaehlen.
    private static let ownLaunchWindow: TimeInterval = 10

    private let model = LauncherModel()
    private let catalog = AppCatalog()
    private let usage = UsageStore()
    private let log = Logger(category: "controller")
    /// Waechst aus der Mitte der Unterkante heraus (`DrawerMotion.grow`),
    /// dort wo der Zeiger steht.
    private let drawer: EdgeDrawer<LauncherView>
    private var ownLaunches: [String: Date] = [:]

    init() {
        drawer = EdgeDrawer(edge: .bottom, size: Self.size, cornerRadius: Self.cornerRadius,
                            motion: .grow, rootView: LauncherView(model: model))
        drawer.onOpen = { [weak self] in
            guard let self else { return }
            self.model.reload(self.catalog.scan(), usage: self.usage.stats, pinned: PinnedApps.load())
        }
        model.onLaunch = { [weak self] app in self?.launch(app) }
        model.onClose = { [weak self] in self?.close() }
        model.onRightClick = { [weak self] app, view in self?.showMenu(for: app, at: view) }
        observeAppLaunches()
    }

    var isOpen: Bool { drawer.isOpen }

    func toggle() {
        drawer.toggle()
    }

    func open() {
        drawer.open()
    }

    func close() {
        drawer.close()
    }

    /// Rechtsklick auf eine Zeile: dasselbe Menue wie im Dock der Leiste,
    /// also das der App selbst, dazu Oeffnen und der Sprung in den
    /// Dateimanager. Das Lesen dauert einen Moment, deshalb geht das Menue
    /// erst danach auf.
    private func showMenu(for app: AppEntry, at view: NSView) {
        Task { @MainActor [weak self] in
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(ClosureMenuItem(String(localized: "Öffnen")) { [weak self] in self?.launch(app) })
            menu.addItem(.separator())

            var nodes: [DockMenuNode] = []
            if let bundleID = app.bundleID {
                nodes = await AppleDockMenu.snapshot(bundleID: bundleID)
            }
            if let bundleID = app.bundleID, !nodes.isEmpty {
                NativeAppMenu.append(nodes, to: menu, bundleID: bundleID)
                menu.addItem(.separator())
            } else if let running = LauncherController.runningApp(app) {
                // Apples Dock kennt die App nicht: die Befehle aus ihrer
                // eigenen Menueleiste.
                let commands = DockAppCommands.commands(pid: running.processIdentifier)
                for command in commands {
                    menu.addItem(ClosureMenuItem(command.title) { [weak self] in
                        self?.run(command.kind, of: app)
                    })
                }
                if !commands.isEmpty { menu.addItem(.separator()) }
            }

            menu.addItem(ClosureMenuItem(String(localized: "Im Finder zeigen")) { [weak self] in
                self?.close()
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            })
            NativeAppMenu.popUp(menu, at: view)
        }
    }

    /// Die laufende Instanz zu einem Eintrag, `nil` wenn sie nicht laeuft.
    private static func runningApp(_ app: AppEntry) -> NSRunningApplication? {
        guard let bundleID = app.bundleID else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    /// Einen Befehl der App ausfuehren - derselbe Weg wie im Dock-Menue:
    /// den Menuepunkt ueber die Bedienungshilfen druecken.
    private func run(_ kind: DockCommandKind, of app: AppEntry) {
        close()
        guard let running = LauncherController.runningApp(app),
              let command = DockAppCommands.commands(pid: running.processIdentifier).first(where: { $0.kind == kind })
        else {
            // Laeuft sie doch nicht mehr: dann eben normal starten.
            launch(app)
            return
        }
        usage.record(app.usageKey)
        DockAppCommands.press(command, of: running)
    }

    private func launch(_ app: AppEntry) {
        close()
        usage.record(app.usageKey)
        ownLaunches[app.usageKey] = Date()
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init()) { [log] _, error in
            if let error {
                log.error("Start fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Nutzung auch ausserhalb des Launchers zaehlen

    /// Starts ueber Dock, Finder oder Spotlight zaehlen fuer die Sortierung
    /// genauso. Nur echte Apps mit Fenster, keine Hintergrunddienste.
    private func observeAppLaunches() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let app, app.activationPolicy == .regular,
                  let key = app.bundleIdentifier ?? app.bundleURL?.path
            else { return }
            MainActor.assumeIsolated { self?.recordExternalLaunch(key) }
        }
    }

    private func recordExternalLaunch(_ key: String) {
        if let own = ownLaunches[key], Date().timeIntervalSince(own) < Self.ownLaunchWindow {
            return
        }
        usage.record(key)
    }
}
