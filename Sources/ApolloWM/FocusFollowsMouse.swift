import AppKit

/// Focus follows the mouse: when the mouse rests over a window for `delay`,
/// that window is focused and raised. Modeled on AutoRaise (which borrows
/// yabai's focusing), reimplemented:
///
/// - The window under the mouse is what the system reports at that point
///   (any app's window, not just tiles); menus and Dock items are skipped.
/// - It is compared with the window that really has focus now, not with the
///   last one we focused, so after cmd+Tab or a click elsewhere, going back
///   over a window focuses it again.
/// - Focusing goes straight to the window server (WindowFocus), since the
///   official activation is sometimes refused on macOS 14 and later.
/// - Apps that push themselves back in front are raised up to three times.
/// - Nothing happens while a button is held, a window is dragged or
///   resized, a desktop switch runs, Mission Control or the app switcher is
///   showing, right after an app was activated by other means (until the
///   mouse moves again), or when the focused window lies inside the one
///   under the mouse and belongs to the same app (a dialog over its parent).
/// - The point looked at is 3 pt ahead in the direction of movement, so
///   crossing a border does not focus the window being left.
@MainActor
public final class FocusFollowsMouse {
    private let engine: TilingEngine
    private var tap: CFMachPort?
    private var pending: DispatchWorkItem?
    private var lastPoint: CGPoint?
    private var lookahead = CGVector.zero
    private var checking = false
    /// Set when some app came to the front without us (cmd+Tab, Dock
    /// click); cleared by the next mouse movement.
    private var suppressedUntilMove = false
    private var ourActivation: pid_t?
    private var activationObserver: NSObjectProtocol?

    public var isEnabled = true
    /// How long the mouse must rest over a window (AutoRaise used 50 ms;
    /// the user settled on 25 ms).
    public var delay: TimeInterval = 0.025
    /// Holding these suspends focus following. None by default: the user
    /// did not want control to switch it off (AutoRaise's habit).
    public var disableFlags: CGEventFlags = []

    public var log: (String) -> Void = { print($0) }

    public init(engine: TilingEngine) {
        self.engine = engine
    }

    /// Returns false when the event tap cannot be created (missing permission).
    public func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .tailAppendEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: mask,
                                          callback: focusTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.appActivated(pid) }
        }
        return true
    }

    private func appActivated(_ pid: pid_t?) {
        if let pid, pid == ourActivation {
            ourActivation = nil
        } else {
            // Someone else chose this app: do not fight it with the window
            // that happens to be under the resting mouse.
            suppressedUntilMove = true
        }
    }

    fileprivate func mouseMoved(to point: CGPoint, flags: CGEventFlags) {
        pending?.cancel()
        suppressedUntilMove = false
        if let lastPoint {
            let dx = point.x - lastPoint.x, dy = point.y - lastPoint.y
            lookahead = CGVector(dx: dx > 0 ? 3 : dx < 0 ? -3 : 0, dy: dy > 0 ? 3 : dy < 0 ? -3 : 0)
        }
        lastPoint = point
        guard isEnabled, flags.intersection(disableFlags).isEmpty else { return }
        let target = CGPoint(x: point.x + lookahead.dx, y: point.y + lookahead.dy)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.check(target) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func check(_ point: CGPoint) {
        guard !checking, !suppressedUntilMove, NSEvent.pressedMouseButtons == 0,
              !engine.isSwitchingSpace, engine.dragging == nil, engine.resizing == nil else { return }
        checking = true
        let own = getpid()
        let trace = ProcessInfo.processInfo.environment["APOLLOWM_TRACE"] == "1"
        let done: @MainActor @Sendable () -> Void = { [weak self] in self?.checking = false }
        let markOurs: @MainActor @Sendable (pid_t) -> Void = { [weak self] pid in self?.ourActivation = pid }
        // Everything below asks other apps or the window server: off the main thread.
        Task.detached(priority: .userInitiated) {
            defer { Task { @MainActor in done() } }
            guard !WindowFocus.dockIsBusy(),
                  let window = WindowFocus.window(at: point), window.pid != own,
                  [kAXStandardWindowSubrole, kAXDialogSubrole].contains(window.subrole) else { return }
            let focused = WindowFocus.focusedWindowID()
            guard focused != window.windowID else { return }
            // A dialog of the same app over its window keeps focus; another
            // app's floating window does not block the window around it.
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if let focused, frontmost == window.pid, let inner = FocusFollowsMouse.frame(of: focused),
               let outer = window.serverFrame, outer.contains(inner) {
                return
            }
            await markOurs(window.pid)
            if trace { FileHandle.standardError.write(Data("focus: \(window.title)\n".utf8)) }
            WindowFocus.focus(window)
            // Some apps push their own window back in front: up to twice more.
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(50))
                if WindowFocus.focusedWindowID() == window.windowID { break }
                WindowFocus.focus(window)
            }
        }
    }

    private nonisolated static func frame(of id: CGWindowID) -> CGRect? {
        var raw = UnsafeRawPointer(bitPattern: UInt(id))
        guard let ids = CFArrayCreate(nil, &raw, 1, nil),
              let list = CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]],
              let bounds = list.first?[kCGWindowBounds as String] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as! CFDictionary)
    }
}

private let focusTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let focus = Unmanaged<FocusFollowsMouse>.fromOpaque(refcon).takeUnretainedValue()
    let location = event.location
    let flags = event.flags
    MainActor.assumeIsolated {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            focus.reenable()
        } else {
            focus.mouseMoved(to: location, flags: flags)
        }
    }
    return Unmanaged.passUnretained(event)
}
