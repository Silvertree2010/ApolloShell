import AppKit
import ApolloProviders
import ApolloShellCore
import ApplicationServices
import os

@MainActor
final class SystemMenuBarSource: MenuBarSource {
    static let shared = SystemMenuBarSource()

    private(set) var pid: pid_t?
    private var name = ""
    private var bundleID: String?
    private var titles: [String] = []
    private var cache: [pid_t: [String]] = [:]
    private var observers: [NSObjectProtocol] = []
    private var handler: (@MainActor (MenuBarState?) -> Void)?
    private var generation = 0
    private lazy var watcher = FocusedWindowWatcher { [weak self] pid in
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let self, self.pid == pid else { return }
                self.refreshTitles()
            }
        }
    }

    func start(_ handler: @escaping @MainActor (MenuBarState?) -> Void) {
        self.handler = handler
        guard observers.isEmpty else { return deliver() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.show(running) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let pid = running?.processIdentifier { self?.cache[pid] = nil }
            }
        })
        show(NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
        handler = nil
        pid = nil
        watcher.stop()
    }

    func press(_ path: [String]) async -> Bool {
        guard let pid else { return false }
        return await AXMenus.pressMenuBar(pid: pid, titles: path)
    }

    func menus(_ indices: [Int]) async -> [(title: String, index: Int, nodes: [AppMenuNode])] {
        guard let pid else { return [] }
        return await AXMenus.menuBarMenus(pid: pid, indices: indices)
    }

    func press(steps: [AXMenuStep]) {
        guard let pid else { return }
        Task { _ = await AXMenus.pressMenuBar(pid: pid, path: steps) }
    }

    func menuClosed() {
        refreshTitles()
    }

    private func show(_ running: NSRunningApplication?) {
        let next = running?.processIdentifier
        guard next != pid || running?.localizedName != name else { return }
        pid = next
        name = running?.localizedName ?? running?.bundleIdentifier ?? ""
        bundleID = running?.bundleIdentifier
        titles = next.flatMap { cache[$0] } ?? []
        if let next, AXIsProcessTrusted() { watcher.follow(next) } else { watcher.stop() }
        deliver()
        refreshTitles()
    }

    private func deliver() {
        guard let handler else { return }
        handler(pid == nil ? nil : MenuBarState(appName: name, bundleID: bundleID, titles: titles, trusted: AXIsProcessTrusted()))
    }

    private func refreshTitles(attempt: Int = 0) {
        guard let pid else { return }
        generation += 1
        let asked = generation
        Task { @MainActor in
            let read = await AXMenus.menuBarTitles(pid: pid)
            guard asked == generation, self.pid == pid else { return }
            if let read, !read.isEmpty {
                cache[pid] = read
                if titles != read { titles = read; deliver() }
            } else if read == nil, !titles.isEmpty {
                titles = []
                deliver()
            }
            if let read, read.count <= 2, attempt < 6 {
                try? await Task.sleep(for: .milliseconds(500))
                guard asked == generation else { return }
                refreshTitles(attempt: attempt + 1)
            }
        }
    }
}

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
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
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
