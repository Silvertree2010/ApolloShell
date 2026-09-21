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
    private var pending: DispatchWorkItem?

    public var log: (String) -> Void = { print($0) }

    public init(engine: TilingEngine) {
        self.engine = engine
    }

    public func start() {
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
        for delay in [0.05, 0.25, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.reconcile() }
            }
        }
    }

    // MARK: Reconcile

    public func reconcile() {
        let found = WindowDiscovery.tileableWindows(in: engine.screenArea)
        let foundIDs = Set(found.map(\.windowID))

        for (id, window) in engine.windows where !foundIDs.contains(id) {
            // Not on screen right now. Only drop it when it is really gone;
            // a window on another Space stays valid and stays tiled.
            let element = window.element
            let gone = window.position == nil
                || element.bool(kAXMinimizedAttribute) == true
                || AXUIElementCreateApplication(window.pid).bool(kAXHiddenAttribute) == true
            if gone {
                log("closed: \(window.title.isEmpty ? "\(id)" : window.title)")
                engine.remove(id)
            }
        }

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
