import AppKit
import ApolloShellCore
import ApplicationServices
import Observation
import os

/// The frontmost app and the titles of its menu bar, for the Apple menu and
/// app menu blocks (spec topbar.md, "Etappe 5").
///
/// Titles per pid in a cache, so switching back to an app shows its menus at
/// once; read again in the background on every switch, when its focused
/// window changes (menus often follow the document) and every time one of
/// its menus opens. A menu itself is always read fresh on opening: "Open
/// Recent" and window lists change without telling anyone.
///
/// Without the accessibility permission there are no titles: the blocks
/// show the app's name alone, and a click offers the way to the permission.
@MainActor
@Observable
final class AppMenuModel {
    struct FrontApp: Equatable {
        let pid: pid_t
        let name: String
    }

    private(set) var app: FrontApp?
    /// The top-level titles as accessibility lists them: "Apple", the app
    /// menu ("Finder"), then File, Edit ... Empty without the permission.
    private(set) var titles: [String] = []
    /// The top-level menu that is open right now (its title stays lit).
    private(set) var openIndex: Int?

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var demand = BarDemand()
    @ObservationIgnored private var cache: [pid_t: [String]] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private lazy var watcher = FocusedWindowWatcher { [weak self] pid in
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let self, self.app?.pid == pid else { return }
                self.refreshTitles()
            }
        }
    }
    @ObservationIgnored private let log = Logger(category: "appmenu")

    init() {
        live = true
    }

    /// For the preview and the image samples: fixed, never asks anyone.
    init(preview app: FrontApp?, titles: [String]) {
        live = false
        self.app = app
        self.titles = titles
    }

    var paused: Bool {
        get { demand.paused }
        set { demand.paused = newValue; sync() }
    }

    func acquire() { demand.acquire(); sync() }
    func release() { demand.release(); sync() }

    /// The app menu's title: what the app calls itself in its menu bar
    /// ("Finder"), its name while that is not read yet.
    var appTitle: String {
        titles.count > 1 && !titles[1].isEmpty ? titles[1] : app?.name ?? ""
    }

    /// Titles after the app menu, with their index in the menu bar.
    var menuTitles: [(title: String, index: Int)] {
        titles.enumerated().dropFirst(2).map { ($0.element, $0.offset) }
    }

    private func sync() {
        guard live else { return }
        if demand.isActive, observers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                                queue: .main) { [weak self] note in
                let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.show(running) }
            })
            // A pid can come back for another app: forget what it had.
            observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                                queue: .main) { [weak self] note in
                let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    if let pid = running?.processIdentifier { self?.cache[pid] = nil }
                }
            })
            show(NSWorkspace.shared.frontmostApplication)
        } else if !demand.isActive, !observers.isEmpty {
            for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            observers = []
            watcher.stop()
        }
    }

    private func show(_ running: NSRunningApplication?) {
        let next = running.map { FrontApp(pid: $0.processIdentifier, name: $0.localizedName ?? $0.bundleIdentifier ?? "") }
        guard next != app else { return }
        app = next
        titles = next.flatMap { cache[$0.pid] } ?? []
        if let pid = next?.pid, AXIsProcessTrusted() { watcher.follow(pid) } else { watcher.stop() }
        refreshTitles()
    }

    /// Reads the titles in the background. An app that was just launched is
    /// active before its menu bar is filled: while only the Apple menu (or
    /// nothing) is there, it asks again, twice a second, a few times.
    private func refreshTitles(attempt: Int = 0) {
        guard let pid = app?.pid else { return }
        generation += 1
        let asked = generation
        Task { @MainActor in
            let read = await AXMenus.menuBarTitles(pid: pid)
            // A newer question was asked meanwhile, or another app came forward.
            guard asked == generation, app?.pid == pid else { return }
            if let read, !read.isEmpty {
                cache[pid] = read
                if titles != read { titles = read }
            } else if read == nil, !titles.isEmpty {
                // No permission (any more), or an app without a menu bar.
                titles = []
            }
            if let read, read.count <= 2, attempt < 6 {
                try? await Task.sleep(for: .milliseconds(500))
                guard asked == generation else { return }
                refreshTitles(attempt: attempt + 1)
            }
        }
    }

    // MARK: - Opening menus

    /// Opens top-level menu `index` (0 = Apple, 1 = the app menu) under
    /// `anchor`, read fresh.
    func open(index: Int, below anchor: NSView) {
        guard live else { return }
        guard AXIsProcessTrusted(), let pid = app?.pid else {
            AXMenuBuilder.popUp(AXMenuBuilder.permissionMenu(), below: anchor)
            return
        }
        Task { @MainActor in
            let menus = await AXMenus.menuBarMenus(pid: pid, indices: [index])
            guard let first = menus.first, !first.nodes.isEmpty else {
                log.notice("menu \(index, privacy: .public) of \(pid, privacy: .public) empty or gone")
                refreshTitles()
                return
            }
            show(AXMenuBuilder.menu(first.nodes) { path in Self.press(pid: pid, path: path) },
                 index: index, below: anchor)
        }
    }

    /// The menus that did not fit, as submenus of one "…" menu.
    func openOverflow(indices: [Int], below anchor: NSView) {
        guard live, !indices.isEmpty else { return }
        guard AXIsProcessTrusted(), let pid = app?.pid else {
            AXMenuBuilder.popUp(AXMenuBuilder.permissionMenu(), below: anchor)
            return
        }
        Task { @MainActor in
            let menus = await AXMenus.menuBarMenus(pid: pid, indices: indices)
            guard !menus.isEmpty else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            for entry in menus {
                let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
                item.submenu = AXMenuBuilder.menu(entry.nodes) { path in Self.press(pid: pid, path: path) }
                menu.addItem(item)
            }
            show(menu, index: nil, below: anchor)
        }
    }

    /// `popUp` returns when the menu closes; meanwhile the title stays lit.
    private func show(_ menu: NSMenu, index: Int?, below anchor: NSView) {
        openIndex = index
        AXMenuBuilder.popUp(menu, below: anchor)
        openIndex = nil
        refreshTitles()
    }

    private static func press(pid: pid_t, path: [AXMenuStep]) {
        Task { _ = await AXMenus.pressMenuBar(pid: pid, path: path) }
    }
}

/// Hears when the frontmost app's focused window changes - an app's menus
/// often follow its document. An AXObserver whose run loop source hangs
/// off the main run loop and only hands the pid on; the pattern of
/// `FrontWindowTitleWorker`.
///
/// `@unchecked Sendable`: its state is touched only on `queue`.
final class FocusedWindowWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: AppIdentity.scoped("appmenu-watch"))
    private let onChange: @Sendable (pid_t) -> Void
    private var observer: AXObserver?
    private var pid: pid_t = 0

    init(onChange: @escaping @Sendable (pid_t) -> Void) {
        self.onChange = onChange
    }

    func follow(_ pid: pid_t) {
        queue.async { self.attach(pid) }
    }

    func stop() {
        queue.async { self.detach() }
    }

    private func attach(_ pid: pid_t) {
        detach()
        self.pid = pid
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<FocusedWindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.queue.async { if watcher.pid != 0 { watcher.onChange(watcher.pid) } }
        }, &created) == .success, let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, app, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(created, app, kAXMainWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        pid = 0
    }
}
