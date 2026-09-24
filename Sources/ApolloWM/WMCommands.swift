import AppKit
import Carbon.HIToolbox

@MainActor
public final class WMCommands {
    public typealias Action = Command

    private let engine: TilingEngine

    public var superFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    public var log: (String) -> Void = { print($0) }

    public var quitWithLastWindow = true
    public var neverQuit: Set<String> = ["com.apple.finder"]

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

    public var useAppleDesktops = true

    public init(engine: TilingEngine) {
        self.engine = engine
        engine.onScratchpadElsewhere = { [weak self] window, space in
            guard let number = Spaces.ordered().firstIndex(of: space).map({ $0 + 1 }) else { return }
            self?.send(window.windowID, toDesktop: number)
        }
    }

    public func start() {
        guard useAppleDesktops else { return }
        let (shortcuts, changed) = DesktopShortcuts.ensure(modifiers: superFlags)
        desktopShortcuts = shortcuts
        if changed { log("set Apple's Switch to Desktop 1-9 shortcuts to Super + number") }
    }

    public func stop() {
        engine.onScratchpadElsewhere = nil
    }

    public var terminals = ["net.kovidgoyal.kitty", "com.mitchellh.ghostty", "com.apple.Terminal"]

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
            if useAppleDesktops {
                switchAppleDesktop(number)
            } else {
                engine.switchWorkspace(to: number)
            }
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
        if action != .closeWindow, let id = engine.focused, let window = engine.windows[id] {
            perform(action, on: window)
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let focused = WindowDiscovery.focusedWindow()
            await MainActor.run { self?.perform(action, on: focused) }
        }
    }

    public static let echoWindow: CFTimeInterval = 0.4
    private var lastPosted: (number: Int, time: CFTimeInterval)?

    private func switchAppleDesktop(_ number: Int) {
        let now = CACurrentMediaTime()
        if let last = lastPosted, last.number == number, now - last.time < Self.echoWindow { return }
        guard let shortcut = desktopShortcuts[number] else {
            log("desktop \(number): desktop shortcuts are not set")
            return
        }
        lastPosted = (number, now)
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let key = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: keyDown)
            key?.flags = shortcut.flags
            key?.post(tap: .cghidEventTap)
        }
    }

    private func perform(_ action: Action, on focused: AXWindow?) {
        if action == .closeWindow {
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

    static func waitForModifiersReleased() async {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        for _ in 0..<80 {
            if CGEventSource.flagsState(.hidSystemState).intersection(modifiers).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                 kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9].map(Int64.init)

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
