import AppKit
import ApplicationServices

@MainActor
public final class WindowWatcher {
    private let engine: TilingEngine
    private var observers: [pid_t: AXObserver] = [:]
    private var watchedWindows: Set<CGWindowID> = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var safetyTimer: Timer?
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
                    self.engine.updateDisplays()
                    self.engine.switchSpace(to: space)
                    self.engine.relayout()
                    self.reconcileSoon()
                }
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.engine.focusChanged() }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    guard let self, let pid else { return }
                    if let observer = self.observers.removeValue(forKey: pid) {
                        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                    }
                    self.engine.forgetApp(pid)
                    self.reconcile()
                }
            },
        ]
        workspaceTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.log("displays changed")
                self.engine.updateDisplays()
                self.engine.relayout()
                self.reconcileSoon()
            }
        })
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.engine.isAnimating, self.engine.dragging == nil else { return }
                self.reconcile()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
        watchNewWindows()
        reconcile()
    }

    public func stop() {
        safetyTimer?.invalidate()
        safetyTimer = nil
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        workspaceTokens = []
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers = [:]
        watchedWindows = []
    }

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil, pid != getpid() else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, watcherCallback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXWindowMiniaturizedNotification,
                     kAXWindowDeminiaturizedNotification, kAXApplicationHiddenNotification,
                     kAXApplicationShownNotification, kAXUIElementDestroyedNotification,
                     kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(observer, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
    }

    private func watchNewWindows() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for (id, window) in engine.windows where !watchedWindows.contains(id) {
            guard let observer = observers[window.pid] else { continue }
            AXObserverAddNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString, refcon)
            AXObserverAddNotification(observer, window.element, kAXTitleChangedNotification as CFString, refcon)
            watchedWindows.insert(id)
        }
        watchedWindows.formIntersection(engine.windows.keys)
    }

    fileprivate func handle(_ notification: String, windowID: CGWindowID?) {
        if notification == kAXTitleChangedNotification {
            if let id = windowID { engine.refreshTitle(of: id) }
            return
        }
        if notification == kAXFocusedWindowChangedNotification {
            engine.focusChanged()
            return
        }
        if notification == kAXWindowCreatedNotification || notification == kAXWindowDeminiaturizedNotification
            || notification == kAXApplicationShownNotification {
            reconcileSoon()
        } else {
            reconcile()
        }
    }

    private func reconcileSoon() {
        for work in pendingLooks { work.cancel() }
        pendingLooks = [0.05, 0.25, 0.8, 1.2].map { delay in
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.reconcile() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }
    private var pendingLooks: [DispatchWorkItem] = []

    private struct Missing: Sendable {
        var closed = false
        var minimized = false
        var appHidden = false
    }

    private var scanning = false
    private var rescan = false

    public func reconcile() {
        if scanning {
            rescan = true
            return
        }
        scanning = true
        let screens = engine.displaysShareSpaces
            ? [engine.screens.first?.bounds ?? engine.screenArea]
            : (engine.screens.isEmpty ? [engine.screenArea] : engine.screens.map(\.bounds))
        let tracked = engine.windows
        Task.detached(priority: .userInitiated) { [weak self] in
            let order = Spaces.ordered()
            let found = WindowDiscovery.allDesktopWindows(on: screens)
            let foundIDs = Set(found.map(\.window.windowID))
            var spaces: [CGWindowID: SpaceID] = [:]
            for item in found { spaces[item.window.windowID] = item.space }
            var missing: [CGWindowID: Missing] = [:]
            for (id, window) in tracked {
                guard !foundIDs.contains(id) else { continue }
                spaces[id] = Spaces.of(id)
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
            await MainActor.run { [found, spaces, missing, order] in
                guard let self else { return }
                self.apply(found: found, spaces: spaces, missing: missing, order: order)
                self.scanning = false
                if self.rescan {
                    self.rescan = false
                    self.reconcile()
                }
            }
        }
    }

    private func apply(found: [WindowDiscovery.Found], spaces: [CGWindowID: SpaceID],
                       missing: [CGWindowID: Missing], order: [SpaceID]) {
        let foundIDs = Set(found.map(\.window.windowID))

        if !order.isEmpty {
            let vanished = Set(engine.knownSpaceOrder).subtracting(order)
            for old in vanished {
                let movedHere = engine.windows.keys.filter { engine.desk(of: $0)?.space == old }
                if let into = movedHere.lazy.compactMap({ spaces[$0] }).first {
                    engine.absorbVanishedSpace(old, into: into)
                }
            }
            engine.noteSpaceOrder(order)
        }

        for id in engine.windows.keys where id != engine.dragging {
            if let space = spaces[id], space != engine.desk(of: id)?.space {
                engine.move(id, to: space)
            }
        }

        let shown = engine.shownDesks.flatMap { engine.layouts[$0].ids }
        let allAside = !shown.isEmpty && shown.allSatisfy { !foundIDs.contains($0) }

        for (id, state) in missing where engine.windows[id] != nil && id != engine.dragging {
            if id == engine.scratchpad, !state.closed, state.minimized || engine.scratchpadHidden { continue }
            guard let window = engine.windows[id] else { continue }
            let reason: String?
            if state.closed {
                reason = "closed"
            } else if state.minimized {
                reason = "minimized"
            } else if state.appHidden {
                reason = "app hidden"
            } else if !engine.isSwitchingSpace && !allAside {
                let since = invisibleSince[id] ?? CACurrentMediaTime()
                invisibleSince[id] = since
                if CACurrentMediaTime() - since >= invisibleGrace {
                    reason = "not visible"
                } else {
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

        engine.pruneIgnored(keeping: foundIDs)
        let fresh = found.filter { engine.windows[$0.window.windowID] == nil && !engine.ignored.contains($0.window.windowID) }
        for item in fresh {
            log("opened: \(item.window.title.isEmpty ? "\(item.window.windowID)" : item.window.title) (desktop \(item.space))")
        }
        let shownSpaces = Set(engine.shownDesks.map(\.space))
        let onShown = fresh.filter { shownSpaces.contains($0.space) }
        if onShown.count == 1, fresh.count == 1, !engine.isSwitchingSpace {
            engine.add(onShown[0].window, at: CGEvent(source: nil)?.location, on: onShown[0].space)
        } else {
            for space in Set(fresh.map(\.space)) {
                engine.adopt(fresh.filter { $0.space == space }.map(\.window), on: space)
            }
        }
        watchNewWindows()
    }
}

private let watcherCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let watcher = Unmanaged<WindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    let id = name == kAXTitleChangedNotification ? element.windowID : nil
    MainActor.assumeIsolated { watcher.handle(name, windowID: id) }
}
