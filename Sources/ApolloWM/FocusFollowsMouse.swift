import AppKit

/// Focus follows the mouse (like AutoRaise, or Hyprland's follow_mouse):
/// when the mouse rests over a managed window for `delay`, that window is
/// raised and its app activated.
///
/// Never while a button is held, a window is dragged or resized, or a
/// disable key (none by default) is down, and never when something else lies on
/// top at that spot (a menu, a popup, a panel of the host).
@MainActor
public final class FocusFollowsMouse {
    private let engine: TilingEngine
    private var tap: CFMachPort?
    private var pending: DispatchWorkItem?
    private var lastFocused: CGWindowID?

    public var isEnabled = true
    /// How long the mouse must rest over a window. AutoRaise: 50 ms.
    public var delay: TimeInterval = 0.05
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
        return true
    }

    fileprivate func mouseMoved(to point: CGPoint, flags: CGEventFlags) {
        pending?.cancel()
        guard isEnabled, flags.intersection(disableFlags).isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.focusWindow(at: point) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func focusWindow(at point: CGPoint) {
        guard NSEvent.pressedMouseButtons == 0, !engine.isSwitchingSpace,
              engine.dragging == nil, engine.resizing == nil,
              let id = engine.window(at: point),
              let window = engine.windows[id],
              Self.topmostWindow(at: point) == id else {
            // Over nothing we manage: entering a window later focuses it again.
            if engine.window(at: point) == nil { lastFocused = nil }
            return
        }
        // Focus on entering a window, not again while resting inside it.
        // (Asking the system which window has focus is a round trip into
        // the focused app, too slow for every mouse stop.)
        guard id != lastFocused else { return }
        lastFocused = id
        if ProcessInfo.processInfo.environment["APOLLOWM_TRACE"] == "1" {
            FileHandle.standardError.write(Data("focus: \(window.title) (desk \(engine.desk))\n".utf8))
        }
        let pid = window.pid
        // Raise on the app's thread; a slow app must not stall the mouse.
        engine.raise(id) {
            _ = window.element.set(kAXMainAttribute, bool: true)
            // Without .activateAllWindows only the raised (main) window comes forward.
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    /// The frontmost on-screen window at `point`, whatever its layer, so a
    /// menu or panel lying on top blocks focusing the tile underneath.
    static func topmostWindow(at point: CGPoint) -> CGWindowID? {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]] ?? []
        for info in infos {
            guard let bounds = info[kCGWindowBounds as String],
                  let frame = CGRect(dictionaryRepresentation: bounds as! CFDictionary),
                  frame.contains(point),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 else { continue }
            return info[kCGWindowNumber as String] as? CGWindowID
        }
        return nil
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
