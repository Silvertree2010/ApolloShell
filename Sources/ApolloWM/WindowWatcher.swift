import AppKit
import ApplicationServices

/// Keeps the engine's window set in sync with reality: new windows get tiled,
/// closed, minimized or hidden ones leave the layout.
///
/// Accessibility notifications (window created, destroyed, minimized, app
/// hidden) and app launch/quit only trigger a reconcile; the reconcile itself
/// compares the engine against a fresh window scan. One code path, and a
/// missed notification is caught by the slow safety scan.
@MainActor
public final class WindowWatcher {
    private let engine: TilingEngine
    private var observers: [pid_t: AXObserver] = [:]
    private var watchedWindows: Set<CGWindowID> = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var safetyTimer: Timer?
    /// When a window was first seen invisible. It loses its tile only after
    /// staying invisible for a while, so brief moments (Mission Control,
    /// Show Desktop) do not shuffle the layout.
    private var invisibleSince: [CGWindowID: CFTimeInterval] = [:]
    private let invisibleGrace: CFTimeInterval = 1.5

    public var log: (String) -> Void = { print($0) }

    public init(engine: TilingEngine) {
        self.engine = engine
    }

    public func start() {
        if let space = Spaces.current() { engine.switchSpace(to: space) }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app.processIdentifier)
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    guard let self, let pid else { return }
                    self.observe(pid)
                    self.reconcileSoon()
                }
            },
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let space = Spaces.current() else { return }
                    self.engine.switchSpace(to: space)
                    // Windows of the new desktop are on screen only after the switch animation.
                    self.reconcileSoon()
                }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    guard let self, let pid else { return }
                    self.observers[pid] = nil
                    self.reconcile()
                }
            },
        ]
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // A full scan costs a few ms per app; never during a glide or drag.
                guard let self, !self.engine.isAnimating, self.engine.dragging == nil else { return }
                self.reconcile()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
        watchNewWindows()
    }

    // MARK: Notifications

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil, pid != getpid() else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, watcherCallback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXWindowMiniaturizedNotification,
                     kAXWindowDeminiaturizedNotification, kAXApplicationHiddenNotification,
                     kAXApplicationShownNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(observer, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
    }

    /// Destroyed notifications are only reliable when registered on the window itself.
    private func watchNewWindows() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for (id, window) in engine.windows where !watchedWindows.contains(id) {
            guard let observer = observers[window.pid] else { continue }
            AXObserverAddNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString, refcon)
            watchedWindows.insert(id)
        }
        watchedWindows.formIntersection(engine.windows.keys)
    }

    fileprivate func handle(_ notification: String) {
        if notification == kAXWindowCreatedNotification || notification == kAXWindowDeminiaturizedNotification
            || notification == kAXApplicationShownNotification {
            // Fresh windows often have no frame or subrole yet; look again shortly.
            reconcileSoon()
        } else {
            reconcile()
        }
    }

    private func reconcileSoon() {
        for delay in [0.05, 0.25, 0.8, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.reconcile() }
            }
        }
    }

    // MARK: Reconcile

    /// What a background scan learned about one tracked window that was
    /// not found on screen.
    private struct Missing: Sendable {
        var closed = false
        var minimized = false
        var appHidden = false
    }

    private var scanning = false
    private var rescan = false

    /// Compares the engine with a fresh window scan. The scan asks every app
    /// for its windows, which is a round trip each, so it runs off the main
    /// thread (measured: it blocked the main thread for 30-80 ms after every
    /// desktop switch); only the result is applied here.
    public func reconcile() {
        if scanning {
            rescan = true
            return
        }
        scanning = true
        let area = engine.screenArea
        let tracked = engine.windows
        Task.detached(priority: .userInitiated) { [weak self] in
            let found = WindowDiscovery.tileableWindows(in: area)
            let foundIDs = Set(found.map(\.windowID))
            var spaces: [CGWindowID: SpaceID] = [:]
            var missing: [CGWindowID: Missing] = [:]
            for (id, window) in tracked {
                spaces[id] = Spaces.of(id)
                guard !foundIDs.contains(id) else { continue }
                var state = Missing()
                if window.position == nil {
                    state.closed = true
                } else if window.element.bool(kAXMinimizedAttribute) == true {
                    state.minimized = true
                } else if AXUIElementCreateApplication(window.pid).bool(kAXHiddenAttribute) == true {
                    state.appHidden = true
                }
                missing[id] = state
            }
            await MainActor.run { [found, spaces, missing] in
                guard let self else { return }
                self.apply(found: found, spaces: spaces, missing: missing)
                self.scanning = false
                if self.rescan {
                    self.rescan = false
                    self.reconcile()
                }
            }
        }
    }

    private func apply(found: [AXWindow], spaces: [CGWindowID: SpaceID], missing: [CGWindowID: Missing]) {
        let foundIDs = Set(found.map(\.windowID))

        // Windows the user moved to another desktop follow there.
        for id in engine.windows.keys where id != engine.dragging {
            if let space = spaces[id], space != engine.desk(of: id)?.space {
                engine.move(id, to: space)
            }
        }

        // Everything on this desktop gone at once means Show Desktop or
        // Mission Control pushed the windows aside; they come back, so they
        // keep their tiles.
        let shown = engine.tree.ids
        let allAside = !shown.isEmpty && shown.allSatisfy { !foundIDs.contains($0) }

        for (id, state) in missing where engine.windows[id] != nil && id != engine.dragging {
            guard let window = engine.windows[id] else { continue }
            // Not on screen. It keeps its tile only while it lives on another
            // desktop or is parked on another workspace. Apps like WhatsApp
            // or System Settings keep closed windows alive but invisible;
            // those must not hold a tile.
            let home = engine.desk(of: id)
            let elsewhere = home != nil && home != engine.desk
            let reason: String?
            if state.closed {
                reason = "closed"
            } else if state.minimized {
                reason = "minimized"
            } else if state.appHidden {
                reason = "app hidden"
            } else if !elsewhere && !engine.isSwitchingSpace && !allAside {
                let since = invisibleSince[id] ?? CACurrentMediaTime()
                invisibleSince[id] = since
                if CACurrentMediaTime() - since >= invisibleGrace {
                    reason = "not visible"
                } else {
                    // Look again once the grace period is over.
                    DispatchQueue.main.asyncAfter(deadline: .now() + invisibleGrace) { [weak self] in
                        MainActor.assumeIsolated { self?.reconcile() }
                    }
                    reason = nil
                }
            } else {
                reason = nil
            }
            if let reason {
                invisibleSince[id] = nil
                log("\(reason): \(window.title.isEmpty ? "\(id)" : window.title)")
                engine.remove(id)
            }
        }

        for id in foundIDs { invisibleSince[id] = nil }

        let fresh = found.filter { engine.windows[$0.windowID] == nil }
        for window in fresh {
            log("opened: \(window.title.isEmpty ? "\(window.windowID)" : window.title)")
        }
        if fresh.count > 1 || engine.isSwitchingSpace {
            // Several unknown windows at once (a desktop seen for the first
            // time): keep the order they already have on screen.
            engine.adopt(fresh)
        } else if let window = fresh.first {
            // One newly opened window: it splits the tile under the mouse.
            engine.add(window, at: CGEvent(source: nil)?.location)
        }
        watchNewWindows()
    }
}

private let watcherCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon else { return }
    let watcher = Unmanaged<WindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated { watcher.handle(name) }
}
