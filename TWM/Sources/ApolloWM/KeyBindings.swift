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
        /// Wider/taller (positive) or narrower/shorter by these fractions of the area.
        case grow(CGSize)
        case newTerminal
        /// Join the neighbor's tile as a tab, or leave a tab group.
        case toggleGroup
        /// Next (true) or previous tab of a group.
        case cycleTab(Bool)
        case toggleFloating
        case toggleFullscreen
        /// Close the focused window (like its red button; the app keeps running).
        case closeWindow
        /// Show workspace n. While a window is held with the mouse, it comes along.
        case workspace(Int)
        /// Send the focused window to desktop n and show that desktop.
        case sendToDesktop(Int)
        /// Resize mode: arrows or H J K L resize, Escape or Return ends it.
        case resizeMode
        /// Send mode: the next digit sends the window to that desktop.
        case sendMode
        /// Show or hide the scratchpad window, or make the focused window it.
        case scratchpad
    }

    /// Like Hyprland's submaps: after Super + R or Super + M the next keys
    /// mean something else, with or without Super.
    public enum Mode: String, Sendable, Equatable {
        case normal
        case resize
        case send
    }

    public private(set) var mode = Mode.normal {
        didSet { if mode != oldValue { onModeChanged?(mode) } }
    }
    public var onModeChanged: ((Mode) -> Void)?
    /// A mode ends by itself after this long without a key.
    public var modeTimeout: TimeInterval = 6
    private var modeTimer: DispatchWorkItem?
    /// One press in resize mode, as a fraction of the area.
    public var resizeStep: CGFloat = 0.03

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
            Int64(kVK_ANSI_Minus): .grow(CGSize(width: -0.05, height: 0)),
            Int64(kVK_ANSI_Equal): .grow(CGSize(width: 0.05, height: 0)),
            Int64(kVK_ANSI_R): .resizeMode,
            Int64(kVK_ANSI_M): .sendMode,
            Int64(kVK_ANSI_S): .scratchpad,
            Int64(kVK_Return): .newTerminal,
            Int64(kVK_ANSI_G): .toggleGroup,
            Int64(kVK_ANSI_RightBracket): .cycleTab(true),
            Int64(kVK_ANSI_LeftBracket): .cycleTab(false),
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
            let (shortcuts, changed) = DesktopShortcuts.ensure(modifiers: superFlags)
            desktopShortcuts = shortcuts
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

    /// Removes the event tap; start() can be called again later.
    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
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
        case .resizeMode:
            enter(.resize)
            return
        case .sendMode:
            enter(.send)
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
        case .scratchpad:
            engine.toggleScratchpad(focused: id)
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
        case .toggleGroup: engine.toggleGroup(id)
        case .cycleTab(let forward): engine.cycleTab(from: id, forward: forward)
        case .grow(let fraction): engine.grow(id, by: fraction)
        case .sendToDesktop(let number): send(id, toDesktop: number)
        case .toggleFloating: engine.toggleFloating(id)
        case .toggleFullscreen: engine.toggleFullscreen(id)
        case .workspace, .equalize, .newTerminal, .closeWindow, .cycleFocus, .resizeMode, .sendMode, .scratchpad: break
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
            if mode != .normal, let taken = handleInMode(key: key, flags: flags, isRepeat: isRepeat) {
                if taken { swallowed.insert(key) }
                return taken
            }
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

    // MARK: Modes

    private static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                 kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9].map(Int64.init)

    public func enter(_ mode: Mode) {
        self.mode = mode
        log("mode: \(mode.rawValue)")
        restartModeTimer()
    }

    public func leaveMode() {
        modeTimer?.cancel()
        modeTimer = nil
        mode = .normal
    }

    private func restartModeTimer() {
        modeTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.leaveMode() } }
        modeTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + modeTimeout, execute: work)
    }

    /// A key while a mode is on. Nil lets normal handling run (the mode has
    /// ended); true swallows the key, false passes it on.
    private func handleInMode(key: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool? {
        let exits = [Int64(kVK_Escape), Int64(kVK_Return)]
        if exits.contains(key) {
            leaveMode()
            return true
        }
        switch mode {
        case .resize:
            let step = resizeStep
            let grow: CGSize? = switch Int(key) {
            case kVK_LeftArrow, kVK_ANSI_H: CGSize(width: -step, height: 0)
            case kVK_RightArrow, kVK_ANSI_L: CGSize(width: step, height: 0)
            case kVK_UpArrow, kVK_ANSI_K: CGSize(width: 0, height: -step)
            case kVK_DownArrow, kVK_ANSI_J: CGSize(width: 0, height: step)
            default: nil
            }
            if let grow {
                restartModeTimer()
                perform(.grow(grow))
                return true
            }
            if key == Int64(kVK_ANSI_R), flags.intersection(superFlags) == superFlags {
                leaveMode()
                return true
            }
        case .send:
            if let index = Self.digits.firstIndex(of: key) {
                leaveMode()
                if !isRepeat { perform(.sendToDesktop(index + 1)) }
                return true
            }
        case .normal:
            return nil
        }
        // Any other key ends the mode and does what it normally does.
        leaveMode()
        return nil
    }

    /// Apple's switch shortcut for each desktop, set by start().
    private var desktopShortcuts: [Int: DesktopShortcuts.Shortcut] = [:]

    private func send(_ id: CGWindowID, toDesktop number: Int) {
        guard let window = engine.windows[id] else { return }
        let shortcut = desktopShortcuts[number]
            ?? DesktopShortcuts.Shortcut(keyCode: CGKeyCode(Self.digits[number - 1]), flags: superFlags)
        Task { [weak self] in
            let result = await DesktopMover.send(window, toDesktop: number, shortcut: shortcut)
            if case .failure(let failure) = result { self?.log("send to desktop \(number): \(failure)") }
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
