import AppKit
import ApolloShellCore
import QuartzCore
import SwiftUI
import os

/// Opens and closes the launcher: a panel at the bottom centre, where the Dock
/// used to sit. The launcher leaves Apple's Dock in peace: it used to make it
/// slide away on opening - which would have fetched a permanently hidden Dock
/// back out on closing.
@MainActor
final class LauncherController {
    /// The visible size.
    static let size = NSSize(width: 560, height: 520)
    /// Flush with the bottom edge like the edge windows (it used to float 12 pt
    /// above the edge - without a visible Apple Dock that looked detached): the
    /// window sticks out below the screen by the corner radius - the bottom
    /// corners lie outside (`EdgeDrawer`, the bottom edge).
    static let cornerRadius: CGFloat = 26

    /// When the launcher starts an app itself, macOS reports that shortly
    /// afterwards as an app launch once more. Do not count it twice within this
    /// window.
    private static let ownLaunchWindow: TimeInterval = 10

    private let model = LauncherModel()
    private let catalog = AppCatalog()
    private let usage = UsageStore()
    private let log = Logger(category: "controller")
    /// Grows out of the middle of the bottom edge (`DrawerMotion.grow`), where
    /// the pointer stands.
    private let drawer: EdgeDrawer<LauncherView>
    private var ownLaunches: [String: Date] = [:]

    init() {
        drawer = EdgeDrawer(edge: .bottom, size: Self.size, cornerRadius: Self.cornerRadius,
                            motion: .grow, rootView: LauncherView(model: model))
        drawer.onOpen = { [weak self] in
            guard let self else { return }
            self.model.reload(self.catalog.scan(), usage: self.usage.stats, pinned: PinnedApps.load())
        }
        model.onActivate = { [weak self] row in self?.activate(row) }
        model.themes = {
            guard let store = ThemeStore.shared else { return [] }
            return [(id: nil, title: String(localized: "No Theme"), current: store.selection == nil)]
                + store.available.map { (id: $0.identifier, title: $0.title, current: store.selection == $0.identifier) }
        }
        model.onClose = { [weak self] in self?.close() }
        model.onRightClick = { [weak self] app, view in self?.showMenu(for: app, at: view) }
        model.onMovePin = { [weak self] id, target in self?.changePins { $0.move(id, onto: target) } }
        observeAppLaunches()
    }

    var isOpen: Bool { drawer.isOpen }

    /// `>` Settings: opens the Nexus panel (set by the app delegate).
    var onOpenSettings: () -> Void = {}
    /// Something went wrong where nobody would see it (a wallpaper that
    /// would not set): a toast.
    var onReport: (_ title: String, _ message: String) -> Void = { _, _ in }

    func toggle() {
        drawer.toggle()
    }

    func open() {
        drawer.open()
    }

    func close() {
        drawer.close()
    }

    /// A right click on a row: the same menu as in the Dock of the bar, so the
    /// one of the app itself, plus Open and the jump into the file manager. The
    /// reading takes a moment, so the menu only opens afterwards.
    /// erst danach auf.
    private func showMenu(for app: AppEntry, at view: NSView) {
        Task { @MainActor [weak self] in
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(ClosureMenuItem(String(localized: "Open")) { [weak self] in self?.launch(app) })
            menu.addItem(.separator())

            var nodes: [DockMenuNode] = []
            if let bundleID = app.bundleID {
                nodes = await AppleDockMenu.snapshot(bundleID: bundleID)
            }
            if let bundleID = app.bundleID, !nodes.isEmpty {
                NativeAppMenu.append(nodes, to: menu, bundleID: bundleID)
                menu.addItem(.separator())
            } else if let running = LauncherController.runningApp(app) {
                // Apple's Dock does not know the app: the commands out of its
                // own menu bar.
                let commands = DockAppCommands.commands(pid: running.processIdentifier)
                for command in commands {
                    menu.addItem(ClosureMenuItem(command.title) { [weak self] in
                        self?.run(command.kind, of: app)
                    })
                }
                if !commands.isEmpty { menu.addItem(.separator()) }
            }

            for item in self?.pinItems(for: app) ?? [] { menu.addItem(item) }
            menu.addItem(ClosureMenuItem(String(localized: "Show in Finder")) { [weak self] in
                self?.close()
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            })
            NativeAppMenu.popUp(menu, at: view)
        }
    }

    /// Pinning where the app stands (design/2026-09-21-menubar-nexus.md,
    /// task 4). Needs no accessibility: only pinned.json changes.
    private func pinItems(for app: AppEntry) -> [NSMenuItem] {
        guard let id = app.bundleID else { return [] }
        if model.isPinned(app) {
            return [ClosureMenuItem(String(localized: "Unpin")) { [weak self] in
                self?.changePins { $0.remove(id) }
            }]
        }
        let pinned = PinnedList(model.pinned)
        let item = ClosureMenuItem(pinned.isFull ? String(localized: "Pin (\(PinnedList.limit) pinned already)")
                                                 : String(localized: "Pin")) { [weak self] in
            self?.changePins { $0.add(id) }
        }
        item.isEnabled = !pinned.isFull
        return [item]
    }

    private func changePins(_ change: (inout PinnedList) -> Void) {
        guard let ids = PinnedApps.update(change) else { return }
        model.setPinned(ids)
    }

    /// The running instance for an entry, `nil` when it is not running.
    private static func runningApp(_ app: AppEntry) -> NSRunningApplication? {
        guard let bundleID = app.bundleID else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    /// Carry out a command of the app - the same way as in the Dock menu: press
    /// the menu item through the accessibility API.
    private func run(_ kind: DockCommandKind, of app: AppEntry) {
        close()
        guard let running = LauncherController.runningApp(app),
              let command = DockAppCommands.commands(pid: running.processIdentifier).first(where: { $0.kind == kind })
        else {
            // It is not running after all: then start it normally.
            launch(app)
            return
        }
        usage.record(app.usageKey)
        DockAppCommands.press(command, of: running)
    }

    /// Return or a click on a row.
    private func activate(_ row: LauncherRow) {
        switch row {
        case .app(let app):
            launch(app)
        case .action(let action):
            run(action)
        case .calculation(let result):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result, forType: .string)
            close()
        case .theme(let id, _, _):
            close()
            ThemeStore.shared?.select(id)
        case .wallpaper(let wallpaper):
            close()
            if !wallpaper.apply() {
                onReport(String(localized: "Wallpaper not set"), wallpaper.name)
            }
        case .note:
            break
        }
    }

    /// The `>` actions. The three with a mode fill in the keyword instead
    /// (as in Caelestia); log out, restart and shut down want a second
    /// Return.
    private func run(_ action: LauncherAction) {
        if let keyword = action.completion {
            model.query = "\(LauncherQuery.actionPrefix)\(keyword) "
            return
        }
        if action.needsConfirmation, model.armed != action {
            model.armed = action
            return
        }
        close()
        switch action {
        case .light: UtilitiesAppearance.setDark(false)
        case .dark: UtilitiesAppearance.setDark(true)
        case .settings: onOpenSettings()
        case .randomWallpaper:
            if let wallpaper = AppleWallpaper.all().filter(\.isAvailable).randomElement(), !wallpaper.apply() {
                onReport(String(localized: "Wallpaper not set"), wallpaper.name)
            }
        case .lock:
            // Ctrl-Cmd-Q goes to the app in front: only once the launcher
            // is gone, or it would land in our panel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { UtilitiesKeys.post(.lockScreen) }
        case .sleep: runSession(.sleep)
        case .logOut: runSession(.logOut)
        case .restart: runSession(.restart)
        case .shutDown: runSession(.shutDown)
        case .calculator, .theme, .wallpaper: break
        }
    }

    /// The same commands as the session menu, after the launcher has left.
    private func runSession(_ action: SessionAction) {
        let command = action.command
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            _ = Subprocess.launch(command.executable, command.arguments)
        }
    }

    /// A click (or Return) on an app. Not running: start it. Running and able
    /// to open more windows (a plain ⌘N in its menu bar): a new window, on
    /// the current desktop. Running with no such command: its windows come
    /// forward, which is what opening it again does.
    ///
    /// The ⌘N lookup goes through Accessibility; without the permission it
    /// finds nothing, and the app is simply brought forward as before.
    private func launch(_ app: AppEntry) {
        close()
        usage.record(app.usageKey)
        if let running = LauncherController.runningApp(app),
           let newWindow = DockAppCommands.commands(pid: running.processIdentifier).first(where: \.isNewWindow) {
            DockAppCommands.press(newWindow, of: running)
            return
        }
        ownLaunches[app.usageKey] = Date()
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init()) { [log] _, error in
            if let error {
                log.error("Start fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Counting use outside the launcher too

    /// Launches through the Dock, the Finder or Spotlight count for the order
    /// just the same. Only real apps with a window, no background services.
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
