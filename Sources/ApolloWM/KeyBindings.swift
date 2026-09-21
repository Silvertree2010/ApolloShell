import AppKit
import Carbon.HIToolbox

/// Super + key shortcuts for the focused window. Super is fn held, which
/// Karabiner sends as ⌘⌃⌥⇧; the matching key presses are swallowed so the
/// app never sees them.
@MainActor
public final class KeyBindings {
    public enum Action: Sendable, Equatable {
        case focus(Direction)
        case swap(Direction)
        case cycleFocus
        case toggleSplit
        case equalize
        /// Wider (positive) or narrower by this fraction of the area.
        case growWidth(CGFloat)
        case newTerminal
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
            Int64(kVK_LeftArrow): .focus(.left),
            Int64(kVK_RightArrow): .focus(.right),
            Int64(kVK_UpArrow): .focus(.up),
            Int64(kVK_DownArrow): .focus(.down),
            Int64(kVK_ANSI_H): .swap(.left),
            Int64(kVK_ANSI_J): .swap(.down),
            Int64(kVK_ANSI_K): .swap(.up),
            Int64(kVK_ANSI_L): .swap(.right),
            Int64(kVK_Tab): .cycleFocus,
            Int64(kVK_ANSI_T): .toggleSplit,
            Int64(kVK_ANSI_E): .equalize,
            Int64(kVK_ANSI_Minus): .growWidth(-0.05),
            Int64(kVK_ANSI_Equal): .growWidth(0.05),
            Int64(kVK_Return): .newTerminal,
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

    /// Terminal opened by Super+Return (bundle ids, first installed wins).
    public var terminals = ["net.kovidgoyal.kitty", "com.mitchellh.ghostty", "com.apple.Terminal"]

    public func perform(_ action: Action) {
        switch action {
        case .workspace(let number):
            if !useAppleDesktops { engine.switchWorkspace(to: number) }
            return
        case .equalize:
            engine.equalize()
            return
        case .newTerminal:
            openTerminal()
            return
        default:
            break
        }
        // The rest acts on the focused window. Asking which one that is is a
        // round trip into the focused app, so it runs off the main thread.
        Task.detached(priority: .userInitiated) { [weak self] in
            let focused = WindowDiscovery.focusedWindow()
            await MainActor.run { self?.perform(action, on: focused) }
        }
    }

    private func perform(_ action: Action, on focused: AXWindow?) {
        if action == .closeWindow {
            // Any focused window, managed or not.
            guard let focused else { return }
            if !focused.close() { log("close: \(focused.title) has no close button") }
            return
        }
        let id = focused.map(\.windowID).flatMap { engine.windows[$0] != nil ? $0 : nil }
        switch action {
        case .cycleFocus:
            engine.cycleFocus(from: id)
            return
        default:
            break
        }
        guard let id else {
            log("\(action): focused window is not managed")
            return
        }
        switch action {
        case .focus(let direction):
            if let other = engine.neighbor(of: id, direction) { engine.focus(other) }
        case .swap(let direction): engine.swap(id, direction)
        case .toggleSplit: engine.toggleSplit(of: id)
        case .growWidth(let fraction): engine.growWidth(of: id, by: fraction)
        case .toggleFloating: engine.toggleFloating(id)
        case .toggleFullscreen: engine.toggleFullscreen(id)
        case .workspace, .equalize, .newTerminal, .closeWindow, .cycleFocus: break
        }
    }

    private func openTerminal() {
        guard let url = terminals.lazy.compactMap({
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }).first else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = url.lastPathComponent != "Terminal.app"
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
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
