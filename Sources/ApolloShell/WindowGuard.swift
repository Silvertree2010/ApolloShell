import AppKit
import ApplicationServices
import ApolloShellCore
import os

/// Window guard: keeps foreign windows out of the left bar's strip.
///
/// macOS has no interface to reserve screen space; `visibleFrame` belongs
/// solely to the Dock and menu bar. So, like the app "Sidebar": listen to
/// window events from all apps via accessibility (AXUIElement/AXObserver)
/// and reposition windows afterward that reach under the bar. The math for
/// that lives in ApolloShellCore/WindowClamp.swift and is tested there.
///
/// When the bar steps aside in fullscreen is decided by `FullscreenMonitor`.
///
/// Needs the "Accessibility" permission. It is requested once per launch;
/// without the permission everything stays as before (bar always visible,
/// windows run underneath it). Every 2 s it checks whether it has been
/// granted or revoked in the meantime - a restart isn't necessary.
///
/// This part lives on the main thread and only forwards; the actual work is
/// done by `WindowGuardWorker` on its own queue.
@MainActor
final class WindowGuard {
    /// AXIsProcessTrusted is cheap; 2 s is fast enough that the guard
    /// starts working shortly after ticking the checkbox in System
    /// Settings.
    private static let trustPollInterval: TimeInterval = 2

    private let worker: WindowGuardWorker
    private let log = Logger(category: "windowguard")
    private var trusted = false
    /// Keys of the screens that have a bar - the strip is only kept clear
    /// there. Reported by the bar manager.
    private var barScreenKeys: Set<String> = []
    /// How wide the strip is. The theme can make the bar wider or narrower
    /// at runtime; the manager reports that too.
    private var barWidth: CGFloat = 0

    /// `askForAccess`: show the system prompt at launch if the permission
    /// is missing. Off while the intro is running - that explains what it's
    /// for first, and asks itself afterward.
    init(askForAccess: Bool = true) {
        worker = WindowGuardWorker()

        // Ask once per launch (only shows the system dialog while the
        // permission is missing). The key is the value of
        // kAXTrustedCheckOptionPrompt; the constant itself is a global
        // `var` and would give a concurrency warning under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": askForAccess] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        log.notice("Accessibility \(self.trusted ? "granted" : "not granted", privacy: .public)")
        if trusted { startWorker() }

        observeSystem()
        startTrustPolling()
    }

    // MARK: - Permission

    /// The permission is granted (or revoked) at runtime via System
    /// Settings; there is no notification for that. The timer runs as long
    /// as the window guard does, so nothing needs to hold onto it.
    private func startTrustPolling() {
        Timer.repeating(every: Self.trustPollInterval, tolerance: 0.5, owner: self) { $0.pollTrust() }
    }

    private func pollTrust() {
        let now = AXIsProcessTrusted()
        guard now != trusted else { return }
        trusted = now
        if now {
            log.notice("Accessibility granted, window guard starting")
            startWorker()
        } else {
            // Revoked: stop, don't touch any more windows.
            log.notice("Accessibility revoked, window guard stopping")
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

    /// Which screens have a bar and how wide it is. This determines where
    /// and how wide the strip is kept clear; the bar manager reports every
    /// change.
    func setBarScreens(_ keys: Set<String>, barWidth: CGFloat) {
        guard keys != barScreenKeys || barWidth != self.barWidth else { return }
        barScreenKeys = keys
        self.barWidth = barWidth
        log.notice("Keeping strip (\(Int(barWidth), privacy: .public) pt) clear on \(keys.count, privacy: .public) screen(s)")
        guard let screens = screensForWorker() else { return }
        worker.screensChanged(screens)
    }

    /// Screens in accessibility coordinates, the one with the menu bar
    /// first, each with its key and whether a bar sits on it. `nil` if
    /// there currently is none (screen mid-reconfiguration): then keep
    /// the old ones.
    private func screensForWorker() -> [GuardScreen]? {
        let screens = ShellScreens.current()
        guard let primary = screens.first else { return nil }
        // The origin of accessibility coordinates is the top-left corner
        // of the main screen, its maxY in AppKit.
        let primaryHeight = primary.frame.maxY
        return screens.map { screen in
            GuardScreen(
                key: screen.info.key,
                frame: WindowClamp.flipped(screen.frame, primaryHeight: primaryHeight),
                reservedWidth: barScreenKeys.contains(screen.info.key) ? barWidth : 0
            )
        }
    }

    // MARK: - Forwarding system events

    /// The guard lives as long as the process (AppDelegate holds it), so
    /// the observers never need to be removed. As long as the permission is
    /// missing, the reports to the worker go nowhere.
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
        // Space switch and wake: pick up newly visible windows.
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

/// A screen, as the window guard needs it.
struct GuardScreen: Sendable, Equatable {
    /// Stable key (name plus resolution), as reported by the bar manager.
    let key: String
    /// Frame in accessibility coordinates (origin top left on the main
    /// screen, y downward).
    let frame: CGRect
    /// How wide the strip to keep clear is on the left edge. 0: no bar
    /// there, windows are left alone.
    let reservedWidth: CGFloat
}

/// The actual window guard.
///
/// Everything runs on a serial queue: accessibility calls are synchronous
/// requests to the other app and wait until it responds - for a hung app,
/// until the timeout. On the main thread that would slow down the launcher
/// hotkey (milliseconds matter there).
///
/// The AXObserver run loop sources still hang off the main run loop (a
/// dispatch queue has none of its own); their callback just forwards the
/// notification to the queue and costs practically nothing there.
///
/// `@unchecked Sendable`: state is touched exclusively on `queue`, all
/// public methods hop there first.
final class WindowGuardWorker: @unchecked Sendable {
    /// A window must be still for this long before it's touched. While
    /// dragging, resizing, or during zoom/tile animations, the "moved"
    /// notifications arrive milliseconds apart and push the deadline back
    /// each time; the guard only steps in once the window is at rest.
    /// Shorter looks like a jolt mid-animation, longer means the window is
    /// visibly seen sitting under the bar.
    static let settleDelay: TimeInterval = 0.2
    /// Freshly launched apps often don't respond yet
    /// (kAXErrorCannotComplete). Retry this often and at this interval.
    static let registerRetries = 10
    static let registerRetryDelay: TimeInterval = 0.5
    /// Wait for an app at most this long. macOS's default is 6 s, which
    /// would stall the whole guard because of one hung app.
    static let messagingTimeout: Float = 1

    private let queue = DispatchQueue(label: AppIdentity.scoped("windowguard"))
    private let log = Logger(category: "windowguard")
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    // Only touch on `queue`.
    private var running = false
    /// Screens in accessibility coordinates, main screen first.
    private var screens: [GuardScreen] = []
    private var apps: [pid_t: ObservedApp] = [:]
    /// The next scheduled look at each window (debouncing).
    private var pending: [AXUIElement: DispatchWorkItem] = [:]
    /// 3 interventions in 30 s: enough for "dragged back under twice in a
    /// row", but an app that puts its window back every time only twitches
    /// briefly at most every 30 s instead of constantly.
    private var ledger = ClampLedger<AXUIElement>(maxAttempts: 3, period: 30)
    /// Minimum widths learned from rejected shrink attempts.
    private var minWidths: [AXUIElement: CGFloat] = [:]

    // MARK: - From outside (any thread)

    func start(screens: [GuardScreen], apps pids: [pid_t]) {
        queue.async { [self] in
            guard !running else { return }
            running = true
            // Applies to all accessibility requests from this process.
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)
            self.screens = screens
            for pid in pids { watchApp(pid, attempt: 0) }
            log.notice("Window guard running, \(self.apps.count, privacy: .public) apps observed")
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
                // Apps that only became regular later.
                watchApp(pid, attempt: 0)
            } else if let window = AX.element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) {
                // kAXWindowsAttribute doesn't return windows on other
                // spaces; at the latest when they come to the front, it's
                // their turn.
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
            // Different resolution or arrangement: every window can now
            // sit differently relative to the bar.
            sweepWindows(onlyNew: false)
        }
    }

    /// From the AXObserver callback on the main thread.
    fileprivate func receive(_ element: AXElementRef, _ notification: String) {
        queue.async { [self] in handle(element.element, notification) }
    }

    // MARK: - Observing

    private func watchApp(_ pid: pid_t, attempt: Int) {
        guard running, pid > 0, pid != ownPID, apps[pid] == nil else { return }

        var created: AXObserver?
        let status = AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let worker = Unmanaged<WindowGuardWorker>.fromOpaque(refcon).takeUnretainedValue()
            worker.receive(AXElementRef(element: element), notification as String)
        }, &created)
        guard status == .success, let observer = created else {
            log.error("AXObserver for pid \(pid, privacy: .public) not created: \(status.rawValue, privacy: .public)")
            return
        }

        // The worker lives as long as the process, unretained is enough.
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
                log.info("pid \(pid, privacy: .public) not observable: \(results.map(\.rawValue), privacy: .public)")
            }
            return
        }

        // .commonModes: also while a menu or a drag is running on the main
        // thread (eventTracking), otherwise notifications pile up.
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

    /// "Moved" and "resized" arrive per window, so every new window is
    /// registered individually. The app's observer object deregisters
    /// them once it is released.
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

    /// Re-read the window list. `onlyNew`: only windows not yet registered
    /// (the ones newly visible after a space switch); the known ones
    /// report in themselves when moved.
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
            // Usually the element is the new window; some apps report the app instead.
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

    // MARK: - Repositioning

    /// Debounced: every notification pushes the look at the window back by
    /// `settleDelay`; it only steps in once the window is at rest.
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

        // Left mouse button still down: someone is dragging the window
        // right now (or just holding it still). Don't rip it out of their
        // hand, check again later - like the Dock only reacting after
        // release.
        if CGEventSource.buttonState(.combinedSessionState, button: .left) {
            scheduleClamp(window)
            return
        }

        let pid = AX.pid(of: window)
        // Standard windows only: sheets, dialogs, floating palettes and
        // popovers have a different role or subrole and hang off their
        // parent window, or belong deliberately wherever they are.
        // Minimized and fullscreen windows are none of the bar's concern,
        // nor are windows on a screen without a bar.
        guard pid != ownPID, apps[pid] != nil,
              AX.string(window, kAXRoleAttribute) == kAXWindowRole,
              AX.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
              AX.bool(window, kAXMinimizedAttribute) != true,
              AX.bool(window, AX.fullScreenAttribute) != true,
              let frame = AX.frame(of: window),
              // The window belongs to the screen where the largest part
              // of it lies - and it's only repositioned where a bar sits.
              let index = WindowClamp.dominantScreen(for: frame, among: screens.map(\.frame)),
              screens[index].reservedWidth > 0,
              let target = WindowClamp.clampedFrame(
                  window: frame, screen: screens[index].frame,
                  reservedWidth: screens[index].reservedWidth, minWidth: minWidths[window] ?? 0
              )
        else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard ledger.shouldClamp(window, current: frame, now: now) else {
            log.debug("pid \(pid, privacy: .public): window just touched or pushing back, leaving it")
            return
        }
        guard AX.isSettable(window, kAXPositionAttribute) else { return }

        apply(target, to: window, current: frame, pid: pid)

        // Read back: whatever the app made of it is the new state. If it
        // rejected the shrink, that's its minimum width - then don't try
        // to make it narrower next time, only move it.
        let result = AX.frame(of: window) ?? target
        if target.width < frame.width - WindowClamp.tolerance,
           result.width > target.width + WindowClamp.tolerance {
            minWidths[window] = result.width
        }
        ledger.record(window, result: result, now: now)
        log.debug("pid \(pid, privacy: .public): \(String(describing: frame), privacy: .public) -> \(String(describing: result), privacy: .public)")
    }

    private func apply(_ target: CGRect, to window: AXUIElement, current: CGRect, pid: pid_t) {
        // Chromium, Firefox & co. turn on "AXEnhancedUserInterface" as soon
        // as accessibility software is running; then they animate every
        // change and only partially adopt position and size. Turn it off
        // for the intervention, then back on afterward (this is how
        // Rectangle does it).
        let app = AXUIElementCreateApplication(pid)
        let enhanced = AX.bool(app, AX.enhancedUserInterfaceAttribute) == true
        if enhanced { AX.setBool(app, AX.enhancedUserInterfaceAttribute, false) }
        defer { if enhanced { AX.setBool(app, AX.enhancedUserInterfaceAttribute, true) } }

        // Narrow first, then move: this way the window never sticks out
        // past the right edge in between. If the app rejects the size, it
        // is still moved.
        if abs(target.width - current.width) > WindowClamp.tolerance {
            AX.setSize(window, target.size)
        }
        AX.setPosition(window, target.origin)
    }
}

/// An observed app. Lives only on the worker's queue.
private final class ObservedApp {
    let element: AXUIElement
    let observer: AXObserver
    /// Windows for which "moved"/"resized" are already registered.
    var windows: Set<AXUIElement> = []

    init(element: AXUIElement, observer: AXObserver) {
        self.element = element
        self.observer = observer
    }
}

/// Carrier to pass an AXUIElement from the callback to the queue.
/// Harmless: an AXUIElement is an immutable reference (process plus
/// element ID), and the AX functions may be called from any thread. Swift
/// just doesn't know `Sendable` for it.
private struct AXElementRef: @unchecked Sendable {
    let element: AXUIElement
}
