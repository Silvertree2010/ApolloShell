import AppKit
import ApplicationServices
import ApolloShellCore
import os

@MainActor
final class WindowGuard {
    private static let trustPollInterval: TimeInterval = 2

    private let worker: WindowGuardWorker
    private let log = Logger(category: "windowguard")
    private var trusted = false
    private var barScreenKeys: Set<String> = []
    private var barWidth: CGFloat = 0

    init(askForAccess: Bool = true) {
        worker = WindowGuardWorker()

        let options = ["AXTrustedCheckOptionPrompt": askForAccess] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        log.notice("Bedienungshilfen \(self.trusted ? "freigegeben" : "nicht freigegeben", privacy: .public)")
        if trusted { startWorker() }

        observeSystem()
        startTrustPolling()
    }

    private func startTrustPolling() {
        Timer.repeating(every: Self.trustPollInterval, tolerance: 0.5, owner: self) { $0.pollTrust() }
    }

    private func pollTrust() {
        let now = AXIsProcessTrusted()
        guard now != trusted else { return }
        trusted = now
        if now {
            log.notice("Bedienungshilfen freigegeben, Fensterwache startet")
            startWorker()
        } else {
            log.notice("Bedienungshilfen entzogen, Fensterwache haelt an")
            worker.stop()
        }
    }

    private func startWorker() {
        worker.start(
            screens: screensForWorker() ?? [],
            apps: NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map(\.processIdentifier)
        )
    }

    func setBarScreens(_ keys: Set<String>, barWidth: CGFloat) {
        guard keys != barScreenKeys || barWidth != self.barWidth else { return }
        barScreenKeys = keys
        self.barWidth = barWidth
        log.notice("Streifen (\(Int(barWidth), privacy: .public) pt) freihalten auf \(keys.count, privacy: .public) Bildschirm(en)")
        guard let screens = screensForWorker() else { return }
        worker.screensChanged(screens)
    }

    private func screensForWorker() -> [GuardScreen]? {
        let screens = ShellScreens.current()
        guard let primary = screens.first else { return nil }
        let primaryHeight = primary.frame.maxY
        return screens.map { screen in
            GuardScreen(
                key: screen.info.key,
                frame: WindowClamp.flipped(screen.frame, primaryHeight: primaryHeight),
                reservedWidth: barScreenKeys.contains(screen.info.key) ? barWidth : 0
            )
        }
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let worker = worker

        workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular
            else { return }
            worker.appLaunched(app.processIdentifier)
        }
        workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            worker.appTerminated(app.processIdentifier)
        }
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            worker.appActivated(app.processIdentifier, isRegular: app.activationPolicy == .regular)
        }
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                worker.spaceChanged()
            }
        }

        ShellScreens.onChange { [weak self] in
            guard let self, let screens = self.screensForWorker() else { return }
            worker.screensChanged(screens)
        }
    }
}

struct GuardScreen: Sendable, Equatable {
    let key: String
    let frame: CGRect
    let reservedWidth: CGFloat
}

final class WindowGuardWorker: @unchecked Sendable {
    static let settleDelay: TimeInterval = 0.2
    static let registerRetries = 10
    static let registerRetryDelay: TimeInterval = 0.5
    static let messagingTimeout: Float = 1

    private let queue = DispatchQueue(label: AppIdentity.scoped("windowguard"))
    private let log = Logger(category: "windowguard")
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private var running = false
    private var screens: [GuardScreen] = []
    private var apps: [pid_t: ObservedApp] = [:]
    private var pending: [AXUIElement: DispatchWorkItem] = [:]
    private var ledger = ClampLedger<AXUIElement>(maxAttempts: 3, period: 30)
    private var minWidths: [AXUIElement: CGFloat] = [:]

    func start(screens: [GuardScreen], apps pids: [pid_t]) {
        queue.async { [self] in
            guard !running else { return }
            running = true
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)
            self.screens = screens
            for pid in pids { watchApp(pid, attempt: 0) }
            log.notice("Fensterwache laeuft, \(self.apps.count, privacy: .public) Apps beobachtet")
        }
    }

    func stop() {
        queue.async { [self] in
            guard running else { return }
            running = false
            for pid in Array(apps.keys) { unwatchApp(pid) }
            for work in pending.values { work.cancel() }
            pending = [:]
            ledger = ClampLedger(maxAttempts: ledger.maxAttempts, period: ledger.period)
            minWidths = [:]
        }
    }

    func appLaunched(_ pid: pid_t) {
        queue.async { [self] in
            guard running else { return }
            watchApp(pid, attempt: 0)
        }
    }

    func appTerminated(_ pid: pid_t) {
        queue.async { [self] in
            unwatchApp(pid)
        }
    }

    func appActivated(_ pid: pid_t, isRegular: Bool) {
        queue.async { [self] in
            guard isRegular, pid != ownPID, running else { return }
            if apps[pid] == nil {
                watchApp(pid, attempt: 0)
            } else if let window = AX.element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) {
                watchWindow(window, pid: pid)
                scheduleClamp(window)
            }
        }
    }

    func spaceChanged() {
        queue.async { [self] in
            guard running else { return }
            sweepWindows(onlyNew: true)
        }
    }

    func screensChanged(_ screens: [GuardScreen]) {
        queue.async { [self] in
            self.screens = screens
            guard running else { return }
            sweepWindows(onlyNew: false)
        }
    }

    fileprivate func receive(_ element: AXElementRef, _ notification: String) {
        queue.async { [self] in handle(element.element, notification) }
    }

    private func watchApp(_ pid: pid_t, attempt: Int) {
        guard running, pid > 0, pid != ownPID, apps[pid] == nil else { return }

        var created: AXObserver?
        let status = AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let worker = Unmanaged<WindowGuardWorker>.fromOpaque(refcon).takeUnretainedValue()
            worker.receive(AXElementRef(element: element), notification as String)
        }, &created)
        guard status == .success, let observer = created else {
            log.error("AXObserver fuer pid \(pid, privacy: .public) nicht angelegt: \(status.rawValue, privacy: .public)")
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let app = AXUIElementCreateApplication(pid)
        let results = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification].map {
            AXObserverAddNotification(observer, app, $0 as CFString, refcon)
        }
        guard results.contains(where: { $0 == .success || $0 == .notificationAlreadyRegistered }) else {
            if results.contains(.cannotComplete), attempt < Self.registerRetries {
                queue.asyncAfter(deadline: .now() + Self.registerRetryDelay) { [self] in
                    watchApp(pid, attempt: attempt + 1)
                }
            } else {
                log.info("pid \(pid, privacy: .public) nicht beobachtbar: \(results.map(\.rawValue), privacy: .public)")
            }
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        apps[pid] = ObservedApp(element: app, observer: observer)

        for window in AX.elements(app, kAXWindowsAttribute) {
            watchWindow(window, pid: pid)
            scheduleClamp(window)
        }
    }

    private func unwatchApp(_ pid: pid_t) {
        guard let app = apps.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(app.observer), .commonModes)
        let belongs: (AXUIElement) -> Bool = { AX.pid(of: $0) == pid }
        for (window, work) in pending where belongs(window) {
            work.cancel()
            pending[window] = nil
        }
        ledger.forget(where: belongs)
        minWidths = minWidths.filter { !belongs($0.key) }
    }

    private func watchWindow(_ window: AXUIElement, pid: pid_t) {
        guard let app = apps[pid], !app.windows.contains(window),
              AX.string(window, kAXRoleAttribute) == kAXWindowRole
        else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [
            kAXWindowMovedNotification,
            kAXWindowResizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXUIElementDestroyedNotification,
        ] {
            AXObserverAddNotification(app.observer, window, name as CFString, refcon)
        }
        app.windows.insert(window)
    }

    private func sweepWindows(onlyNew: Bool) {
        for (pid, app) in apps {
            for window in AX.elements(app.element, kAXWindowsAttribute) {
                if onlyNew, app.windows.contains(window) { continue }
                watchWindow(window, pid: pid)
                scheduleClamp(window)
            }
        }
    }

    private func forget(_ window: AXUIElement, pid: pid_t) {
        pending.removeValue(forKey: window)?.cancel()
        ledger.forget(window)
        minWidths[window] = nil
        apps[pid]?.windows.remove(window)
    }

    private func handle(_ element: AXUIElement, _ notification: String) {
        guard running else { return }
        let pid = AX.pid(of: element)
        switch notification {
        case kAXWindowCreatedNotification:
            watchWindow(element, pid: pid)
            scheduleClamp(element)
        case kAXFocusedWindowChangedNotification:
            let window = AX.string(element, kAXRoleAttribute) == kAXApplicationRole
                ? AX.element(element, kAXFocusedWindowAttribute) : element
            if let window {
                watchWindow(window, pid: pid)
                scheduleClamp(window)
            }
        case kAXWindowResizedNotification:
            scheduleClamp(element)
        case kAXWindowMovedNotification, kAXWindowDeminiaturizedNotification:
            scheduleClamp(element)
        case kAXUIElementDestroyedNotification:
            forget(element, pid: pid)
        default:
            break
        }
    }

    private func scheduleClamp(_ window: AXUIElement) {
        pending[window]?.cancel()
        let ref = AXElementRef(element: window)
        let work = DispatchWorkItem { [self] in
            pending[ref.element] = nil
            clampIfNeeded(ref.element)
        }
        pending[window] = work
        queue.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func clampIfNeeded(_ window: AXUIElement) {
        guard running, !screens.isEmpty else { return }

        if CGEventSource.buttonState(.combinedSessionState, button: .left) {
            scheduleClamp(window)
            return
        }

        let pid = AX.pid(of: window)
        guard pid != ownPID, apps[pid] != nil,
              AX.string(window, kAXRoleAttribute) == kAXWindowRole,
              AX.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
              AX.bool(window, kAXMinimizedAttribute) != true,
              AX.bool(window, AX.fullScreenAttribute) != true,
              let frame = AX.frame(of: window),
              let index = WindowClamp.dominantScreen(for: frame, among: screens.map(\.frame)),
              screens[index].reservedWidth > 0,
              let target = WindowClamp.clampedFrame(
                  window: frame, screen: screens[index].frame,
                  reservedWidth: screens[index].reservedWidth, minWidth: minWidths[window] ?? 0
              )
        else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard ledger.shouldClamp(window, current: frame, now: now) else {
            log.debug("pid \(pid, privacy: .public): Fenster eben erst angefasst oder wehrt sich, lasse es")
            return
        }
        guard AX.isSettable(window, kAXPositionAttribute) else { return }

        apply(target, to: window, current: frame, pid: pid)

        let result = AX.frame(of: window) ?? target
        if target.width < frame.width - WindowClamp.tolerance,
           result.width > target.width + WindowClamp.tolerance {
            minWidths[window] = result.width
        }
        ledger.record(window, result: result, now: now)
        log.debug("pid \(pid, privacy: .public): \(String(describing: frame), privacy: .public) -> \(String(describing: result), privacy: .public)")
    }

    private func apply(_ target: CGRect, to window: AXUIElement, current: CGRect, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        let enhanced = AX.bool(app, AX.enhancedUserInterfaceAttribute) == true
        if enhanced { AX.setBool(app, AX.enhancedUserInterfaceAttribute, false) }
        defer { if enhanced { AX.setBool(app, AX.enhancedUserInterfaceAttribute, true) } }

        if abs(target.width - current.width) > WindowClamp.tolerance {
            AX.setSize(window, target.size)
        }
        AX.setPosition(window, target.origin)
    }
}

private final class ObservedApp {
    let element: AXUIElement
    let observer: AXObserver
    var windows: Set<AXUIElement> = []

    init(element: AXUIElement, observer: AXObserver) {
        self.element = element
        self.observer = observer
    }
}

private struct AXElementRef: @unchecked Sendable {
    let element: AXUIElement
}
