import ApolloShellCore
import ApolloWM
import AppKit
import Observation
import os

/// Runs the tiling window manager (TWM/, ApolloWM) inside ApolloShell and
/// follows Nexus > TWM: on starts it, off lets every window stay where it
/// is and stops it, the other settings apply live.
///
/// Tiles keep free what the bars cover, on every edge of every screen. The arrangement is saved
/// in twm-layout.json after every glide and on quit.
@MainActor
final class TWMController {
    private let settings: ShellSettingsStore
    private let layoutFile: URL
    private let log = Logger(category: "twm")
    private var observation: Task<Void, Never>?

    private var engine: TilingEngine?
    private var watcher: WindowWatcher?
    private var drags: DragTracker?
    private var keys: KeyBindings?
    private var focus: FocusFollowsMouse?
    private var tabBars: TWMTabBars?
    private var border: TWMBorder?
    private var server: CommandServer?

    /// Called with true while tiling runs: the window guard (which pushes
    /// windows out of the sidebar's strip) must pause then, or both would
    /// move the same windows. Set by the AppDelegate.
    var onRunningChange: (Bool) -> Void = { _ in } {
        didSet { onRunningChange(engine != nil) }
    }

    /// What the bars cover per screen key (`ScreenInfo.key`), from the
    /// sidebar. Set by the AppDelegate on every change.
    private var barReserved: [String: ReservedInsets] = [:]

    func setReserved(_ reserved: [String: ReservedInsets]) {
        guard reserved != barReserved else { return }
        barReserved = reserved
        guard let engine else { return }
        engine.options.reservedByDisplay = reservedByDisplay()
        engine.relayout()
    }

    /// The bars' room by display UUID, the way the engine knows displays.
    private func reservedByDisplay() -> [String: NSEdgeInsets] {
        var result: [String: NSEdgeInsets] = [:]
        for screen in ShellScreens.current() {
            guard let insets = barReserved[screen.info.key],
                  let uuid = ShellScreens.uuid(of: screen.displayID) else { continue }
            result[uuid] = NSEdgeInsets(top: insets.top, left: insets.left,
                                        bottom: insets.bottom, right: insets.right)
        }
        return result
    }

    init(settings: ShellSettingsStore, layoutFile: URL = ShellFiles.live.twmLayout) {
        self.settings = settings
        self.layoutFile = layoutFile
        observation = Task { [weak self, settings] in
            for await twm in Observations({ settings.settings.twm }) {
                self?.apply(twm)
            }
        }
    }

    /// On quit: windows stay where they are, the layout is saved.
    func terminate() {
        observation?.cancel()
        stop()
    }

    private func apply(_ twm: TWMSettings) {
        if twm.enabled, engine == nil {
            start(twm)
        } else if !twm.enabled, engine != nil {
            stop()
        } else if let engine {
            configure(engine, twm)
        }
    }

    private func configure(_ engine: TilingEngine, _ twm: TWMSettings) {
        engine.options.gaps = Gaps(outer: twm.outerGap, inner: twm.innerGap)
        engine.options.response = twm.glideDuration
        engine.options.tabBarHeight = twm.tabBarHeight
        engine.options.reservedByDisplay = reservedByDisplay()
        engine.options.scratchpadShare = twm.scratchpadShare
        engine.options.layout = twm.layout == .canvas ? .canvas : .dwindle
        engine.options.columnWidth = twm.columnWidth
        engine.options.centerFocusedColumn = twm.centerFocusedColumn
        drags?.scrollPans = twm.scrollPans
        drags?.scrollSpeed = twm.scrollSpeed
        drags?.invertScroll = twm.invertScroll
        keys?.setUseAppleDesktops(twm.appleDesktops)
        keys?.quitWithLastWindow = twm.quitWithLastWindow
        keys?.terminals = twm.terminal.isEmpty
            ? ["net.kovidgoyal.kitty", "com.mitchellh.ghostty", "com.apple.Terminal"]
            : [twm.terminal]
        engine.options.resize = switch twm.resize {
        case .proxy: .proxy
        case .smooth: .smooth
        case .snap: .snap
        }
        focus?.isEnabled = twm.focusFollowsMouse
        focus?.delay = Double(twm.focusDelayMilliseconds) / 1000
        border?.width = twm.borderWidth
        border?.radius = twm.borderRadius
        engine.relayout()
    }

    private func start(_ twm: TWMSettings) {
        guard AXIsProcessTrusted() else {
            log.notice("TWM needs the Accessibility permission")
            return
        }
        guard let area = WindowDiscovery.mainArea() else { return }
        if WindowDiscovery.isStageManagerOn {
            log.notice("Stage Manager is on; it fights tiling")
        }
        var options = TilingEngine.Options()
        options.reservedByDisplay = reservedByDisplay()
        let engine = TilingEngine(area: area, options: options)
        // Debug level only: the messages name window titles (chats, URLs,
        // documents), and debug messages are never written to disk. Read
        // them live with `log stream --level debug`.
        engine.log = { [log] message in log.debug("\(message, privacy: .public)") }
        if let data = try? Data(contentsOf: layoutFile),
           let snapshot = try? JSONDecoder().decode(TilingEngine.Snapshot.self, from: data) {
            let existing = Set((CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
                .compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
            engine.restore(snapshot, alive: { existing.contains($0) })
        }
        if let space = Spaces.current() { engine.switchSpace(to: space) }
        engine.onSettled = { [weak self] in self?.save() }
        engine.onDisplaysChanged = { [weak self, weak engine] in
            guard let self, let engine else { return }
            // A replug hands out new display IDs; the bars' keys stay.
            engine.options.reservedByDisplay = reservedByDisplay()
            TWMStatus.shared.update(from: engine)
        }
        TWMStatus.shared.update(from: engine)
        self.engine = engine

        let focus = FocusFollowsMouse(engine: engine)
        self.focus = focus
        let border = TWMBorder(engine: engine)
        self.border = border
        configure(engine, twm)

        engine.adopt(WindowDiscovery.tileableWindows(in: area))
        engine.startSnapshots()
        let watcher = WindowWatcher(engine: engine)
        watcher.log = engine.log
        watcher.start()
        self.watcher = watcher
        let drags = DragTracker(engine: engine)
        _ = drags.start()
        self.drags = drags
        let keys = KeyBindings(engine: engine)
        keys.log = engine.log
        keys.useAppleDesktops = twm.appleDesktops
        _ = keys.start()
        self.keys = keys
        configure(engine, twm)
        _ = focus.start()
        tabBars = TWMTabBars(engine: engine)
        // Right at the start ApolloShell itself may be in front; look again
        // once the app that had focus is back.
        engine.focusChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak engine] in engine?.focusChanged() }
        let file = TWMConfigFile.shared
        file.onChange = { [weak engine, weak keys] config in
            keys?.apply(config)
            engine?.apply(rules: config.rules)
        }
        file.start()
        let server = CommandServer(path: ShellFiles.live.twmSocket.path) { [weak keys] line in
            keys?.reply(to: line) ?? "error: stopped"
        }
        server.log = engine.log
        server.start()
        self.server = server
        onRunningChange(true)
        log.notice("TWM started")
    }

    private func stop() {
        guard let engine else { return }
        server?.stop()
        server = nil
        TWMConfigFile.shared.onChange = nil
        TWMConfigFile.shared.stop()
        tabBars?.close()
        tabBars = nil
        border?.close()
        border = nil
        focus?.stop()
        keys?.stop()
        drags?.stop()
        watcher?.stop()
        engine.stopSnapshots()
        engine.releaseAll()
        save(engine)
        focus = nil
        keys = nil
        drags = nil
        watcher = nil
        self.engine = nil
        TWMStatus.shared.clear()
        onRunningChange(false)
        log.notice("TWM stopped")
    }

    private func save(_ engine: TilingEngine? = nil) {
        guard let engine = engine ?? self.engine,
              let data = try? JSONEncoder().encode(engine.snapshot()) else { return }
        let file = layoutFile
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}
