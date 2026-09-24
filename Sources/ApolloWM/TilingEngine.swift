import ApolloWMCore
import AppKit
import Synchronization

/// One layout slot: a macOS desktop (Space) and one of our own workspaces
/// on it (1-9, Hyprland style).
public struct Desk: Hashable, Sendable, Codable, CustomStringConvertible {
    public var space: SpaceID
    public var workspace: Int

    public init(space: SpaceID, workspace: Int) {
        self.space = space
        self.workspace = workspace
    }

    public var description: String { "\(space)/\(workspace)" }
}

/// How windows are arranged on a desktop.
public enum LayoutMode: String, Sendable, CaseIterable {
    /// Hyprland's dwindle: every window splits the tile it lands in.
    case dwindle
    /// niri's endless strip of columns; the screen is a viewport onto it.
    case canvas
}

/// How window sizes animate during a glide.
public enum ResizeAnimation: String, Sendable, CaseIterable {
    /// The size glides along with the position. Looks best, but apps redraw
    /// their content on every frame (measured: GPU ~36% vs ~20%).
    case smooth
    /// Only the position glides; a shrinking side snaps at the start, a
    /// growing side at the end. Cheap, but the jump is visible.
    case snap
    /// Like smooth, except for apps measured to be slow at resizing
    /// (Spotify, browsers): their windows glide as an unscaled snapshot while
    /// the app resizes once, off screen, and takes its place at the end.
    /// Fast apps (kitty) keep gliding for real, so blur and transparency stay
    /// live. Needs Screen Recording; without it this acts like smooth.
    case proxy
}

/// Owns the tiled windows, their layout tree and the animation loop.
/// Every layout change only sets new spring targets; the loop then glides
/// each window there. Retargeting mid-flight keeps momentum.
@MainActor
public final class TilingEngine {
    public struct Options: Sendable {
        public var gaps = Gaps(outer: 12, inner: 10)
        /// Seconds a move roughly takes.
        public var response: CGFloat = 0.28
        public var frameRate: Double = 120
        /// Room above a tab group's window for the host's tab bar.
        public var tabBarHeight: CGFloat = 30
        /// How much of the area the scratchpad window covers.
        public var scratchpadShare: CGFloat = 0.7
        /// How window sizes animate. Hosts can change it at any time, e.g.
        /// from a settings toggle; it applies from the next frame on.
        public var resize: ResizeAnimation = .smooth
        /// How windows are arranged: the dwindle tiles, or the canvas strip.
        public var layout: LayoutMode = .dwindle
        /// A new column's share of the screen in the canvas layout.
        public var columnWidth: CGFloat = 0.5
        /// The focused column is pulled to the middle of the screen.
        public var centerFocusedColumn = false
        /// Screen space the host keeps for itself, e.g. ApolloShell's 44 pt
        /// sidebar on the left, counted from the display edge. Tiles never go there.
        public var reserved = NSEdgeInsets()
        /// Whether that space is kept free on every display or only on the
        /// main one (the host's bar may stand on one screen only).
        public var reservedOnEveryDisplay = true
        /// Reserved space per display, by the display's UUID. When set it
        /// wins over `reserved` and `reservedOnEveryDisplay`: a display
        /// missing from it keeps nothing free (the host's bars may stand on
        /// any edge, and differently on each screen).
        public var reservedByDisplay: [String: NSEdgeInsets]?

        public init() {}
    }

    /// Usable area of the main display (menu bar and Dock excluded).
    public private(set) var screenArea: CGRect
    public var options: Options

    /// The whole main display, top-left coordinates (menu bar and Dock included).
    public var screenBounds: CGRect {
        screens.first?.bounds ?? screenArea
    }

    /// Where tiles go on the main display. See usable(visible:bounds:).
    public var area: CGRect { usable(visible: screenArea, bounds: screenBounds, insets: reserved(on: screens.first?.uuid)) }

    /// What the host keeps free on the display `uuid` (nil: the main one).
    private func reserved(on uuid: String?) -> NSEdgeInsets {
        if let byDisplay = options.reservedByDisplay {
            return uuid.flatMap { byDisplay[$0] } ?? NSEdgeInsets()
        }
        let isMain = uuid == nil || uuid == screens.first?.uuid
        return isMain || options.reservedOnEveryDisplay ? options.reserved : NSEdgeInsets()
    }

    /// The host's reserved edges count from the display's edge, not on top
    /// of what macOS already keeps free: a Dock on the left (62 pt) and
    /// ApolloShell's sidebar (44 pt) overlap, they do not add up.
    private func usable(visible: CGRect, bounds: CGRect, insets r: NSEdgeInsets) -> CGRect {
        let left = max(visible.minX, bounds.minX + r.left)
        let top = max(visible.minY, bounds.minY + r.top)
        let right = min(visible.maxX, bounds.maxX - r.right)
        let bottom = min(visible.maxY, bounds.maxY - r.bottom)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    // MARK: Displays

    /// A display, in top-left coordinates.
    public struct Screen: Sendable, Equatable {
        /// The window server's UUID for it.
        public let uuid: String
        /// The whole display.
        public let bounds: CGRect
        /// Without the menu bar and the Dock.
        public let visible: CGRect
    }

    /// Every display, the main one (with the menu bar) first.
    public private(set) var screens: [Screen] = []
    /// Which display each known desktop belongs to.
    private var displayOfSpace: [SpaceID: String] = [:]
    /// Each display's desktops in Mission Control order.
    private var desktopOrder: [String: [SpaceID]] = [:]
    /// The desks shown on the other displays right now (the main display's
    /// is `desk`). Empty with one display.
    public private(set) var otherShown: [Desk] = []
    /// True when several displays share their desktops, i.e. "Displays have
    /// separate Spaces" is off in System Settings. macOS then reports one
    /// desktop for everything, so the engine cannot tell the displays'
    /// windows apart; it keeps to the main display and the host says so.
    public private(set) var displaysShareSpaces = false

    /// Every desk on screen right now, the main display's first. A desktop
    /// that is a macOS full-screen app is left out: nothing can be moved
    /// there, and trying made the engine fight macOS 6 times a second.
    public var shownDesks: [Desk] { ([desk] + otherShown).filter { isTileable($0.space) } }

    /// Whether `space` is a normal desktop (not a full-screen app's).
    /// Unknown ones count as normal until the displays have been read.
    public func isTileable(_ space: SpaceID) -> Bool {
        desktopOrder.isEmpty || desktopOrder.values.contains { $0.contains(space) }
    }

    public func isShown(_ desk: Desk) -> Bool { desk == self.desk || otherShown.contains(desk) }

    /// Reads the displays and the desktop each one shows. Call it when
    /// displays or desktops change.
    public func updateDisplays() {
        screens = NSScreen.screens.compactMap { screen in
            guard let uuid = Spaces.uuid(of: screen), let primary = NSScreen.screens.first else { return nil }
            func flipped(_ r: CGRect) -> CGRect {
                CGRect(x: r.minX, y: primary.frame.maxY - r.maxY, width: r.width, height: r.height)
            }
            return Screen(uuid: uuid, bounds: flipped(screen.frame), visible: flipped(screen.visibleFrame))
        }
        if let main = screens.first { screenArea = main.visible }
        let displays = Spaces.displays()
        displayOfSpace = [:]
        desktopOrder = Dictionary(displays.map { ($0.uuid, $0.desktops) }) { first, _ in first }
        for display in displays {
            for space in display.desktops + [display.current] { displayOfSpace[space] = display.uuid }
        }
        let mainUUID = screens.first?.uuid
        let known = Set(screens.map(\.uuid))
        // With "Displays have separate Spaces" off, the window server lists a
        // single display called "Main" for all of them.
        let shared = screens.count > 1 && displays.allSatisfy { !known.contains($0.uuid) }
        if shared != displaysShareSpaces {
            displaysShareSpaces = shared
            if shared {
                log("displays share their desktops: only the main display is arranged")
            }
        }
        let others = displays.filter { $0.uuid != mainUUID && known.contains($0.uuid) }
            .map { Desk(space: $0.current, workspace: activeWorkspace[$0.current] ?? 1) }
        if others != otherShown {
            if !otherShown.isEmpty || !others.isEmpty { log("other displays show \(others)") }
            otherShown = others
            lastSpaceSwitch = CACurrentMediaTime()
        }
        adoptOrphans()
        onDisplaysChanged?()
    }

    /// Called when the displays or the desktops they show changed, so the
    /// host can show what the engine sees.
    public var onDisplaysChanged: (() -> Void)?

    /// Windows whose display was unplugged: macOS has moved them onto a
    /// display that is still there, so they join the desk shown on it.
    private func adoptOrphans() {
        let live = Set(screens.map(\.uuid))
        var moved = 0
        for (id, home) in layouts.spaceOf where !live.contains(displayOfSpace[home.space] ?? "") {
            guard windows[id] != nil, displayOfSpace[home.space] != nil else { continue }
            layouts.remove(id)
            layouts.assign(id, to: desk) { $0.insert(id) }
            strips[home]?.remove(id)
            moved += 1
        }
        for (id, state) in floating where !live.contains(displayOfSpace[state.desk.space] ?? "") {
            guard displayOfSpace[state.desk.space] != nil else { continue }
            floating[id]?.desk = desk
            moved += 1
        }
        if moved > 0 {
            log("a display went away: \(moved) window(s) came over")
            dirtyDesks.insert(desk)
            relayout()
        }
    }

    /// Where tiles go on the display that shows (or holds) `desk`.
    public func area(of desk: Desk) -> CGRect {
        guard let uuid = displayOfSpace[desk.space], let screen = screens.first(where: { $0.uuid == uuid }),
              screen != screens.first else { return area }
        return usable(visible: screen.visible, bounds: screen.bounds, insets: reserved(on: uuid))
    }

    /// The whole usable area of `desk`'s display, inside the outer gap.
    private func fullArea(of desk: Desk) -> CGRect {
        area(of: desk).insetBy(dx: options.gaps.outer, dy: options.gaps.outer)
    }

    /// The shown desk whose display holds `point` (the main one otherwise).
    public func desk(at point: CGPoint) -> Desk {
        let main = screens.first?.uuid
        for shown in otherShown {
            guard let uuid = displayOfSpace[shown.space], uuid != main,
                  let screen = screens.first(where: { $0.uuid == uuid }), screen.bounds.contains(point) else { continue }
            return shown
        }
        return desk
    }

    /// The usable area of the display a frame is mostly on.
    private func area(containing frame: CGRect?) -> CGRect {
        guard let frame else { return area }
        return area(of: desk(at: CGPoint(x: frame.midX, y: frame.midY)))
    }
    /// One layout per desktop. Only `space`'s windows are arranged; the others
    /// keep their tiles until their desktop is shown again.
    public private(set) var layouts = SpaceLayouts<Desk, CGWindowID>()
    /// The canvas strips, one per desktop. Which windows belong to a desktop
    /// is still kept in `layouts`; the strip only holds their order, their
    /// columns and where the viewport stands.
    public private(set) var strips: [Desk: Strip<CGWindowID>] = [:]

    public var isCanvas: Bool { options.layout == .canvas }

    /// The strip of a desk, made to match the desk's windows.
    private func strip(of desk: Desk) -> Strip<CGWindowID> {
        var strip = strips[desk] ?? Strip<CGWindowID>()
        strip.centerFocused = options.centerFocusedColumn
        let wanted = Set(layouts[desk].ids)
        for id in strip.ids where !wanted.contains(id) { strip.remove(id) }
        for id in layouts[desk].ids where !strip.contains(id) { strip.insert(id, width: options.columnWidth) }
        return strip
    }

    /// Reads, changes and stores a desk's strip.
    @discardableResult
    private func withStrip(_ desk: Desk, _ change: (inout Strip<CGWindowID>) -> Void) -> Strip<CGWindowID> {
        var strip = strip(of: desk)
        change(&strip)
        strip.scrollToFocused(area: area(of: desk), gaps: options.gaps)
        strips[desk] = strip
        return strip
    }
    /// The desktop and workspace currently shown on the main display.
    public private(set) var desk = Desk(space: 0, workspace: 1)
    public var space: SpaceID { desk.space }
    public var workspace: Int { desk.workspace }
    /// The workspace last shown on each macOS desktop.
    private var activeWorkspace: [SpaceID: Int] = [:]
    public private(set) var windows: [CGWindowID: AXWindow] = [:]
    public private(set) var dragging: CGWindowID?
    /// Window whose edge the user is dragging; it follows the mouse, the
    /// others follow it.
    public private(set) var resizing: CGWindowID?
    /// Sizes windows refused to go below or above, learned by measuring
    /// after each glide.
    public private(set) var minimums: [CGWindowID: CGSize] = [:]
    public private(set) var maximums: [CGWindowID: CGSize] = [:]

    /// Windows taken out of the layout; they keep their own frame on their desktop.
    public struct Floating: Sendable, Codable {
        public var desk: Desk
        public var frame: CGRect
    }
    public private(set) var floating: [CGWindowID: Floating] = [:]
    /// Last floating frame per window, so floating again returns there.
    private var lastFloatFrame: [CGWindowID: CGRect] = [:]
    /// Per desktop, the tiled window that currently fills the whole area.
    /// It keeps its tile underneath and returns there when toggled off.
    public private(set) var fullscreen: [Desk: CGWindowID] = [:]

    /// Windows of hidden workspaces wait just past the screen edge, a sliver
    /// left on screen (macOS keeps part of every window visible): lower
    /// workspaces to the left, higher ones to the right, so switching slides
    /// like Hyprland. Remembers each parked window's size and height.
    private var parked: [CGWindowID: CGRect] = [:]
    /// Where each window was before the engine first touched it.
    private var originalFrames: [CGWindowID: CGRect] = [:]

    /// When the shown desktop last changed. Windows ignore moves while macOS
    /// animates a desktop switch, so nothing is learned right after one.
    private var lastSpaceSwitch: CFTimeInterval = 0

    /// True for a moment after a desktop switch, while macOS still animates
    /// it and the new desktop's windows may not be on screen yet.
    public var isSwitchingSpace: Bool { CACurrentMediaTime() - lastSpaceSwitch < 1 }
    private var fitCheck: DispatchWorkItem?

    /// Layout of the shown desktop.
    public var tree: DwindleTree<CGWindowID> { layouts[desk] }

    /// Main-thread time per animation step (the apps work on their own threads).
    public private(set) var applyTimes = Durations()
    /// Time between animation steps (1 / achieved frame rate).
    public private(set) var stepIntervals = Durations()

    public var onSettled: (() -> Void)?
    public var log: (String) -> Void = { print($0) }

    private var springs: [CGWindowID: AnimatedRect] = [:]

    // Proxy glides (see ResizeAnimation.proxy).
    private let proxies = WindowProxies()
    /// Windows shown as a snapshot right now; the real one waits off screen.
    private var proxied: Set<CGWindowID> = []
    private var proxyFinish: DispatchWorkItem?
    /// Apps whose size changes took longer than a frame (median of recent
    /// ones). Only their windows glide as snapshots.
    public private(set) var slowApps: Set<pid_t> = []
    /// Slower than this per size change counts as slow: one frame at 120 Hz.
    public var slowResizeThreshold: Double = 0.008
    /// The size each proxied window was resized to off screen.
    private var preparedSize: [CGWindowID: CGSize] = [:]
    private var snapshotTimer: Timer?
    /// Drives the glide in step with the display (vsync), not a timer.
    private var ticker: DisplayTicker?
    /// One thread per app for Accessibility calls (see AppWorker).
    private var workers: [pid_t: AppWorker] = [:]
    private var lastStep: CFTimeInterval = 0
    /// Set while a coalesced relayout is waiting for this run-loop turn to
    /// end (see `relayout()`).
    private var relayoutScheduled = false

    public init(area: CGRect, options: Options = Options()) {
        self.screenArea = area
        self.options = options
        updateDisplays()
    }

    // MARK: Layout

    /// Takes over windows in their on-screen order. `space` is the desktop
    /// they live on (default: the shown one); windows on hidden desktops are
    /// arranged there right away, without animation.
    public func adopt(_ newWindows: [AXWindow], on space: SpaceID? = nil) {
        let target = deskShown(on: space)
        for window in newWindows where windows[window.windowID] == nil {
            let id = window.windowID
            let rule = ruleAction(for: window)
            if rule == .ignore {
                ignore(window)
                continue
            }
            windows[id] = window
            if originalFrames[id] == nil { originalFrames[id] = window.serverFrame }
            inspect(window)
            // Known from a saved layout: it keeps its old spot.
            if let home = desk(of: id) {
                dirtyDesks.insert(home)
                continue
            }
            if floatsByItself(window, on: target, rule: rule) { continue }
            layouts.assign(id, to: target) { $0.insert(id) }
        }
        dirtyDesks.insert(target)
        relayout()
        // Focus may have moved to one of them before they were managed.
        focusChanged()
    }

    /// The workspace shown on a desktop (always 1 while Apple's desktops
    /// are the workspaces).
    private func deskShown(on space: SpaceID?) -> Desk {
        guard let space, space != self.space else { return desk }
        return Desk(space: space, workspace: activeWorkspace[space] ?? 1)
    }

    /// Hidden desks whose layout changed; relayout() writes their frames.
    private var dirtyDesks: Set<Desk> = []

    /// Tiles a new window on the shown desktop. A point (usually the mouse)
    /// picks the tile to split, like a drop; otherwise the last tile is split.
    public func add(_ window: AXWindow, at point: CGPoint?, on space: SpaceID? = nil) {
        let id = window.windowID
        guard windows[id] == nil else { return }
        let rule = ruleAction(for: window)
        if rule == .ignore { return ignore(window) }
        windows[id] = window
        if originalFrames[id] == nil { originalFrames[id] = window.serverFrame }
        inspect(window)
        let target = deskShown(on: space)
        if let pending = pendingTab, pending.pid == window.pid, CACurrentMediaTime() - pending.since < 10,
           windows[pending.target] != nil, desk(of: id) == nil {
            pendingTab = nil
            join(id, with: pending.target)
            relayout()
            return
        }
        dirtyDesks.insert(desk(of: id) ?? target)
        if desk(of: id) != nil || floatsByItself(window, on: target, rule: rule) {
            relayout()
            return
        }
        let shown = isShown(target)
        let targetArea = area(of: target)
        layouts.assign(id, to: target) { tree in
            if let point, shown {
                tree.insert(id, at: point, in: targetArea, gaps: options.gaps, minimums: layoutMinimums, maximums: maximums)
            } else {
                tree.insert(id)
            }
        }
        relayout()
        // A new window usually takes focus before it is managed.
        focusChanged()
    }

    /// Drops a window from tiling; the others close the gap.
    public func remove(_ id: CGWindowID) {
        guard windows[id] != nil else { return }
        if dragging == id { dragging = nil }
        if focused == id { focused = nil }
        if scratchpad == id { scratchpad = nil }
        windows[id] = nil
        minimums[id] = nil
        maximums[id] = nil
        floating[id] = nil
        lastFloatFrame[id] = nil
        parked[id] = nil
        originalFrames[id] = nil
        proxied.remove(id)
        proxies.forget(id)
        fullscreen = fullscreen.filter { $0.value != id }
        if let home = desk(of: id) { dirtyDesks.insert(home) }
        leaveGroup(id)
        layouts.remove(id)
        relayout()
    }

    /// Dialogs, panels and windows that cannot be resized (or whose minimum
    /// and maximum size are the same) float where the app put them instead of
    /// taking a tile. Returns true when the window was made floating.
    private func floatsByItself(_ window: AXWindow, on target: Desk, rule: WindowRule.Action?) -> Bool {
        if rule == .float {
            makeFloating(window, reason: "rule", on: target)
            return true
        }
        guard window.subrole != kAXStandardWindowSubrole, rule != .tile else { return false }
        makeFloating(window, reason: window.subrole, on: target)
        return true
    }

    // MARK: Rules

    /// Rules from the config file; later ones win. Set them with apply(rules:).
    public private(set) var rules: [WindowRule] = []
    /// Windows a rule told the engine to leave alone.
    public private(set) var ignored: Set<CGWindowID> = []

    private func ruleAction(for window: AXWindow) -> WindowRule.Action? {
        guard !rules.isEmpty else { return nil }
        let app = NSRunningApplication(processIdentifier: window.pid)
        return rules.action(bundleID: app?.bundleIdentifier, appName: app?.localizedName, title: window.title)
    }

    private func ignore(_ window: AXWindow) {
        guard ignored.insert(window.windowID).inserted else { return }
        log("ignored by a rule: \(window.title)")
    }

    /// New rules: managed windows they now ignore are let go (they stay
    /// where they are), tiled ones they now float leave the layout, and
    /// windows no longer ignored are picked up by the next scan.
    public func apply(rules newRules: [WindowRule]) {
        guard newRules != rules else { return }
        rules = newRules
        ignored.removeAll()
        for (id, window) in windows {
            switch ruleAction(for: window) {
            case .ignore:
                remove(id)
                ignore(window)
            case .float where floating[id] == nil:
                guard let home = desk(of: id) else { continue }
                dirtyDesks.insert(home)
                leaveGroup(id)
                layouts.remove(id)
                fullscreen = fullscreen.filter { $0.value != id }
                makeFloating(window, reason: "rule", on: home)
            default:
                break
            }
        }
        relayout()
    }

    /// Forgets ignored windows that are gone.
    public func pruneIgnored(keeping alive: Set<CGWindowID>) {
        ignored.formIntersection(alive)
    }

    /// Floats `window` where it is, kept inside the usable area.
    private func makeFloating(_ window: AXWindow, reason: String, on target: Desk) {
        let id = window.windowID
        let area = area(of: target)
        var frame = window.serverFrame ?? defaultFloatFrame(for: id, on: target)
        frame.origin.x = min(max(frame.minX, area.minX), max(area.maxX - frame.width, area.minX))
        frame.origin.y = min(max(frame.minY, area.minY), max(area.maxY - frame.height, area.minY))
        layouts.remove(id)
        floating[id] = Floating(desk: target, frame: frame)
        log("floats by itself (\(reason)): \(window.title)")
    }

    /// Asks a new window for its size limits and whether it can be resized,
    /// on its app's thread (these are round trips into the app). A window
    /// that cannot be resized, or whose minimum and maximum are the same,
    /// then leaves the layout and floats.
    private func inspect(_ window: AXWindow) {
        let largest = area(containing: window.serverFrame).insetBy(dx: options.gaps.outer, dy: options.gaps.outer)
        worker(for: window.pid).run { [weak self] in
            let limits = window.measureLimits(largest: largest)
            let resizable = window.isResizable
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.applyInspection(window, limits: limits, resizable: resizable) }
            }
        }
    }

    private func applyInspection(_ window: AXWindow, limits: (minimum: CGSize, maximum: CGSize)?, resizable: Bool) {
        let id = window.windowID
        guard windows[id] != nil else { return }
        let name = window.title.isEmpty ? "\(id)" : window.title
        if let limits {
            minimums[id] = limits.minimum == .zero ? nil : limits.minimum
            maximums[id] = limits.maximum == .infinite ? nil : limits.maximum
            log("limits for \(name): min \(Self.describe(limits.minimum)) max \(Self.describe(limits.maximum)) (asked)")
        } else {
            log("limits for \(name): app did not answer, learning later")
        }
        let fixed = limits.map {
            abs($0.minimum.width - $0.maximum.width) < 2 && abs($0.minimum.height - $0.maximum.height) < 2
        } ?? false
        if (!resizable || fixed), floating[id] == nil, let home = layouts.space(of: id) {
            layouts.remove(id)
            makeFloating(window, reason: resizable ? "fixed size" : "not resizable", on: home)
            dirtyDesks.insert(home)
        } else if let home = layouts.space(of: id), group(of: id) == nil,
                  !layouts[home].fits(in: area(of: home), gaps: options.gaps, minimums: layoutMinimums),
                  let sibling = layouts[home].sibling(of: id) {
            // Not enough room next to its neighbor: share its tile as a tab
            // instead of overlapping.
            layouts.remove(id)
            join(id, with: sibling)
            dirtyDesks.insert(home)
        }
        relayout()
    }

    /// The window now lives on another desktop (the user moved it there).
    public func move(_ id: CGWindowID, to targetSpace: SpaceID) {
        if id == scratchpad, scratchpadHidden { return }
        // A tab that was carried to another desktop leaves its group: its
        // fellows stay where they are, and it would otherwise be a group
        // member and a tile at the same time.
        if group(of: id) != nil {
            leaveGroup(id)
            if let home = desk(of: id) { dirtyDesks.insert(home) }
        }
        let target = Desk(space: targetSpace, workspace: activeWorkspace[targetSpace] ?? 1)
        if var state = floating[id] {
            guard state.desk.space != targetSpace else { return }
            state.desk = target
            floating[id] = state
            return
        }
        guard windows[id] != nil, id != dragging, layouts.space(of: id)?.space != targetSpace else { return }
        fullscreen = fullscreen.filter { $0.value != id }
        log("\(windows[id]?.title ?? "\(id)") moved to desktop \(targetSpace)")
        if let old = layouts.space(of: id) { dirtyDesks.insert(old) }
        dirtyDesks.insert(target)
        layouts.assign(id, to: target) { $0.insert(id) }
        relayout()
    }

    /// The desktops in Mission Control order, as last seen.
    public private(set) var knownSpaceOrder: [SpaceID] = []

    public func noteSpaceOrder(_ order: [SpaceID]) {
        if !order.isEmpty { knownSpaceOrder = order }
    }

    /// A desktop was closed in Mission Control and macOS moved its windows
    /// onto `target`. They keep their arrangement and land on our workspace
    /// numbered after the closed desktop's place (third desktop: workspace 3).
    public func absorbVanishedSpace(_ vanished: SpaceID, into target: SpaceID) {
        let place = (knownSpaceOrder.firstIndex(of: vanished) ?? 0) + 1
        let desks = Set(layouts.spaceOf.values.filter { $0.space == vanished })
            .union(floating.values.map(\.desk).filter { $0.space == vanished })
        for old in desks.sorted(by: { $0.workspace < $1.workspace }) {
            let new = Desk(space: target, workspace: min(9, place + old.workspace - 1))
            log("desktop \(vanished) closed: its workspace \(old.workspace) becomes workspace \(new.workspace)")
            layouts.move(old, to: new)
            dirtyDesks.insert(new)
            for (id, state) in floating where state.desk == old { floating[id]?.desk = new }
            if let id = fullscreen.removeValue(forKey: old) { fullscreen[new] = id }
        }
        relayout()
    }

    /// The user switched desktops: arrange the windows shown there.
    public func switchSpace(to target: SpaceID) {
        guard target != space else { return }
        log("desktop \(space) -> \(target)")
        desk = Desk(space: target, workspace: activeWorkspace[target] ?? 1)
        lastSpaceSwitch = CACurrentMediaTime()
        // A drag cannot survive a desktop switch; the window comes along and
        // stays where it is: tiled on the new desktop, or floating there.
        if let id = dragging {
            dragging = nil
            if var state = floating[id] {
                state.desk = desk
                if let frame = windows[id]?.serverFrame { state.frame = frame }
                floating[id] = state
            } else {
                layouts.assign(id, to: desk) { $0.insert(id) }
            }
        }
        relayout()
    }

    public var isAnimating: Bool { ticker != nil }

    /// The worker thread for an app, created on first use.
    private func worker(for pid: pid_t) -> AppWorker {
        if let worker = workers[pid] { return worker }
        let worker = AppWorker(pid: pid) { [weak self] id in self?.forget(id) }
        workers[pid] = worker
        return worker
    }

    /// Sets a window's frame on its app's thread, never blocking the main
    /// thread. Latest wins while the app is busy. `completion` runs once set.
    public func write(_ id: CGWindowID, _ frame: CGRect,
                      completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let window = windows[id] else { return }
        worker(for: window.pid).setFrame(window, frame, completion: completion)
    }

    /// Raises a window on its app's thread.
    public func raise(_ id: CGWindowID, then: (@MainActor @Sendable () -> Void)? = nil) {
        guard let window = windows[id] else { return }
        worker(for: window.pid).run {
            window.raise()
            if let then { DispatchQueue.main.async { MainActor.assumeIsolated { then() } } }
        }
    }

    /// An app quit: its thread is not needed any more.
    public func forgetApp(_ pid: pid_t) {
        workers[pid] = nil
        slowApps.remove(pid)
    }

    /// Frames skipped because an app was still busy with an older one.
    public var droppedFrames: Int { workers.values.reduce(0) { $0 + $1.droppedFrames } }

    /// The desk a window belongs to, tiled, grouped or floating.
    public func desk(of id: CGWindowID) -> Desk? {
        if let desk = layouts.space(of: id) ?? floating[id]?.desk { return desk }
        return groups.first { $0.contains(id) }.flatMap { layouts.space(of: $0.active) }
    }

    // MARK: Titles and focus

    /// A window's title changed: read it again on its app's thread and
    /// update its group's tab bar.
    public func refreshTitle(of id: CGWindowID) {
        guard let window = windows[id] else { return }
        worker(for: window.pid).run { [weak self] in
            guard window.refreshTitle() else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.publishTabBars() } }
        }
    }

    /// The managed window with keyboard focus, as last seen.
    public private(set) var focused: CGWindowID?

    /// Where the focused window is on screen and whether it is shown, for
    /// the host's border around it.
    public struct ActiveWindow: Sendable, Equatable {
        public let windowID: CGWindowID
        /// Top-left coordinates. A tab group's includes its tab bar.
        public let frame: CGRect
    }

    /// Called when the focused window changes or moves; nil hides the border.
    public var onActiveWindowChanged: ((ActiveWindow?) -> Void)?
    private var publishedActive: ActiveWindow?

    /// Something may have taken focus (an app came forward, an app focused
    /// another window). Asking which window has it is a round trip into the
    /// focused app, so it runs off the main thread.
    public func focusChanged() {
        focusGeneration &+= 1
        let generation = focusGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let id = WindowDiscovery.focusedWindowID()
            await MainActor.run { self?.noteFocused(id, generation: generation) }
        }
    }

    /// Counts focus changes, so a slow answer to an older question (two
    /// notifications for one change, a focus set by keys meanwhile) never
    /// overwrites a newer state.
    private var focusGeneration: UInt64 = 0

    /// When the engine last focused a window on purpose (keys, a tab click).
    /// Focus follows mouse stops insisting on its window after that.
    public private(set) var lastDirectedFocus: CFTimeInterval = 0

    private func noteFocused(_ id: CGWindowID?, generation: UInt64) {
        guard generation == focusGeneration else { return }
        let managed = id.flatMap { windows[$0] != nil ? $0 : nil }
        guard managed != focused else { return }
        focused = managed
        publishActive()
    }

    /// The focused window's frame, following it mid-glide. Nil while it is
    /// dragged or resized by hand (macOS moves it then), or not shown.
    public func activeWindow() -> ActiveWindow? {
        guard let id = focused, id != dragging, id != resizing else { return nil }
        guard var frame = springs[id]?.current ?? targetFrames()[id], parked[id] == nil else { return nil }
        // At rest, the window's real frame: apps that snap to character
        // cells (kitty) stay a little smaller than their tile, and the
        // border should hug the window, not the tile. Mid-glide the spring
        // is exact enough and saves a window-server query per frame.
        if !isAnimating, let actual = windows[id]?.serverFrame,
           abs(actual.minX - frame.minX) < 40, abs(actual.minY - frame.minY) < 40,
           abs(actual.width - frame.width) < 40, abs(actual.height - frame.height) < 40 {
            frame = actual
        }
        if let group = group(of: id), let home = layouts.space(of: group.active), isShown(home) {
            frame = CGRect(x: frame.minX, y: frame.minY - options.tabBarHeight,
                           width: frame.width, height: frame.height + options.tabBarHeight)
        } else if let home = desk(of: id), !isShown(home) {
            return nil
        }
        return ActiveWindow(windowID: id, frame: frame)
    }

    private func publishActive() {
        let active = activeWindow()
        guard active != publishedActive else { return }
        publishedActive = active
        onActiveWindowChanged?(active)
    }

    // MARK: Tab groups

    /// Windows sharing a tile as tabs. Only each group's active window is in
    /// the layout tree; the others lie exactly behind it.
    public private(set) var groups: [TabGroup<CGWindowID>] = []

    public func group(of id: CGWindowID) -> TabGroup<CGWindowID>? {
        groups.first { $0.contains(id) }
    }

    /// Minimums as the layout sees them: a group needs the largest of its
    /// windows' minimums, plus room for its tab bar.
    private var layoutMinimums: [CGWindowID: CGSize] {
        guard !groups.isEmpty else { return minimums }
        var result = minimums
        for group in groups {
            var size = CGSize.zero
            for member in group.members {
                guard let minimum = minimums[member] else { continue }
                size.width = max(size.width, minimum.width)
                size.height = max(size.height, minimum.height)
            }
            size.height += options.tabBarHeight
            result[group.active] = size
        }
        return result
    }

    /// One tab of a group, as the host shows it.
    public struct Tab: Sendable, Equatable {
        public let windowID: CGWindowID
        public let title: String
        public let pid: pid_t
    }

    /// Where a group's tab bar goes (top-left coordinates) and what it shows.
    public struct TabBar: Sendable, Equatable {
        public let frame: CGRect
        public let tabs: [Tab]
        public let active: CGWindowID
    }

    /// Called whenever tab bars appear, move or change; the host draws them.
    public var onTabBarsChanged: (([TabBar]) -> Void)?
    private var publishedBars: [TabBar] = []

    /// The tab bars of the shown desktop, following their windows mid-glide.
    public func tabBars() -> [TabBar] {
        groups.compactMap { group in
            guard let home = layouts.space(of: group.active), isShown(home), dragging != group.active,
                  let frame = springs[group.active]?.current ?? targetFrames()[group.active] else { return nil }
            let tabs = group.members.compactMap { id in
                windows[id].map { Tab(windowID: id, title: $0.title, pid: $0.pid) }
            }
            return TabBar(frame: CGRect(x: frame.minX, y: frame.minY - options.tabBarHeight,
                                        width: frame.width, height: options.tabBarHeight),
                          tabs: tabs, active: group.active)
        }
    }

    private func publishTabBars() {
        let bars = tabBars()
        guard bars != publishedBars else { return }
        publishedBars = bars
        onTabBarsChanged?(bars)
    }

    /// Adds `id` (not in any tree) to `target`'s group, or makes a new group
    /// of the two, and shows `id` in the shared tile.
    private func join(_ id: CGWindowID, with target: CGWindowID) {
        if let index = groups.firstIndex(where: { $0.contains(target) }) {
            let shown = groups[index].active
            groups[index].add(id)
            layouts.replace(shown, with: id)
        } else {
            groups.append(TabGroup(target, id))
            layouts.replace(target, with: id)
        }
        log("tab group: \(windows[id]?.title ?? "\(id)") joins \(windows[target]?.title ?? "\(target)")")
        raise(id)
    }

    /// Takes `id` out of its group. If it was the shown tab, the next one
    /// takes over the tile; a group down to one window ends. Afterwards `id`
    /// is in no tree. Returns whether it was grouped.
    @discardableResult
    private func leaveGroup(_ id: CGWindowID) -> Bool {
        guard let index = groups.firstIndex(where: { $0.contains(id) }) else { return false }
        var group = groups[index]
        let wasShown = group.active == id
        let next = group.remove(id)
        if wasShown, let heir = next ?? group.members.first {
            layouts.replace(id, with: heir)
            raise(heir)
        }
        if next == nil { groups.remove(at: index) } else { groups[index] = group }
        return true
    }

    /// Shows another tab of a group.
    public func activateTab(_ id: CGWindowID) {
        guard let index = groups.firstIndex(where: { $0.contains(id) }) else { return }
        let shown = groups[index].active
        guard shown != id else { return focus(id) }
        layouts.replace(shown, with: id)
        groups[index].activate(id)
        focus(id)
        relayout()
    }

    /// Moves a tab one place along its bar.
    public func moveTab(_ id: CGWindowID, forward: Bool) {
        guard let index = groups.firstIndex(where: { $0.contains(id) }) else { return }
        guard groups[index].move(id, forward: forward) else { return }
        publishTabBars()
    }

    /// Puts a tab where it was dragged to on the bar.
    public func moveTab(_ id: CGWindowID, to place: Int) {
        guard let index = groups.firstIndex(where: { $0.contains(id) }) else { return }
        groups[index].move(id, to: place)
        publishTabBars()
    }

    /// Every window of one app on this desktop into a single group, so an
    /// app's windows sit in one tile as tabs.
    public func groupApp(of id: CGWindowID) {
        guard let window = windows[id], let home = desk(of: id) else { return }
        let mates = windows.values
            .filter { $0.pid == window.pid && $0.windowID != id && desk(of: $0.windowID) == home
                      && floating[$0.windowID] == nil && scratchpad != $0.windowID }
            .map(\.windowID)
        guard !mates.isEmpty else {
            log("group app: \(window.title) is the only window of its app here")
            return
        }
        for mate in mates {
            guard group(of: mate)?.contains(id) != true else { continue }
            leaveGroup(mate)
            layouts.remove(mate)
            strips[home]?.remove(mate)
            join(mate, with: id)
        }
        log("grouped \(mates.count + 1) windows of \(window.title)")
        relayout()
    }

    /// The next or previous tab of the group holding `id`.
    public func cycleTab(from id: CGWindowID, forward: Bool) {
        guard let group = group(of: id), let next = group.neighbor(of: group.active, forward: forward) else { return }
        activateTab(next)
    }

    /// Super+G: a grouped window leaves its group and gets its own tile next
    /// to it; a tiled one joins the window it was split from.
    public func toggleGroup(_ id: CGWindowID) {
        if isCanvas, let home = layouts.space(of: id) {
            // On the strip a "group" is a column: the window joins the
            // column to its left, or leaves its own again.
            withStrip(home) { strip in
                guard let index = strip.column(of: id) else { return }
                if strip.columns[index].windows.count > 1 {
                    strip.expel(id)
                } else if index > 0 {
                    let target = strip.columns[index - 1].active
                    strip.remove(id)
                    strip.stack(id, intoColumnOf: target)
                }
            }
            relayout()
            return
        }
        if let group = group(of: id), let home = desk(of: id) {
            leaveGroup(id)
            let beside = group.members.first { $0 != id && layouts.space(of: $0) != nil }
            layouts.assign(id, to: home) { $0.insert(id, splitting: beside) }
        } else if let home = layouts.space(of: id), let sibling = layouts[home].sibling(of: id) {
            if fullscreen[home] == id { fullscreen[home] = nil }
            layouts.remove(id)
            join(id, with: sibling)
        }
        relayout()
    }

    /// The next new window of `pid` joins `id`'s group (the tab bar's + button).
    public func routeNextWindow(of pid: pid_t, intoGroupWith id: CGWindowID) {
        pendingTab = (pid, id, CACurrentMediaTime())
    }
    private var pendingTab: (pid: pid_t, target: CGWindowID, since: CFTimeInterval)?

    /// Recomputes the layout and lets every window glide to its new tile.
    /// Windows not on the shown desktop are left alone.
    ///
    /// Several state changes in one run-loop turn (e.g. reconcile() moving
    /// or dropping a handful of windows, or a fast edge-resize drag posting
    /// many mouse-dragged events between display frames) each call this; all
    /// but the first only mark it dirty and return, so the actual layout and
    /// spring retargeting run once with the final state, not once per call.
    /// Springs only consume their target on the next display tick anyway, so
    /// nothing is lost by waiting for the turn to end.
    public func relayout() {
        guard !relayoutScheduled else { return }
        relayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.relayoutScheduled = false
            self.performRelayout()
        }
    }

    private func performRelayout() {
        if isCanvas { syncStrips() }
        for shown in shownDesks { layouts[shown].freezeDirections(in: area(of: shown), gaps: options.gaps) }
        arrangeHiddenDesks()
        let frames = targetFrames()
        let held = [dragging, resizing]
        // Windows of a restored layout that were not seen yet (their desktop
        // was never shown) get no spring: a spring made up at the target
        // would never move the real window there.
        for id in springs.keys where frames[id] == nil || held.contains(id) || windows[id] == nil {
            springs[id] = nil
        }
        for (id, rect) in frames where !held.contains(id) && windows[id] != nil {
            springs[id, default: AnimatedRect(windows[id]?.serverFrame ?? rect)].target = rect
        }
        if resizing != nil {
            // An edge under the mouse: neighbors follow it at once, like
            // Hyprland, instead of gliding after it.
            for (id, rect) in frames where !held.contains(id) && windows[id] != nil {
                springs[id] = AnimatedRect(rect)
                write(id, rect)
            }
            publishTabBars()
            publishActive()
            return
        }
        startProxies()
        startLoop()
        publishTabBars()
        publishActive()
    }

    /// Reverses the window order. Used by the probe to force big moves.
    public func mirror() {
        let ids = tree.ids
        for id in ids { layouts.remove(id) }
        for id in ids.reversed() { layouts.assign(id, to: desk) { $0.insert(id) } }
        relayout()
    }

    /// The managed window under `point`: floating windows first (they sit
    /// on top), then a fullscreen one, then the tiles.
    public func window(at point: CGPoint) -> CGWindowID? {
        if let id = floating.first(where: { isShown($0.value.desk) && $0.value.frame.contains(point) })?.key {
            return id
        }
        let here = desk(at: point)
        if let id = fullscreen[here], layouts[here].contains(id) { return id }
        return layouts[here].id(at: point, in: area(of: here), gaps: options.gaps,
                                minimums: layoutMinimums, maximums: maximums)
    }

    /// The whole usable area of the main display, inside the outer gap.
    private var fullArea: CGRect { fullArea(of: desk) }

    /// Where the engine last put the window (nil while dragged or unknown).
    public func expectedFrame(of id: CGWindowID) -> CGRect? {
        springs[id]?.current
    }

    /// Where every window on the shown desktop should be: tiles, then a
    /// fullscreen window over its tile, then floating windows.
    public func targetFrames() -> [CGWindowID: CGRect] {
        var frames: [CGWindowID: CGRect] = [:]
        for shown in shownDesks { frames.merge(self.frames(on: shown)) { first, _ in first } }
        // Windows of this desktop's other workspaces go (or stay) aside.
        var aside: [CGWindowID: Int] = [:]
        for (id, home) in layouts.spaceOf where home.space == space && home.workspace != workspace {
            aside[id] = home.workspace
        }
        for (id, state) in floating where state.desk.space == space && state.desk.workspace != workspace {
            aside[id] = state.desk.workspace
        }
        for (id, home) in aside where id != dragging {
            var frame = parked[id] ?? springs[id]?.current ?? windows[id]?.serverFrame ?? fullArea
            frame.origin.x = home < workspace ? screenArea.minX - frame.width + 1 : screenArea.maxX - 1
            parked[id] = frame
            frames[id] = frame
        }
        parked = parked.filter { aside[$0.key] != nil }
        return frames
    }

    // MARK: Saving the layout

    /// Everything needed to bring the arrangement back after a restart.
    /// Window numbers stay the same as long as their apps keep running.
    public struct Snapshot: Codable, Sendable {
        public var layouts: SpaceLayouts<Desk, CGWindowID>
        public var floating: [CGWindowID: Floating]
        public var activeWorkspace: [SpaceID: Int]
        public var originalFrames: [CGWindowID: CGRect]
        /// Missing in layouts saved before tab groups existed.
        public var groups: [TabGroup<CGWindowID>]?
    }

    public func snapshot() -> Snapshot {
        Snapshot(layouts: layouts, floating: floating,
                 activeWorkspace: activeWorkspace, originalFrames: originalFrames, groups: groups)
    }

    /// Loads a saved arrangement before windows are adopted. Windows that no
    /// longer exist (`alive` rejects them) are dropped; the rest return to
    /// their old tiles when they are adopted.
    public func restore(_ snapshot: Snapshot, alive: (CGWindowID) -> Bool) {
        var saved = snapshot.layouts
        let floats = snapshot.floating.filter { alive($0.key) }
        // A window is tiled or floating, never both (an older version could
        // save both after a floating window was carried to another desktop).
        saved.retain { alive($0) && floats[$0] == nil }
        layouts = saved
        floating = floats
        activeWorkspace = snapshot.activeWorkspace
        originalFrames = snapshot.originalFrames.filter { alive($0.key) }
        groups = (snapshot.groups ?? []).filter { group in
            group.members.allSatisfy(alive) && layouts.space(of: group.active) != nil
        }
        desk.workspace = activeWorkspace[space] ?? 1
        log("restored layout: \(layouts.spaceOf.count) tiled, \(floating.count) floating")
    }

    /// Hidden desktops change too (a window closed there, a new one opened):
    /// their windows are put straight into place, nobody sees a glide.
    private func arrangeHiddenDesks() {
        let shownSpaces = Set(shownDesks.map(\.space))
        for hidden in dirtyDesks where !isShown(hidden) && !shownSpaces.contains(hidden.space) {
            layouts[hidden].freezeDirections(in: area(of: hidden), gaps: options.gaps)
            for (id, frame) in frames(on: hidden) where windows[id] != nil { write(id, frame) }
        }
        dirtyDesks.removeAll()
    }

    /// Where the windows of `desk` go when it is shown: tiles, a fullscreen
    /// window over its tile, floating windows.
    public func frames(on desk: Desk) -> [CGWindowID: CGRect] {
        var frames = isCanvas
            ? canvasFrames(on: desk)
            : layouts[desk].layout(in: area(of: desk), gaps: options.gaps,
                                   minimums: layoutMinimums, maximums: maximums)
        if let id = fullscreen[desk], frames[id] != nil {
            frames[id] = DwindleTree<CGWindowID>.centered(fullArea(of: desk), maximum: maximums[id])
        }
        for (id, state) in floating where state.desk == desk {
            frames[id] = state.frame
        }
        // A group's windows share its tile below the tab bar.
        for group in groups {
            guard let tile = frames[group.active] else { continue }
            let below = CGRect(x: tile.minX, y: tile.minY + options.tabBarHeight,
                               width: tile.width, height: max(tile.height - options.tabBarHeight, 1))
            for member in group.members where windows[member] != nil { frames[member] = below }
        }
        return frames
    }

    // MARK: Displays: focus and moving between them

    /// The desks on screen, in the order the displays stand (main first).
    private func shownDesk(onDisplay index: Int) -> Desk? {
        guard screens.indices.contains(index) else { return nil }
        let uuid = screens[index].uuid
        return shownDesks.first { displayOfSpace[$0.space] == uuid }
            ?? (index == 0 ? desk : nil)
    }

    /// The desks on screen that belong to one display.
    public func desks(onDisplay uuid: String) -> [Desk] {
        shownDesks.filter { displayOfSpace[$0.space] == uuid }
    }

    private func displayIndex(of desk: Desk) -> Int? {
        guard let uuid = displayOfSpace[desk.space] else { return nil }
        return screens.firstIndex { $0.uuid == uuid }
    }

    /// Focus goes to the next or previous display, onto the window that was
    /// focused there last, or the first one.
    public func focusDisplay(next: Bool) {
        guard screens.count > 1 else { return }
        let here = focused.flatMap { desk(of: $0) }.flatMap { displayIndex(of: $0) } ?? 0
        let there = (here + (next ? 1 : -1) + screens.count) % screens.count
        guard let target = shownDesk(onDisplay: there) else { return }
        let candidates = layouts[target].ids + floating.filter { $0.value.desk == target }.map(\.key)
        guard let id = lastFocusedOnDesk[target].flatMap({ candidates.contains($0) ? $0 : nil })
                ?? candidates.first else { return }
        focus(id)
    }

    /// The focused window goes to the next or previous display: it is put
    /// into the layout there, and macOS counts it to that display once its
    /// frame lies on it.
    public func sendToDisplay(_ id: CGWindowID, next: Bool) {
        guard screens.count > 1, let home = desk(of: id) else { return }
        let here = displayIndex(of: home) ?? 0
        let there = (here + (next ? 1 : -1) + screens.count) % screens.count
        guard there != here, let target = shownDesk(onDisplay: there) else { return }
        if var state = floating[id] {
            let area = area(of: target)
            state.desk = target
            state.frame = CGRect(x: area.midX - state.frame.width / 2,
                                 y: area.midY - state.frame.height / 2,
                                 width: state.frame.width, height: state.frame.height)
            floating[id] = state
        } else {
            leaveGroup(id)
            if fullscreen[home] == id { fullscreen[home] = nil }
            layouts.remove(id)
            strips[home]?.remove(id)
            layouts.assign(id, to: target) { $0.insert(id) }
        }
        dirtyDesks.insert(home)
        dirtyDesks.insert(target)
        log("\(windows[id]?.title ?? "\(id)") -> display \(there + 1)")
        relayout()
        focus(id)
    }

    /// The window focused last on each desk, so coming back to a display
    /// lands where one left off.
    private var lastFocusedOnDesk: [Desk: CGWindowID] = [:]

    // MARK: Canvas

    /// Where the strip's windows go. Columns that the screen does not show
    /// wait just past its edge: macOS keeps a sliver of every window on
    /// screen, and a window sent far away would be lost there.
    private func canvasFrames(on desk: Desk) -> [CGWindowID: CGRect] {
        let area = area(of: desk)
        var frames = strip(of: desk).layout(in: area, gaps: options.gaps, minimums: layoutMinimums)
        for (id, frame) in frames {
            if frame.maxX < area.minX {
                frames[id] = CGRect(origin: CGPoint(x: area.minX - frame.width + 1, y: frame.minY), size: frame.size)
            } else if frame.minX > area.maxX {
                frames[id] = CGRect(origin: CGPoint(x: area.maxX - 1, y: frame.minY), size: frame.size)
            }
        }
        return frames
    }

    /// The strip follows the focused window, and the viewport follows the
    /// focused column - but only when the focus really changed, so a scroll
    /// by hand is not undone by the next layout.
    private func syncStrips() {
        for shown in shownDesks {
            var strip = strip(of: shown)
            if let id = focused, strip.contains(id) { strip.focus(id) }
            if let onTop = strip.focused, lastScrolledTo[shown] != onTop {
                strip.scrollToFocused(area: area(of: shown), gaps: options.gaps)
                lastScrolledTo[shown] = onTop
            }
            strips[shown] = strip
        }
    }

    /// The column the viewport was moved to last, per desk.
    private var lastScrolledTo: [Desk: CGWindowID] = [:]

    /// Scrolls the strip of the shown desktop by `delta` points.
    public func pan(by delta: CGFloat) {
        guard isCanvas else { return }
        var strip = strip(of: desk)
        strip.scroll(by: delta, area: area(of: desk), gaps: options.gaps)
        strips[desk] = strip
        relayout()
    }

    /// Brings the focused column into view (after a focus change by keys).
    public func scrollToFocused() {
        guard isCanvas else { return }
        withStrip(desk) { _ in }
        relayout()
    }

    /// The window left, right, above or below on the strip.
    private func canvasNeighbor(of id: CGWindowID, _ direction: Direction) -> CGWindowID? {
        guard let home = layouts.space(of: id) else { return nil }
        var strip = strip(of: home)
        strip.focus(id)
        return switch direction {
        case .left: strip.focusColumn(next: false)
        case .right: strip.focusColumn(next: true)
        case .up: strip.focusInColumn(next: false)
        case .down: strip.focusInColumn(next: true)
        }
    }

    /// Super + H J K L on the strip: a column moves along it, a stacked
    /// window moves inside its column.
    private func canvasMove(_ id: CGWindowID, _ direction: Direction) {
        guard let home = layouts.space(of: id) else { return }
        withStrip(home) { strip in
            strip.focus(id)
            switch direction {
            case .left: strip.moveColumn(next: false)
            case .right: strip.moveColumn(next: true)
            case .up, .down: strip.moveInColumn(id, next: direction == .down)
            }
        }
        relayout()
    }

    // MARK: Workspaces

    /// Shows workspace `number` (1-9) of the current desktop. Its windows
    /// slide in, the others slide out to the side they belong to. A window
    /// held with the mouse comes along and lands where it is dropped.
    public func switchWorkspace(to number: Int) {
        guard (1...9).contains(number), number != workspace else { return }
        log("workspace \(workspace) -> \(number)")
        activeWorkspace[space] = number
        desk.workspace = number
        relayout()
    }

    /// Sends a window to another workspace of the current desktop.
    public func moveWindow(_ id: CGWindowID, toWorkspace number: Int) {
        guard (1...9).contains(number), number != workspace, windows[id] != nil, id != dragging else { return }
        let target = Desk(space: space, workspace: number)
        if var state = floating[id] {
            state.desk = target
            floating[id] = state
        } else if tree.contains(id) {
            if fullscreen[desk] == id { fullscreen[desk] = nil }
            layouts.remove(id)
            layouts.assign(id, to: target) { $0.insert(id) }
        }
        log("\(windows[id]?.title ?? "\(id)") -> workspace \(number)")
        relayout()
    }

    /// Lets go of every window where it belongs now: a glide in progress
    /// jumps to its end, snapshot stand-ins go away and their real windows
    /// (waiting off screen) take their tiles. Nothing goes back to where it
    /// was before; for that there is restoreAll().
    public func releaseAll() {
        ticker?.stop()
        ticker = nil
        proxyFinish?.cancel()
        let targets = targetFrames()
        for (id, window) in windows {
            let target: CGRect?
            if parked[id] != nil, let home = desk(of: id) {
                // Waiting past the edge for another workspace: onto the screen,
                // or it would be lost there once nobody manages it.
                target = frames(on: home)[id]
            } else if proxied.contains(id) || !(springs[id]?.isSettled ?? true) {
                target = targets[id]
            } else {
                target = nil
            }
            guard let target else { continue }
            window.invalidateCache()
            window.setFrame(target)
        }
        proxied.removeAll()
        proxies.removeAll()
    }

    /// Puts every managed window back where it was before the engine first
    /// touched it (or, for parked ones without a record, onto the screen).
    public func restoreAll() {
        ticker?.stop()
        ticker = nil
        proxyFinish?.cancel()
        proxied.removeAll()
        proxies.removeAll()
        for (id, window) in windows {
            window.invalidateCache()
            if let frame = originalFrames[id] {
                window.setFrame(frame)
            } else if let frame = parked[id] {
                window.setFrame(CGRect(origin: CGPoint(x: area.midX - frame.width / 2, y: frame.minY), size: frame.size))
            }
        }
    }

    // MARK: Keyboard

    /// Raises and focuses a window (its app comes forward with only it).
    public func focus(_ id: CGWindowID) {
        guard let window = windows[id] else { return }
        worker(for: window.pid).run { WindowFocus.focus(window) }
        focusGeneration &+= 1
        lastDirectedFocus = CACurrentMediaTime()
        focused = id
        if let home = desk(of: id) { lastFocusedOnDesk[home] = id }
        publishActive()
        // On the strip the viewport follows the focus.
        if isCanvas { relayout() }
    }

    /// The managed window next to `id` on screen in `direction`, on the
    /// shown desktop (tiles and floating windows).
    public func neighbor(of id: CGWindowID, _ direction: Direction) -> CGWindowID? {
        if isCanvas, floating[id] == nil, layouts.space(of: id) != nil {
            return canvasNeighbor(of: id, direction)
        }
        var frames: [CGWindowID: CGRect] = [:]
        for shown in shownDesks { frames.merge(self.frames(on: shown)) { first, _ in first } }
        return Neighbors.neighbor(of: id, direction, in: frames.filter { windows[$0.key] != nil })
    }

    /// Focus the next window in reading order (tiles, then floating ones).
    public func cycleFocus(from id: CGWindowID?) {
        let home = id.flatMap { desk(of: $0) }.flatMap { isShown($0) ? $0 : nil } ?? desk
        let order = layouts[home].ids + floating.filter { $0.value.desk == home }.map(\.key).sorted()
        guard !order.isEmpty else { return }
        let next = id.flatMap { order.firstIndex(of: $0) }.map { (order.index(after: $0)) % order.count } ?? 0
        focus(order[next])
    }

    /// Swaps a tiled window with its tiled neighbor in `direction`.
    public func swap(_ id: CGWindowID, _ direction: Direction) {
        guard let home = layouts.space(of: id) else { return }
        if isCanvas { return canvasMove(id, direction) }
        let tiles = layouts[home].layout(in: area(of: home), gaps: options.gaps, minimums: layoutMinimums, maximums: maximums)
        guard let other = Neighbors.neighbor(of: id, direction, in: tiles) else { return }
        log("swap \(windows[id]?.title ?? "\(id)") with \(windows[other]?.title ?? "\(other)")")
        layouts[home].swap(id, other)
        relayout()
    }

    /// Turns the split that holds `id` (side by side ↔ stacked).
    public func toggleSplit(of id: CGWindowID) {
        guard let home = layouts.space(of: id) else { return }
        if isCanvas {
            // No splits on the strip: the key centers the focused column instead.
            options.centerFocusedColumn.toggle()
            log("focused column centered: \(options.centerFocusedColumn)")
            withStrip(home) { strip in strip.focus(id) }
            relayout()
            return
        }
        layouts[home].toggleSplit(of: id)
        relayout()
    }

    /// Every split on the shown desktop back to half and half.
    public func equalize() {
        if isCanvas {
            withStrip(desk) { strip in
                for id in strip.columns.map(\.active) { strip.setWidth(options.columnWidth, of: id) }
            }
            relayout()
            return
        }
        layouts[desk].equalize()
        relayout()
    }

    /// Makes a window wider or taller (negative: narrower, shorter) by
    /// `fraction` of the area's width and height. A tile moves the edge that
    /// has a neighbor; a floating window grows around its center.
    public func grow(_ id: CGWindowID, by fraction: CGSize) {
        guard dragging == nil, resizing == nil, let home = desk(of: id) else { return }
        let area = area(of: home)
        let fullArea = fullArea(of: home)
        let delta = CGSize(width: area.width * fraction.width, height: area.height * fraction.height)
        if var state = floating[id] {
            let minimum = minimums[id] ?? CGSize(width: 120, height: 80)
            let width = min(max(state.frame.width + delta.width, minimum.width), fullArea.width)
            let height = min(max(state.frame.height + delta.height, minimum.height), fullArea.height)
            state.frame = CGRect(x: state.frame.midX - width / 2, y: state.frame.midY - height / 2,
                                 width: width, height: height)
            floating[id] = state
        } else if isCanvas {
            withStrip(home) { strip in strip.cycleWidth(of: id, wider: fraction.width >= 0) }
        } else {
            let tile = group(of: id)?.active ?? id
            guard layouts[home].contains(tile) else { return }
            if fullscreen[home] == tile { fullscreen[home] = nil }
            layouts[home].grow(tile, by: delta, in: area, gaps: options.gaps)
        }
        relayout()
    }

    // MARK: Floating and fullscreen

    /// Takes a tiled window out of the layout (it glides to a centered
    /// floating frame, or where it floated last) or puts a floating one back
    /// into the tile under its center.
    public func toggleFloating(_ id: CGWindowID) {
        guard let window = windows[id], dragging == nil, resizing == nil else { return }
        if let state = floating[id] {
            floating[id] = nil
            if scratchpad == id {
                scratchpad = nil
                log("no longer the scratchpad: \(window.title)")
            }
            lastFloatFrame[id] = state.frame
            let frame = window.serverFrame ?? state.frame
            let home = state.desk
            let area = area(of: home)
            layouts.assign(id, to: home) { tree in
                tree.insert(id, at: CGPoint(x: frame.midX, y: frame.midY), in: area, gaps: options.gaps,
                            minimums: layoutMinimums, maximums: maximums)
            }
            log("tiled: \(window.title)")
        } else if let home = layouts.space(of: id) {
            if fullscreen[home] == id { fullscreen[home] = nil }
            layouts.remove(id)
            floating[id] = Floating(desk: home, frame: lastFloatFrame[id] ?? defaultFloatFrame(for: id, on: home))
            raise(id)
            log("floating: \(window.title)")
        }
        relayout()
    }

    /// `share` (60%) of the area, centered, within the window's own limits.
    private func defaultFloatFrame(for id: CGWindowID, share: CGFloat = 0.6, on home: Desk? = nil) -> CGRect {
        let area = area(of: home ?? desk)
        let fullArea = fullArea(of: home ?? desk)
        let minimum = minimums[id] ?? .zero
        let maximum = maximums[id] ?? .infinite
        let width = min(max(area.width * share, minimum.width), maximum.width, fullArea.width)
        let height = min(max(area.height * share, minimum.height), maximum.height, fullArea.height)
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    /// Lets a tiled window fill the whole area (inside the outer gap, not
    /// macOS fullscreen), or sends it back to its tile.
    public func toggleFullscreen(_ id: CGWindowID) {
        guard let window = windows[id], let home = layouts.space(of: id), dragging == nil, resizing == nil else { return }
        if fullscreen[home] == id {
            fullscreen[home] = nil
            log("fullscreen off: \(window.title)")
        } else {
            fullscreen[home] = id
            raise(id)
            log("fullscreen: \(window.title)")
        }
        relayout()
    }

    // MARK: Remote control

    /// Every managed window as a JSON array, for the command socket.
    public func describeWindows() -> String {
        let shown = targetFrames()
        let items: [[String: Any]] = windows.values.sorted { $0.windowID < $1.windowID }.map { window in
            let id = window.windowID
            var item: [String: Any] = [
                "id": Int(id),
                "pid": Int(window.pid),
                "app": NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "",
                "title": window.title,
                "floating": floating[id] != nil,
                "focused": focused == id,
                "scratchpad": scratchpad == id,
            ]
            if let home = desk(of: id) {
                let display = displayOfSpace[home.space]
                let order = display.flatMap { desktopOrder[$0] } ?? knownSpaceOrder
                item["desktop"] = (order.firstIndex(of: home.space) ?? -1) + 1
                item["display"] = (screens.firstIndex { $0.uuid == display } ?? 0) + 1
                item["fullscreen"] = fullscreen[home] == id
            }
            if let group = group(of: id) { item["group"] = group.members.map { Int($0) } }
            if let frame = shown[id] ?? window.serverFrame {
                item["frame"] = ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
            }
            return item
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.sortedKeys]) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Scratchpad

    /// One window kept at hand (Hyprland's special workspace): Super + S
    /// hides it (minimized) and brings it back, floating in the middle of
    /// whatever desktop is shown. A minimized window comes back on its own
    /// desktop (measured on macOS 26, from the Dock too), so one kept on
    /// another desktop is carried over afterwards (onScratchpadElsewhere).
    public private(set) var scratchpad: CGWindowID?
    public private(set) var scratchpadHidden = false
    /// The scratchpad came back on another desktop than `SpaceID`, the one
    /// shown when it was asked for: the host carries it over (DesktopMover).
    public var onScratchpadElsewhere: ((AXWindow, SpaceID) -> Void)?

    /// With no scratchpad yet, `focused` becomes it; otherwise it is hidden
    /// when it shows on this desktop and brought here when not.
    public func toggleScratchpad(focused id: CGWindowID?) {
        if let pad = scratchpad, windows[pad] == nil { scratchpad = nil }
        guard dragging == nil, resizing == nil else { return }
        guard let pad = scratchpad else {
            if let id, windows[id] != nil { makeScratchpad(id) }
            return
        }
        if !scratchpadHidden, floating[pad]?.desk == desk {
            hideScratchpad(pad)
        } else {
            showScratchpad(pad)
        }
    }

    private func makeScratchpad(_ id: CGWindowID) {
        guard let window = windows[id] else { return }
        if let home = desk(of: id) { dirtyDesks.insert(home) }
        leaveGroup(id)
        layouts.remove(id)
        fullscreen = fullscreen.filter { $0.value != id }
        scratchpad = id
        scratchpadHidden = false
        floating[id] = Floating(desk: desk, frame: defaultFloatFrame(for: id, share: options.scratchpadShare))
        raise(id)
        log("scratchpad: \(window.title)")
        relayout()
    }

    private func hideScratchpad(_ id: CGWindowID) {
        guard let window = windows[id] else { return }
        floating[id] = nil
        springs[id] = nil
        scratchpadHidden = true
        worker(for: window.pid).run { _ = window.element.set(kAXMinimizedAttribute, bool: true) }
        log("scratchpad hidden")
        relayout()
        focusChanged()
    }

    private func showScratchpad(_ id: CGWindowID) {
        guard let window = windows[id] else { return }
        let wasShownElsewhere = !scratchpadHidden
        let wanted = space
        floating[id] = nil
        springs[id] = nil
        scratchpadHidden = true
        worker(for: window.pid).run { [weak self] in
            if wasShownElsewhere {
                // On another desktop: minimize first, so it comes back here.
                _ = window.element.set(kAXMinimizedAttribute, bool: true)
                Thread.sleep(forTimeInterval: 0.45)
            }
            _ = window.element.set(kAXMinimizedAttribute, bool: false)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.scratchpadRestored(id, wanted: wanted) }
            }
        }
    }

    private func scratchpadRestored(_ id: CGWindowID, wanted: SpaceID) {
        guard scratchpad == id, let window = windows[id] else { return }
        if let home = Spaces.of(id), home != wanted { onScratchpadElsewhere?(window, wanted) }
        scratchpadHidden = false
        window.invalidateCache()
        floating[id] = Floating(desk: desk,
                                frame: lastFloatFrame[id] ?? defaultFloatFrame(for: id, share: options.scratchpadShare))
        if let frame = window.serverFrame { springs[id] = AnimatedRect(frame) }
        log("scratchpad shown")
        relayout()
        focus(id)
    }

    // MARK: Drag and drop

    /// The user picked up `id`: it leaves the layout and the rest closes the gap.
    public func beginDrag(_ id: CGWindowID) {
        guard dragging == nil else { return }
        dropProxy(id)
        if floating[id] != nil {
            // Floating windows just move; nothing else changes.
            dragging = id
            springs[id] = nil
            publishActive()
            return
        }
        if group(of: id) != nil {
            // Dragging a tab out of its group.
            leaveGroup(id)
            dragging = id
            windows[id]?.invalidateCache()
            log("drag tab out: \(windows[id]?.title ?? "\(id)")")
            relayout()
            return
        }
        guard let home = layouts.space(of: id) else { return }
        dragging = id
        if fullscreen[home] == id { fullscreen[home] = nil }
        layouts.remove(id)
        windows[id]?.invalidateCache()
        log("drag start: \(windows[id]?.title ?? "\(id)")")
        relayout()
    }

    /// The user let go at `point`: the tile under the mouse splits to take it.
    /// The dropped window starts from where the user left it.
    public func endDrag(at point: CGPoint) {
        guard let id = dragging else { return }
        dragging = nil
        if var state = floating[id] {
            state.frame = windows[id]?.serverFrame ?? state.frame
            state.desk = desk(at: point)
            floating[id] = state
            windows[id]?.invalidateCache()
            publishActive()
            return
        }
        // A centered window is never asked to grow again, so a wrong maximum
        // would stick. Dropping it gives it a fresh chance.
        maximums[id] = nil
        // Dropped on the middle of a tile: it joins that tile as a tab.
        // The display under the mouse takes it (dragging over to another display).
        let home = desk(at: point)
        let area = area(of: home)
        if isCanvas {
            layouts.assign(id, to: home) { $0.insert(id) }
            withStrip(home) { strip in
                strip.focus(id)
                let inner = area.insetBy(dx: options.gaps.outer, dy: options.gaps.outer)
                strip.moveColumn(of: id, nearX: point.x - inner.minX + strip.offset,
                                 width: inner.width, gaps: options.gaps)
            }
            if let window = windows[id] {
                window.invalidateCache()
                springs[id] = AnimatedRect(window.serverFrame ?? area)
            }
            log("drop on the strip: \(windows[id]?.title ?? "\(id)")")
            relayout()
            return
        }
        let tiles = layouts[home].tiles(in: area, gaps: options.gaps, minimums: layoutMinimums, maximums: maximums)
        if let (target, tile) = tiles.first(where: { $0.value.insetBy(dx: $0.value.width * 0.3, dy: $0.value.height * 0.3).contains(point) }) {
            _ = tile
            join(id, with: target)
        } else {
            layouts.assign(id, to: home) { tree in
                tree.insert(id, at: point, in: area, gaps: options.gaps, minimums: layoutMinimums, maximums: maximums)
            }
        }
        if let window = windows[id] {
            window.invalidateCache()
            springs[id] = AnimatedRect(window.serverFrame ?? area)
        }
        log("drop: \(windows[id]?.title ?? "\(id)") at \(Int(point.x)),\(Int(point.y))")
        relayout()
    }

    // MARK: Resize by mouse

    /// The user grabbed an edge of `id`. From now on the window follows the
    /// mouse (macOS resizes it) and its neighbors follow the window.
    public func beginResize(_ id: CGWindowID) {
        guard dragging == nil, resizing == nil, layouts.space(of: id) != nil || floating[id] != nil else { return }
        dropProxy(id)
        let home = desk(of: id) ?? desk
        if fullscreen[home] == id { fullscreen[home] = nil }
        resizing = id
        if let frame = windows[id]?.serverFrame,
           let tile = layouts[home].tiles(in: area(of: home), gaps: options.gaps)[id] {
            resizeStart = (frame, tile)
        }
        log("resize start: \(windows[id]?.title ?? "\(id)")")
        publishActive()
    }

    /// The window's frame and its (plain) tile when the resize began.
    private var resizeStart: (frame: CGRect, tile: CGRect)?

    /// Called while the edge moves, with the window's current frame.
    public func updateResize(to frame: CGRect) {
        guard let id = resizing else { return }
        if var state = floating[id] {
            state.frame = frame
            floating[id] = state
            return
        }
        // Only the edges that really moved since the grab count, measured
        // against the window's own frame then. Compared with the tile, a
        // window that never matched it exactly (a minimum size, centered)
        // looked as if every edge moved, and the layout jumped.
        let home = desk(of: id) ?? desk
        let area = area(of: home)
        guard let start = resizeStart else {
            layouts[home].resize(id, to: frame, in: area, gaps: options.gaps)
            relayout()
            return
        }
        var target = start.tile
        let left = frame.minX - start.frame.minX, right = frame.maxX - start.frame.maxX
        let top = frame.minY - start.frame.minY, bottom = frame.maxY - start.frame.maxY
        if abs(left) > 1 { target.origin.x += left; target.size.width -= left }
        if abs(right) > 1 { target.size.width += right }
        if abs(top) > 1 { target.origin.y += top; target.size.height -= top }
        if abs(bottom) > 1 { target.size.height += bottom }
        layouts[home].resize(id, to: target, in: area, gaps: options.gaps)
        relayout()
    }

    /// The user let go: the window settles into its (new) tile.
    public func endResize() {
        guard let id = resizing else { return }
        resizing = nil
        resizeStart = nil
        if var state = floating[id] {
            state.frame = windows[id]?.serverFrame ?? state.frame
            floating[id] = state
            windows[id]?.invalidateCache()
            publishActive()
            return
        }
        if let window = windows[id] {
            window.invalidateCache()
            springs[id] = AnimatedRect(window.serverFrame ?? area)
        }
        log("resize end: \(windows[id]?.title ?? "\(id)")")
        relayout()
        // Apps may apply the drag's last size a moment after the mouse is
        // up; look again once they had the time.
        // A new resize replaces the looks still pending from the last one.
        for work in resyncs { work.cancel() }
        resyncs = [0.1, 0.35, 0.8].map { delay in
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.resyncFromServer() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }
    private var resyncs: [DispatchWorkItem] = []

    // MARK: Proxy glides

    /// Windows whose size is about to change glide as a snapshot. The real
    /// window goes just off screen and takes its new size there right away,
    /// so the app has the whole glide to redraw; its new look fades in.
    private func startProxies() {
        proxyFinish?.cancel()
        proxyFinish = nil
        guard options.resize == .proxy, proxies.isAvailable else { return }
        // While the user drags an edge, neighbors follow live: a frozen
        // snapshot would look wrong for the whole drag, and resizing parked
        // windows on every mouse event made the drag lag.
        guard resizing == nil else {
            for id in proxied { dropProxy(id) }
            return
        }
        for (id, spring) in springs where !proxied.contains(id) && id != dragging && id != resizing {
            guard let pid = windows[id]?.pid, slowApps.contains(pid) else { continue }
            let current = spring.current, target = spring.target
            guard abs(current.width - target.width) > 2 || abs(current.height - target.height) > 2,
                  let window = windows[id], proxies.show(id, at: current) else { continue }
            proxied.insert(id)
            proxyGlides += 1
            write(id, CGRect(origin: parkedOrigin(for: target), size: target.size))
            preparedSize[id] = target.size
            proxies.prepareNewLook(id)
        }
        // Proxied windows whose target size changed mid-glide: new size off
        // screen, and their new look is prepared again.
        for id in proxied {
            guard let target = springs[id]?.target, preparedSize[id] != target.size else { continue }
            write(id, CGRect(origin: parkedOrigin(for: target), size: target.size))
            preparedSize[id] = target.size
            proxies.prepareNewLook(id)
        }
    }

    /// Whether a snapshot is still standing in for a real window. Its real
    /// window waits off screen until the app has redrawn, so nothing should
    /// measure window frames while this is true.
    public var hasProxies: Bool { !proxied.isEmpty }

    /// How many window glides used a snapshot (for the probe).
    public private(set) var proxyGlides = 0

    /// Just past the right screen edge, same height on screen.
    private func parkedOrigin(for frame: CGRect) -> CGPoint {
        CGPoint(x: (screens.map(\.bounds.maxX).max() ?? screenArea.maxX) - 1, y: frame.minY)
    }

    /// The glide is over: resize the real windows off screen, give the apps
    /// a moment to redraw, then swap them in for their snapshots.
    private func finishProxies(waited: TimeInterval = 0, then done: @escaping () -> Void) {
        guard !proxied.isEmpty else { done(); return }
        // Swap only once every app has finished drawing at its new size
        // (its new look is showing), or after 0.5 s at most.
        let step: TimeInterval = 0.03
        let allReady = proxied.allSatisfy { proxies.isReady($0) }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let ready = self.proxied.allSatisfy { self.proxies.isReady($0) }
                guard ready || waited >= 0.5 else {
                    self.finishProxies(waited: waited + step, then: done)
                    return
                }
                let swapped = self.proxied
                self.proxied.removeAll()
                for id in swapped {
                    self.preparedSize[id] = nil
                    // Without a spring (the glide was cut short by a desktop
                    // switch, say) the window would stay parked off screen,
                    // so its place is looked up instead.
                    guard let target = self.springs[id]?.target ?? self.placeOf(id) else {
                        self.proxies.remove(id)
                        continue
                    }
                    // Size and position again: Chromium-based apps (Vivaldi)
                    // ignore a resize while their window is off screen, so
                    // the size written while parked may not have landed.
                    self.windows[id]?.invalidateCache()
                    // The snapshot goes once the app has the window in place,
                    // plus one beat so it is on screen.
                    self.write(id, target) { [weak self] in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                            MainActor.assumeIsolated {
                                guard let self, !self.proxied.contains(id) else { return }
                                self.proxies.remove(id)
                            }
                        }
                    }
                }
                done()
            }
        }
        proxyFinish = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (allReady ? 0 : step), execute: work)
    }

    /// Sorts apps into slow and fast by their measured resize cost.
    private func updateSlowApps() {
        var costs: [pid_t: [Double]] = [:]
        for window in windows.values {
            if let cost = window.medianResizeCost { costs[window.pid, default: []].append(cost) }
        }
        for (pid, values) in costs {
            let slow = values.max()! > slowResizeThreshold
            if slow, !slowApps.contains(pid) {
                log("slow at resizing, will glide as snapshot: pid \(pid) (\(Int(values.max()! * 1000)) ms)")
                slowApps.insert(pid)
            } else if !slow, slowApps.contains(pid) {
                slowApps.remove(pid)
            }
        }
    }

    /// A proxied window the user grabs becomes real again at once.
    private func dropProxy(_ id: CGWindowID) {
        guard proxied.remove(id) != nil else { return }
        if let frame = springs[id]?.current ?? placeOf(id) { write(id, frame) }
        proxies.remove(id)
    }

    /// Where a window belongs right now, spring or no spring: its frame on
    /// the desk it lives on.
    private func placeOf(_ id: CGWindowID) -> CGRect? {
        if let frame = targetFrames()[id] { return frame }
        guard let home = desk(of: id) else { return nil }
        return frames(on: home)[id]
    }

    /// Stops the snapshot refresh timer.
    public func stopSnapshots() {
        snapshotTimer?.invalidate()
        snapshotTimer = nil
    }

    /// Keeps snapshots of the shown windows fresh while nothing moves.
    public func startSnapshots(every interval: TimeInterval = 3) {
        guard options.resize == .proxy, snapshotTimer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSnapshots() }
        }
        RunLoop.main.add(timer, forMode: .common)
        snapshotTimer = timer
        refreshSnapshots()
    }

    private func refreshSnapshots() {
        guard options.resize == .proxy, !isAnimating, proxied.isEmpty, dragging == nil else { return }
        proxies.refresh(shownDesks.flatMap { layouts[$0].ids } + floating.filter { isShown($0.value.desk) }.map(\.key))
    }

    // MARK: Animation loop

    public func resetStats() {
        applyTimes = Durations()
        stepIntervals = Durations()
        for worker in workers.values { worker.resetStats() }
    }

    private func startLoop() {
        guard ticker == nil else { return }
        lastStep = 0
        let ticker = DisplayTicker(frameRate: Float(options.frameRate)) { [weak self] in self?.step() }
        self.ticker = ticker
        ticker.start()
        step()
    }

    private func step() {
        let now = CACurrentMediaTime()
        let dt: CGFloat
        if lastStep == 0 {
            dt = 1 / options.frameRate
        } else {
            stepIntervals.add(now - lastStep)
            dt = min(now - lastStep, 0.1)
        }
        lastStep = now

        var work: [(CGWindowID, AXWindow, CGRect)] = []
        for (id, var spring) in springs where !spring.isSettled {
            if options.resize != .snap {
                spring.step(dt, response: options.response)
            } else {
                spring.stepResizingOnce(dt, response: options.response)
            }
            springs[id] = spring
            if proxied.contains(id) {
                proxies.move(id, to: spring.current)
            } else if let window = windows[id] {
                work.append((id, window, spring.current))
            }
        }

        for (id, _, frame) in work { write(id, frame) }
        if !groups.isEmpty { publishTabBars() }
        publishActive()
        // Main-thread cost of the whole step; the apps work on their own threads.
        applyTimes.add(CACurrentMediaTime() - now)

        if springs.values.allSatisfy(\.isSettled) {
            ticker?.stop()
            ticker = nil
            updateSlowApps()
            finishProxies { [weak self] in
                guard let self else { return }
                self.onSettled?()
                self.scheduleFitCheck(retry: true)
                self.refreshSnapshots()
            }
        }
    }

    /// After a glide, compare where windows really are with their tiles.
    /// A window that does not fit gets its frame written once more first
    /// (it may have missed a write); only a second refusal is learned as a
    /// minimum or maximum. Learned limits also heal: a window seen smaller
    /// than its minimum or bigger than its maximum loosens that limit.
    private func scheduleFitCheck(retry: Bool) {
        fitCheck?.cancel()
        let sinceSwitch = CACurrentMediaTime() - lastSpaceSwitch
        let delay = max(0.15, 0.8 - sinceSwitch)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.checkFit(retry: retry) }
        }
        fitCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func checkFit(retry: Bool) {
        guard !isAnimating, dragging == nil, resizing == nil else { return }
        // Tiled and grouped windows (a group's sit below its tab bar); not a
        // fullscreen window, which is bigger than its tile on purpose.
        let grouped = Set(groups.flatMap(\.members))
        var targets: [CGWindowID: CGRect] = [:]
        for shown in shownDesks {
            let tiled = Set(layouts[shown].ids)
            targets.merge(frames(on: shown).filter { tiled.contains($0.key) || grouped.contains($0.key) }) { a, _ in a }
            if let id = fullscreen[shown] { targets[id] = nil }
        }
        var misfits: [CGWindowID] = []
        var moved: [CGWindowID] = []
        var changed = false
        for (id, target) in targets {
            guard let window = windows[id], let actual = window.serverFrame else { continue }
            // Somebody moved it (an app applying a late resize, say) while
            // the engine thought it was in place: put it back.
            if abs(actual.minX - target.minX) > 2 || abs(actual.minY - target.minY) > 2 {
                moved.append(id)
            }
            var minimum = minimums[id] ?? .zero
            var maximum = maximums[id] ?? .infinite
            // Heal limits the window no longer honors.
            if actual.width < minimum.width - 4 { minimum.width = actual.width }
            if actual.height < minimum.height - 4 { minimum.height = actual.height }
            if actual.width > maximum.width + 4 { maximum.width = .infinity }
            if actual.height > maximum.height + 4 { maximum.height = .infinity }

            let tooBig = actual.width > target.width + 4 || actual.height > target.height + 4
            // Small shortfalls are apps snapping to character cells, not a real limit.
            let tooSmall = actual.width < target.width - 20 || actual.height < target.height - 20
            if tooBig || tooSmall {
                if retry {
                    misfits.append(id)
                    continue
                }
                if actual.width > target.width + 4 { minimum.width = max(minimum.width, actual.width) }
                if actual.height > target.height + 4 { minimum.height = max(minimum.height, actual.height) }
                if actual.width < target.width - 20 { maximum.width = min(maximum.width, actual.width) }
                if actual.height < target.height - 20 { maximum.height = min(maximum.height, actual.height) }
            }

            if minimum != (minimums[id] ?? .zero) || maximum != (maximums[id] ?? .infinite) {
                log("limits for \(window.title.isEmpty ? "\(id)" : window.title): min \(Self.describe(minimum)) max \(Self.describe(maximum))")
                minimums[id] = minimum == .zero ? nil : minimum
                maximums[id] = maximum == .infinite ? nil : maximum
                changed = true
            }
        }
        if !misfits.isEmpty {
            for id in misfits {
                guard let window = windows[id], let target = targets[id] else { continue }
                window.invalidateCache()
                write(id, target)
            }
            scheduleFitCheck(retry: false)
        }
        if !moved.isEmpty {
            log("put back \(moved.count) window(s) that were moved behind the engine's back")
            for id in moved where !misfits.contains(id) {
                guard let window = windows[id], let actual = window.serverFrame else { continue }
                window.invalidateCache()
                springs[id] = AnimatedRect(actual)
            }
            changed = true
        }
        if changed { relayout() } else { publishActive() }
    }

    /// Measures where the shown desktop's windows really are and glides any
    /// that are not where the engine believes back to their place. The
    /// engine's springs only know where it sent a window; an app that moves
    /// or resizes a window later (kitty applying the last size of an edge
    /// drag after the mouse is up) would otherwise stay wrong until the next
    /// desktop switch.
    public func resyncFromServer() {
        guard dragging == nil, resizing == nil else { return }
        var drifted = false
        for (id, target) in targetFrames() where !proxied.contains(id) {
            guard let window = windows[id], let actual = window.serverFrame else { continue }
            let off = max(abs(actual.minX - target.minX), abs(actual.minY - target.minY),
                          abs(actual.width - target.width), abs(actual.height - target.height))
            guard off > 2 else { continue }
            window.invalidateCache()
            springs[id] = AnimatedRect(actual)
            drifted = true
        }
        if drifted { relayout() }
    }

    private static func describe(_ size: CGSize) -> String {
        func side(_ v: CGFloat) -> String { v.isFinite ? "\(Int(v))" : "-" }
        return "\(side(size.width))x\(side(size.height))"
    }

    private func forget(_ id: CGWindowID) {
        // A failed write can also mean a busy app; only drop windows that are
        // really gone. Asking is a round trip, so it runs on the app's thread.
        guard let window = windows[id] else { return }
        worker(for: window.pid).run { [weak self] in
            let gone = window.position == nil
            DispatchQueue.main.async { MainActor.assumeIsolated { if gone { self?.forgetNow(id) } } }
        }
    }

    private func forgetNow(_ id: CGWindowID) {
        log("window gone: \(windows[id]?.title ?? "\(id)")")
        remove(id)
    }
}
