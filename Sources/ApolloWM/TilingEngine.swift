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
        /// How window sizes animate. Hosts can change it at any time, e.g.
        /// from a settings toggle; it applies from the next frame on.
        public var resize: ResizeAnimation = .smooth
        /// Screen space the host keeps for itself, e.g. ApolloShell's 44 pt
        /// sidebar on the left. Tiles never go there.
        public var reserved = NSEdgeInsets()

        public init() {}
    }

    public let screenArea: CGRect
    public var options: Options

    /// Where tiles go: the screen area minus the host's reserved edges.
    public var area: CGRect {
        let r = options.reserved
        return CGRect(x: screenArea.minX + r.left,
                      y: screenArea.minY + r.top,
                      width: screenArea.width - r.left - r.right,
                      height: screenArea.height - r.top - r.bottom)
    }
    /// One layout per desktop. Only `space`'s windows are arranged; the others
    /// keep their tiles until their desktop is shown again.
    public private(set) var layouts = SpaceLayouts<Desk, CGWindowID>()
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

    public init(area: CGRect, options: Options = Options()) {
        self.screenArea = area
        self.options = options
    }

    // MARK: Layout

    /// Takes over windows in their on-screen order. `space` is the desktop
    /// they live on (default: the shown one); windows on hidden desktops are
    /// arranged there right away, without animation.
    public func adopt(_ newWindows: [AXWindow], on space: SpaceID? = nil) {
        let target = deskShown(on: space)
        for window in newWindows where windows[window.windowID] == nil {
            let id = window.windowID
            windows[id] = window
            if originalFrames[id] == nil { originalFrames[id] = window.serverFrame }
            inspect(window)
            // Known from a saved layout: it keeps its old spot.
            if let home = desk(of: id) {
                dirtyDesks.insert(home)
                continue
            }
            if floatsByItself(window, on: target) { continue }
            layouts.assign(id, to: target) { $0.insert(id) }
        }
        dirtyDesks.insert(target)
        relayout()
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
        windows[id] = window
        if originalFrames[id] == nil { originalFrames[id] = window.serverFrame }
        inspect(window)
        let target = deskShown(on: space)
        dirtyDesks.insert(desk(of: id) ?? target)
        if desk(of: id) != nil || floatsByItself(window, on: target) {
            relayout()
            return
        }
        let shown = target == desk
        layouts.assign(id, to: target) { tree in
            if let point, shown {
                tree.insert(id, at: point, in: area, gaps: options.gaps, minimums: minimums, maximums: maximums)
            } else {
                tree.insert(id)
            }
        }
        relayout()
    }

    /// Drops a window from tiling; the others close the gap.
    public func remove(_ id: CGWindowID) {
        guard windows[id] != nil else { return }
        if dragging == id { dragging = nil }
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
        layouts.remove(id)
        relayout()
    }

    /// Dialogs, panels and windows that cannot be resized (or whose minimum
    /// and maximum size are the same) float where the app put them instead of
    /// taking a tile. Returns true when the window was made floating.
    private func floatsByItself(_ window: AXWindow, on target: Desk) -> Bool {
        guard window.subrole != kAXStandardWindowSubrole else { return false }
        makeFloating(window, reason: window.subrole, on: target)
        return true
    }

    /// Floats `window` where it is, kept inside the usable area.
    private func makeFloating(_ window: AXWindow, reason: String, on target: Desk) {
        let id = window.windowID
        var frame = window.serverFrame ?? defaultFloatFrame(for: id)
        frame.origin.x = min(max(frame.minX, area.minX), max(area.maxX - frame.width, area.minX))
        frame.origin.y = min(max(frame.minY, area.minY), max(area.maxY - frame.height, area.minY))
        floating[id] = Floating(desk: target, frame: frame)
        log("floats by itself (\(reason)): \(window.title)")
    }

    /// Asks a new window for its size limits and whether it can be resized,
    /// on its app's thread (these are round trips into the app). A window
    /// that cannot be resized, or whose minimum and maximum are the same,
    /// then leaves the layout and floats.
    private func inspect(_ window: AXWindow) {
        let largest = area.insetBy(dx: options.gaps.outer, dy: options.gaps.outer)
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
        }
        relayout()
    }

    /// The window now lives on another desktop (the user moved it there).
    public func move(_ id: CGWindowID, to targetSpace: SpaceID) {
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
        // A drag cannot survive a desktop switch; the window stays where it is.
        if let id = dragging {
            dragging = nil
            layouts.assign(id, to: desk) { $0.insert(id) }
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

    /// Frames skipped because an app was still busy with an older one.
    public var droppedFrames: Int { workers.values.reduce(0) { $0 + $1.droppedFrames } }

    /// The desk a window belongs to, tiled or floating.
    public func desk(of id: CGWindowID) -> Desk? {
        layouts.space(of: id) ?? floating[id]?.desk
    }

    /// Recomputes the layout and lets every window glide to its new tile.
    /// Windows not on the shown desktop are left alone.
    public func relayout() {
        layouts[desk].freezeDirections(in: area, gaps: options.gaps)
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
        startProxies()
        startLoop()
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
        if let id = floating.first(where: { $0.value.desk == desk && $0.value.frame.contains(point) })?.key {
            return id
        }
        if let id = fullscreen[desk], tree.contains(id) { return id }
        return tree.id(at: point, in: area, gaps: options.gaps, minimums: minimums, maximums: maximums)
    }

    /// The whole usable area, inside the outer gap.
    private var fullArea: CGRect { area.insetBy(dx: options.gaps.outer, dy: options.gaps.outer) }

    /// Where the engine last put the window (nil while dragged or unknown).
    public func expectedFrame(of id: CGWindowID) -> CGRect? {
        springs[id]?.current
    }

    /// Where every window on the shown desktop should be: tiles, then a
    /// fullscreen window over its tile, then floating windows.
    public func targetFrames() -> [CGWindowID: CGRect] {
        var frames = frames(on: desk)
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
    }

    public func snapshot() -> Snapshot {
        Snapshot(layouts: layouts, floating: floating,
                 activeWorkspace: activeWorkspace, originalFrames: originalFrames)
    }

    /// Loads a saved arrangement before windows are adopted. Windows that no
    /// longer exist (`alive` rejects them) are dropped; the rest return to
    /// their old tiles when they are adopted.
    public func restore(_ snapshot: Snapshot, alive: (CGWindowID) -> Bool) {
        var saved = snapshot.layouts
        saved.retain(where: alive)
        layouts = saved
        floating = snapshot.floating.filter { alive($0.key) }
        activeWorkspace = snapshot.activeWorkspace
        originalFrames = snapshot.originalFrames.filter { alive($0.key) }
        desk.workspace = activeWorkspace[space] ?? 1
        log("restored layout: \(layouts.spaceOf.count) tiled, \(floating.count) floating")
    }

    /// Hidden desktops change too (a window closed there, a new one opened):
    /// their windows are put straight into place, nobody sees a glide.
    private func arrangeHiddenDesks() {
        for hidden in dirtyDesks where hidden != desk && hidden.space != space {
            layouts[hidden].freezeDirections(in: area, gaps: options.gaps)
            for (id, frame) in frames(on: hidden) where windows[id] != nil { write(id, frame) }
        }
        dirtyDesks.removeAll()
    }

    /// Where the windows of `desk` go when it is shown: tiles, a fullscreen
    /// window over its tile, floating windows.
    public func frames(on desk: Desk) -> [CGWindowID: CGRect] {
        var frames = layouts[desk].layout(in: area, gaps: options.gaps, minimums: minimums, maximums: maximums)
        if let id = fullscreen[desk], frames[id] != nil {
            frames[id] = DwindleTree<CGWindowID>.centered(fullArea, maximum: maximums[id])
        }
        for (id, state) in floating where state.desk == desk {
            frames[id] = state.frame
        }
        return frames
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

    // MARK: Floating and fullscreen

    /// Takes a tiled window out of the layout (it glides to a centered
    /// floating frame, or where it floated last) or puts a floating one back
    /// into the tile under its center.
    public func toggleFloating(_ id: CGWindowID) {
        guard let window = windows[id], dragging == nil, resizing == nil else { return }
        if let state = floating[id] {
            floating[id] = nil
            lastFloatFrame[id] = state.frame
            let frame = window.serverFrame ?? state.frame
            layouts.assign(id, to: desk) { tree in
                tree.insert(id, at: CGPoint(x: frame.midX, y: frame.midY), in: area, gaps: options.gaps,
                            minimums: minimums, maximums: maximums)
            }
            log("tiled: \(window.title)")
        } else if tree.contains(id) {
            if fullscreen[desk] == id { fullscreen[desk] = nil }
            layouts.remove(id)
            floating[id] = Floating(desk: desk, frame: lastFloatFrame[id] ?? defaultFloatFrame(for: id))
            raise(id)
            log("floating: \(window.title)")
        }
        relayout()
    }

    /// 60% of the area, centered, within the window's own limits.
    private func defaultFloatFrame(for id: CGWindowID) -> CGRect {
        let minimum = minimums[id] ?? .zero
        let maximum = maximums[id] ?? .infinite
        let width = min(max(area.width * 0.6, minimum.width), maximum.width, fullArea.width)
        let height = min(max(area.height * 0.6, minimum.height), maximum.height, fullArea.height)
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    /// Lets a tiled window fill the whole area (inside the outer gap, not
    /// macOS fullscreen), or sends it back to its tile.
    public func toggleFullscreen(_ id: CGWindowID) {
        guard let window = windows[id], tree.contains(id), dragging == nil, resizing == nil else { return }
        if fullscreen[desk] == id {
            fullscreen[desk] = nil
            log("fullscreen off: \(window.title)")
        } else {
            fullscreen[desk] = id
            raise(id)
            log("fullscreen: \(window.title)")
        }
        relayout()
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
            return
        }
        guard tree.contains(id) else { return }
        dragging = id
        if fullscreen[desk] == id { fullscreen[desk] = nil }
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
            state.desk = desk
            floating[id] = state
            windows[id]?.invalidateCache()
            return
        }
        // A centered window is never asked to grow again, so a wrong maximum
        // would stick. Dropping it gives it a fresh chance.
        maximums[id] = nil
        layouts.assign(id, to: desk) { tree in
            tree.insert(id, at: point, in: area, gaps: options.gaps, minimums: minimums, maximums: maximums)
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
        guard dragging == nil, resizing == nil, tree.contains(id) || floating[id] != nil else { return }
        dropProxy(id)
        if fullscreen[desk] == id { fullscreen[desk] = nil }
        resizing = id
        log("resize start: \(windows[id]?.title ?? "\(id)")")
    }

    /// Called while the edge moves, with the window's current frame.
    public func updateResize(to frame: CGRect) {
        guard let id = resizing else { return }
        if var state = floating[id] {
            state.frame = frame
            floating[id] = state
            return
        }
        layouts[desk].resize(id, to: frame, in: area, gaps: options.gaps)
        relayout()
    }

    /// The user let go: the window settles into its (new) tile.
    public func endResize() {
        guard let id = resizing else { return }
        resizing = nil
        if var state = floating[id] {
            state.frame = windows[id]?.serverFrame ?? state.frame
            floating[id] = state
            windows[id]?.invalidateCache()
            return
        }
        if let window = windows[id] {
            window.invalidateCache()
            springs[id] = AnimatedRect(window.serverFrame ?? area)
        }
        log("resize end: \(windows[id]?.title ?? "\(id)")")
        relayout()
    }

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

    /// How many window glides used a snapshot (for the probe).
    public private(set) var proxyGlides = 0

    /// Just past the right screen edge, same height on screen.
    private func parkedOrigin(for frame: CGRect) -> CGPoint {
        CGPoint(x: screenArea.maxX - 1, y: frame.minY)
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
                    guard let target = self.springs[id]?.target else {
                        self.proxies.remove(id)
                        continue
                    }
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
        if let frame = springs[id]?.current { write(id, frame) }
        proxies.remove(id)
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
        proxies.refresh(tree.ids + floating.filter { $0.value.desk == desk }.map(\.key))
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
        // Tiles only: a fullscreen window is bigger than its tile on purpose.
        var targets = tree.layout(in: area, gaps: options.gaps, minimums: minimums, maximums: maximums)
        if let id = fullscreen[desk] { targets[id] = nil }
        var misfits: [CGWindowID] = []
        var changed = false
        for (id, target) in targets {
            guard let window = windows[id], let actual = window.serverFrame else { continue }
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
        if changed { relayout() }
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
