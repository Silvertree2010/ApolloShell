import AppKit
import Carbon.HIToolbox

/// Super + key shortcuts for the focused window. Super is fn held, which
/// Karabiner sends as ⌘⌃⌥⇧; the matching key presses are swallowed so the
/// app never sees them.
@MainActor
public final class KeyBindings {
    /// What a key does; see ApolloWMCore's Command for the list.
    public typealias Action = Command

    private let engine: TilingEngine
    private var tap: CFMachPort?
    /// Keys whose key-down we swallowed; their key-up is swallowed too.
    private var swallowed: Set<Int64> = []

    public var superFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    /// Virtual key code (Carbon kVK_*) to action, pressed together with Super.
    public var bindings: [Int64: Action] = KeyBindings.table(Command.defaultBindings)

    static func table(_ bindings: [UInt16: Command]) -> [Int64: Action] {
        Dictionary(uniqueKeysWithValues: bindings.map { (Int64($0.key), $0.value) })
    }

    /// Takes the keys of a config file (defaults included).
    public func apply(_ config: TWMConfig) {
        bindings = Self.table(config.bindings)
    }

    public var log: (String) -> Void = { print($0) }

    /// Super + Q on the last window of an app quits it, the way ⌘Q would.
    /// Without this, apps that stay alive without windows (kitty, and one
    /// process per new instance) pile up invisible windows.
    public var quitWithLastWindow = true
    /// Apps that are never quit this way: the Finder always runs, and we
    /// are not going to quit ourselves.
    public var neverQuit: Set<String> = ["com.apple.finder"]

    /// Looks a moment after the close (apps may ask to save) and quits the
    /// app when no normal window of it is left.
    private func quitIfLastWindowWent(pid: pid_t, closed: CGWindowID) {
        guard pid != getpid(), let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              !neverQuit.contains(app.bundleIdentifier ?? "") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !app.isTerminated else { return }
                let element = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(element, 0.3)
                let windows = element.value(kAXWindowsAttribute) as? [AXUIElement] ?? []
                let left = windows.filter { window in
                    guard let id = window.windowID, id != closed else { return false }
                    return window.bool(kAXMinimizedAttribute) != true
                }
                guard left.isEmpty else { return }
                self.log("last window closed, quitting \(app.localizedName ?? "\(pid)")")
                app.terminate()
            }
        }
    }

    /// Super+1..9 shows Apple desktop 1-9 (our own workspaces stay unused):
    /// start() sets Apple's "Switch to Desktop N" shortcuts to Super + N and
    /// those key presses are left to macOS (see DesktopShortcuts).
    public var useAppleDesktops = true

    public init(engine: TilingEngine) {
        self.engine = engine
        engine.onScratchpadElsewhere = { [weak self] window, space in
            guard let number = Spaces.ordered().firstIndex(of: space).map({ $0 + 1 }) else { return }
            self?.send(window.windowID, toDesktop: number)
        }
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

    /// Apple's "Switch to Desktop N" shortcuts follow `useAppleDesktops`:
    /// on, macOS switches on Super + N itself; off, the TWM's own
    /// workspaces do. Applies while it runs.
    public func setUseAppleDesktops(_ use: Bool) {
        guard use != useAppleDesktops else { return }
        useAppleDesktops = use
        if use {
            let (shortcuts, _) = DesktopShortcuts.ensure(modifiers: superFlags)
            desktopShortcuts = shortcuts
        }
        log("desktops: \(use ? "Apple's" : "the TWM's own")")
    }

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
        case .focusDisplay(let next):
            engine.focusDisplay(next: next)
            return
        default:
            break
        }
        // The rest acts on the focused window. The engine knows it when it is
        // one of its own (it follows focus changes and sets it on every
        // keyboard focus), so fast presses act one after the other at once;
        // asking the app is a round trip and two quick presses would both
        // see the old window. Closing acts on any window, so it always asks.
        if action != .closeWindow, let id = engine.focused, let window = engine.windows[id] {
            perform(action, on: window)
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let focused = WindowDiscovery.focusedWindow()
            await MainActor.run { self?.perform(action, on: focused) }
        }
    }

    /// One line from the command socket: a command in its text form, or
    /// `windows` / `ping`. Returns the reply.
    public func reply(to line: String) -> String {
        switch line.lowercased() {
        case "ping": return "pong"
        case "windows": return engine.describeWindows()
        default: break
        }
        guard let command = Command(parsing: line) else { return "error: unknown command `\(line)`" }
        switch command {
        case .workspace(let number) where useAppleDesktops:
            // A key press would reach macOS by itself; from outside, press
            // Apple's shortcut for it.
            guard let shortcut = desktopShortcuts[number] else { return "error: desktop shortcuts are not set" }
            let source = CGEventSource(stateID: .hidSystemState)
            for keyDown in [true, false] {
                let key = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: keyDown)
                key?.flags = shortcut.flags
                key?.post(tap: .cghidEventTap)
            }
        default:
            perform(command)
        }
        return "ok"
    }

    private func perform(_ action: Action, on focused: AXWindow?) {
        if action == .closeWindow {
            // Any focused window, managed or not.
            guard let focused else { return }
            if !focused.close() {
                log("close: \(focused.title) has no close button")
                return
            }
            if quitWithLastWindow { quitIfLastWindowWent(pid: focused.pid, closed: focused.windowID) }
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
        case .moveTab(let forward): engine.moveTab(id, forward: forward)
        case .groupApp: engine.groupApp(of: id)
        case .grow(let fraction): engine.grow(id, by: fraction)
        case .sendToDesktop(let number): send(id, toDesktop: number)
        case .sendToDisplay(let next): engine.sendToDisplay(id, next: next)
        case .toggleFloating: engine.toggleFloating(id)
        case .toggleFullscreen: engine.toggleFullscreen(id)
        case .workspace, .equalize, .newTerminal, .closeWindow, .cycleFocus,
             .scratchpad, .focusDisplay: break
        }
    }

    /// Super + T. A terminal that already runs gets a new window through its
    /// own ⌘N, never a second instance: starting one per press left 45 kitty
    /// processes behind, each holding invisible windows, and every window
    /// scan on the Mac grew with them.
    private func openTerminal() {
        let installed = terminals.compactMap { id -> (id: String, url: URL)? in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { (id, $0) }
        }
        guard let choice = installed.first else { return }
        let running = installed.lazy.compactMap { entry in
            NSRunningApplication.runningApplications(withBundleIdentifier: entry.id).first
        }.first
        guard let running else {
            NSWorkspace.shared.openApplication(at: choice.url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            return
        }
        running.activate()
        Task { [weak self] in
            await Self.waitForModifiersReleased()
            guard self != nil else { return }
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let key = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_N), keyDown: down)
                key?.flags = .maskCommand
                key?.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(15))
            }
        }
    }

    /// Waits (at most 2 s) until Super is no longer held: the ⌘N above would
    /// otherwise carry the held modifiers along.
    static func waitForModifiersReleased() async {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        for _ in 0..<80 {
            if CGEventSource.flagsState(.hidSystemState).intersection(modifiers).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// Returns true when the event is ours and must not reach the app.
    fileprivate func handle(_ type: CGEventType, key: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        switch type {
        case .keyDown:
            guard flags.intersection(superFlags) == superFlags else { return false }
            guard let action = bindings[key] else {
                log("Super + key \(key) (\(KeyNames.name(UInt16(key)) ?? "?")): no command")
                return false
            }
            if !isRepeat { log("Super + \(KeyNames.name(UInt16(key)) ?? "\(key)") -> \(action.text)") }
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

    private static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                 kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9].map(Int64.init)

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
