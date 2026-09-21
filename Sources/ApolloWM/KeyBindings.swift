import AppKit
import Carbon.HIToolbox

/// Super + key shortcuts for the focused window. Super is fn held, which
/// Karabiner sends as ⌘⌃⌥⇧; the matching key presses are swallowed so the
/// app never sees them.
@MainActor
public final class KeyBindings {
    public enum Action: Sendable, Equatable {
        case toggleFloating
        case toggleFullscreen
        /// Close the focused window (like its red button; the app keeps running).
        case closeWindow
        /// Show workspace n. While a window is held with the mouse, it comes along.
        case workspace(Int)
    }

    private let engine: TilingEngine
    private var tap: CFMachPort?
    /// Keys whose key-down we swallowed; their key-up is swallowed too.
    private var swallowed: Set<Int64> = []

    public var superFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    /// Virtual key code (Carbon kVK_*) to action, pressed together with Super.
    public var bindings: [Int64: Action] = {
        var map: [Int64: Action] = [
            Int64(kVK_Space): .toggleFloating,
            Int64(kVK_ANSI_F): .toggleFullscreen,
            Int64(kVK_ANSI_Q): .closeWindow,
        ]
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                      kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (index, key) in digits.enumerated() { map[Int64(key)] = .workspace(index + 1) }
        return map
    }()

    public var log: (String) -> Void = { print($0) }

    /// Super+1..9 shows Apple desktop 1-9 (our own workspaces stay unused):
    /// start() sets Apple's "Switch to Desktop N" shortcuts to Super + N and
    /// those key presses are left to macOS (see DesktopShortcuts).
    public var useAppleDesktops = true

    public init(engine: TilingEngine) {
        self.engine = engine
    }

    /// Returns false when the event tap cannot be created (missing permission).
    public func start() -> Bool {
        if useAppleDesktops {
            let (_, changed) = DesktopShortcuts.ensure(modifiers: superFlags)
            if changed { log("set Apple's Switch to Desktop 1-9 shortcuts to Super + number") }
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: keyTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func perform(_ action: Action) {
        if case .workspace(let number) = action {
            if !useAppleDesktops {
                engine.switchWorkspace(to: number)
            }
            return
        }
        if action == .closeWindow {
            // Any focused window, managed or not.
            guard let window = WindowDiscovery.focusedWindow() else { return }
            if !window.close() { log("close: \(window.title) has no close button") }
            return
        }
        guard let id = WindowDiscovery.focusedWindowID(), engine.windows[id] != nil else {
            log("\(action): focused window is not managed")
            return
        }
        switch action {
        case .toggleFloating: engine.toggleFloating(id)
        case .toggleFullscreen: engine.toggleFullscreen(id)
        case .workspace, .closeWindow: break
        }
    }

    /// Returns true when the event is ours and must not reach the app.
    fileprivate func handle(_ type: CGEventType, key: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        switch type {
        case .keyDown:
            guard flags.intersection(superFlags) == superFlags, let action = bindings[key] else { return false }
            // Super + digit belongs to macOS then: it switches the desktop itself.
            if useAppleDesktops, case .workspace = action { return false }
            swallowed.insert(key)
            if !isRepeat { perform(action) }
            return true
        case .keyUp:
            return swallowed.remove(key) != nil
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        default:
            return false
        }
    }
}

private let keyTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let bindings = Unmanaged<KeyBindings>.fromOpaque(refcon).takeUnretainedValue()
    let key = event.getIntegerValueField(.keyboardEventKeycode)
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let flags = event.flags
    let swallow = MainActor.assumeIsolated {
        bindings.handle(type, key: key, flags: flags, isRepeat: isRepeat)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
