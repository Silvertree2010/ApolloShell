import AppKit
import ApolloProviders
import ApolloShellCore
import ApolloWM
import os

@MainActor
final class SystemWMEngine: WMEngine {
    private let layoutFile: URL
    private let log = Logger(category: "wm")

    private var engine: TilingEngine?
    private var watcher: WindowWatcher?
    private var drags: DragTracker?
    private var commands: WMCommands?
    private var focus: FocusFollowsMouse?
    private var reserved: [String: WMReserved] = [:]

    var onChange: (@MainActor () -> Void)?

    init(layoutFile: URL) {
        self.layoutFile = layoutFile
    }

    var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    var screenRecordingAllowed: Bool { CGPreflightScreenCaptureAccess() }

    var screens: [WMScreen] {
        let all = NSScreen.screens
        return all.enumerated().map { index, screen in
            WMScreen(key: ScreenInfo.key(name: screen.localizedName, frame: screen.frame), isMain: index == 0)
        }
    }

    func start(_ settings: WMSettings) -> Bool {
        guard engine == nil else { return true }
        guard AXIsProcessTrusted() else {
            log.notice("wm needs the Accessibility permission")
            return false
        }
        guard let area = WindowDiscovery.mainArea() else { return false }
        if WindowDiscovery.isStageManagerOn {
            log.notice("Stage Manager is on; it fights tiling")
        }
        var options = TilingEngine.Options()
        options.reservedByDisplay = reservedByDisplay(\.edge)
        options.visibleReservedByDisplay = reservedByDisplay(\.visible)
        let engine = TilingEngine(area: area, options: options)
        engine.log = { [log] message in log.debug("\(message, privacy: .public)") }
        if let data = try? Data(contentsOf: layoutFile),
           let snapshot = try? JSONDecoder().decode(TilingEngine.Snapshot.self, from: data) {
            let existing = Set((CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
                .compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
            engine.restore(snapshot, alive: { existing.contains($0) })
        }
        if let space = Spaces.current() { engine.switchSpace(to: space) }
        engine.onSettled = { [weak self] in
            self?.save()
            self?.onChange?()
        }
        engine.onDisplaysChanged = { [weak self, weak engine] in
            guard let self, let engine else { return }
            engine.options.reservedByDisplay = reservedByDisplay(\.edge)
            engine.options.visibleReservedByDisplay = reservedByDisplay(\.visible)
            onChange?()
        }
        engine.onActiveWindowChanged = { [weak self] _ in self?.onChange?() }
        engine.onTabBarsChanged = { [weak self] _ in self?.onChange?() }
        self.engine = engine

        let focus = FocusFollowsMouse(engine: engine)
        focus.log = engine.log
        self.focus = focus
        let commands = WMCommands(engine: engine)
        commands.log = engine.log
        commands.useAppleDesktops = settings.appleDesktops
        self.commands = commands
        let drags = DragTracker(engine: engine)
        self.drags = drags
        configure(settings)

        engine.adopt(WindowDiscovery.tileableWindows(in: area))
        engine.startSnapshots()
        let watcher = WindowWatcher(engine: engine)
        watcher.log = engine.log
        watcher.start()
        self.watcher = watcher
        _ = drags.start()
        commands.start()
        _ = focus.start()
        engine.focusChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak engine] in engine?.focusChanged() }
        log.notice("wm started")
        return true
    }

    func configure(_ settings: WMSettings) {
        guard let engine else { return }
        engine.options.gaps = Gaps(outer: settings.outerGap, inner: settings.innerGap)
        engine.options.response = settings.springResponse
        engine.options.frameRate = settings.frameRate
        engine.options.tabBarHeight = settings.tabBarHeight
        engine.options.scratchpadShare = settings.scratchpadShare
        engine.options.layout = settings.layout == .canvas ? .canvas : .dwindle
        engine.options.columnWidth = settings.columnWidth
        engine.options.centerFocusedColumn = settings.centerFocused
        engine.options.resize = switch settings.resize {
        case .proxy: .proxy
        case .smooth: .smooth
        case .snap: .snap
        }
        engine.options.reservedByDisplay = reservedByDisplay(\.edge)
        engine.options.visibleReservedByDisplay = reservedByDisplay(\.visible)
        drags?.superFlags = Self.flags(settings.dragModifiers)
        drags?.scrollPans = settings.scrollPans
        drags?.scrollSpeed = settings.scrollSpeed
        drags?.invertScroll = settings.invertScroll
        commands?.setUseAppleDesktops(settings.appleDesktops)
        commands?.terminals = settings.terminals
        focus?.isEnabled = settings.focusFollowsMouse
        focus?.delay = settings.focusDelay
        focus?.disableFlags = Self.flags(settings.focusSuspendWith)
        engine.apply(rules: settings.rules)
        engine.relayout()
    }

    func stop() {
        guard let engine else { return }
        focus?.stop()
        commands?.stop()
        drags?.stop()
        watcher?.stop()
        engine.onSettled = nil
        engine.onDisplaysChanged = nil
        engine.onActiveWindowChanged = nil
        engine.onTabBarsChanged = nil
        engine.stopSnapshots()
        engine.releaseAll()
        save(engine)
        focus = nil
        commands = nil
        drags = nil
        watcher = nil
        self.engine = nil
        log.notice("wm stopped")
    }

    func perform(_ command: Command) {
        commands?.perform(command)
    }

    func setLayout(_ layout: WMSettings.Layout) {
        guard let engine else { return }
        engine.options.layout = layout == .canvas ? .canvas : .dwindle
        engine.relayout()
    }

    func focusWindow(_ id: UInt32) -> Bool {
        guard let engine, engine.windows[id] != nil else { return false }
        if engine.group(of: id) != nil {
            engine.activateTab(id)
        } else {
            engine.focus(id)
        }
        return true
    }

    func setReserved(_ insets: [String: WMReserved]) {
        guard insets != reserved else { return }
        reserved = insets
        guard let engine else { return }
        engine.options.reservedByDisplay = reservedByDisplay(\.edge)
        engine.options.visibleReservedByDisplay = reservedByDisplay(\.visible)
        engine.relayout()
    }

    func state() -> WMState {
        guard let engine else { return WMState() }
        let order = Spaces.ordered()
        let desktop = (order.firstIndex(of: engine.space) ?? 0) + 1
        return WMState(
            layout: engine.isCanvas ? .canvas : .dwindle,
            windows: windows(engine),
            focused: engine.focused,
            desktop: desktop,
            workspace: engine.workspace,
            tabBars: tabBars(engine)
        )
    }

    private func windows(_ engine: TilingEngine) -> [WMWindowInfo] {
        let data = Data(engine.describeWindows().utf8)
        let items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let raw = item["id"] as? Int, let id = UInt32(exactly: raw) else { return nil }
            let pid = Int32(item["pid"] as? Int ?? 0)
            let frame = (item["frame"] as? [String: Double]).map {
                CGRect(x: $0["x"] ?? 0, y: $0["y"] ?? 0, width: $0["width"] ?? 0, height: $0["height"] ?? 0)
            }
            return WMWindowInfo(
                id: id,
                pid: pid,
                app: item["app"] as? String ?? "",
                bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                title: item["title"] as? String ?? "",
                floating: item["floating"] as? Bool ?? false,
                scratchpad: item["scratchpad"] as? Bool ?? false,
                fullscreen: item["fullscreen"] as? Bool ?? false,
                desktop: item["desktop"] as? Int,
                display: item["display"] as? Int,
                workspace: engine.desk(of: id)?.workspace,
                group: (item["group"] as? [Int] ?? []).compactMap { UInt32(exactly: $0) },
                frame: frame
            )
        }
    }

    private func tabBars(_ engine: TilingEngine) -> [WMTabBarInfo] {
        let keys = screenKeysByUUID()
        return engine.tabBars().map { bar in
            let screen = engine.screens.first { $0.bounds.contains(CGPoint(x: bar.frame.midX, y: bar.frame.maxY)) } ?? engine.screens.first
            let origin = screen?.bounds.origin ?? .zero
            let tabs = bar.tabs.map { tab in
                WMTabInfo(window: tab.windowID, title: tab.title, app: NSRunningApplication(processIdentifier: tab.pid)?.localizedName ?? "")
            }
            return WMTabBarInfo(
                frame: bar.frame.offsetBy(dx: -origin.x, dy: -origin.y),
                screen: screen.flatMap { keys[$0.uuid] } ?? "",
                active: bar.active,
                tabs: tabs
            )
        }
    }

    private func screenKeysByUUID() -> [String: String] {
        var result: [String: String] = [:]
        for screen in NSScreen.screens {
            guard let uuid = Spaces.uuid(of: screen) else { continue }
            result[uuid] = ScreenInfo.key(name: screen.localizedName, frame: screen.frame)
        }
        return result
    }

    private func reservedByDisplay(_ part: KeyPath<WMReserved, WMInsets>) -> [String: NSEdgeInsets] {
        var result: [String: NSEdgeInsets] = [:]
        for screen in NSScreen.screens {
            guard let uuid = Spaces.uuid(of: screen),
                  let insets = reserved[ScreenInfo.key(name: screen.localizedName, frame: screen.frame)]?[keyPath: part] else { continue }
            result[uuid] = NSEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
        }
        return result
    }

    private static func flags(_ modifiers: HotKeyModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return flags
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
