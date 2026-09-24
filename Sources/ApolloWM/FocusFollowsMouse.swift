import AppKit

@MainActor
public final class FocusFollowsMouse {
    private let engine: TilingEngine
    private var tap: CFMachPort?
    private var pending: DispatchWorkItem?
    private var lastPoint: CGPoint?
    private var lookahead = CGVector.zero
    private var checking = false
    private var suppressedUntilMove = false
    private var ourActivation: pid_t?
    private var activationObserver: NSObjectProtocol?

    public var isEnabled = true
    public var delay: TimeInterval = 0.025
    public var disableFlags: CGEventFlags = []

    public var log: (String) -> Void = { print($0) }

    public init(engine: TilingEngine) {
        self.engine = engine
    }

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

    public func stop() {
        pending?.cancel()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    private func appActivated(_ pid: pid_t?) {
        if let pid, pid == ourActivation {
            ourActivation = nil
        } else {
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

    private var waitingPoint: CGPoint?

    private func check(_ point: CGPoint) {
        if checking {
            waitingPoint = point
            return
        }
        guard !suppressedUntilMove, NSEvent.pressedMouseButtons == 0,
              !engine.isSwitchingSpace, engine.dragging == nil, engine.resizing == nil else { return }
        checking = true
        let own = getpid()
        let trace = ProcessInfo.processInfo.environment["APOLLOWM_TRACE"] == "1"
        let ignored = engine.ignored
        let done: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.checking = false
            if let next = self.waitingPoint {
                self.waitingPoint = nil
                self.check(next)
            }
        }
        let started = CACurrentMediaTime()
        let confirm: @MainActor @Sendable () -> Void = { [weak self] in self?.engine.focusChanged() }
        let directedSince: @MainActor @Sendable () -> Bool = { [weak self] in
            (self?.engine.lastDirectedFocus ?? 0) > started
        }
        let markOurs: @MainActor @Sendable (pid_t) -> Void = { [weak self] pid in self?.ourActivation = pid }
        Task.detached(priority: .userInitiated) {
            defer { Task { @MainActor in done() } }
            guard !WindowFocus.dockIsBusy(),
                  let window = WindowFocus.window(at: point), window.pid != own,
                  [kAXStandardWindowSubrole, kAXDialogSubrole].contains(window.subrole),
                  window.serverLayer == 0, !ignored.contains(window.windowID) else { return }
            let focused = WindowFocus.focusedWindowID()
            guard focused != window.windowID else { return }
            let frontmost = WindowFocus.frontmostPID()
            if let focused, frontmost == window.pid, let inner = FocusFollowsMouse.frame(of: focused),
               let outer = window.serverFrame, outer.contains(inner) {
                return
            }
            await markOurs(window.pid)
            if trace { FileHandle.standardError.write(Data("focus: \(window.title)\n".utf8)) }
            WindowFocus.focus(window)
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(50))
                if await directedSince() { break }
                if WindowFocus.focusedWindowID() == window.windowID { break }
                WindowFocus.focus(window)
            }
            await confirm()
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
