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

    public func reconcile() {
        let found = WindowDiscovery.tileableWindows(in: engine.screenArea)
        let foundIDs = Set(found.map(\.windowID))

        // Windows the user moved to another desktop follow there.
        for id in engine.windows.keys where id != engine.dragging {
            if let space = Spaces.of(id), space != engine.layouts.space(of: id) {
                engine.move(id, to: space)
            }
        }

        // Everything on this desktop gone at once means Show Desktop or
        // Mission Control pushed the windows aside; they come back, so they
        // keep their tiles.
        let shown = engine.tree.ids
        let allAside = !shown.isEmpty && shown.allSatisfy { !foundIDs.contains($0) }

        for (id, window) in engine.windows where !foundIDs.contains(id) && id != engine.dragging {
            // Not on screen. It keeps its tile only while it lives on another
            // desktop. Apps like WhatsApp or System Settings keep closed
            // windows alive but invisible; those must not hold a tile.
            let space = Spaces.of(id)
            let elsewhere = space != nil && space != engine.space
            let element = window.element
            let reason: String?
            if window.position == nil {
                reason = "closed"
            } else if element.bool(kAXMinimizedAttribute) == true {
                reason = "minimized"
            } else if AXUIElementCreateApplication(window.pid).bool(kAXHiddenAttribute) == true {
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

        let mouse = CGEvent(source: nil)?.location
        for window in found where engine.windows[window.windowID] == nil {
            log("opened: \(window.title.isEmpty ? "\(window.windowID)" : window.title)")
            engine.add(window, at: mouse)
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
