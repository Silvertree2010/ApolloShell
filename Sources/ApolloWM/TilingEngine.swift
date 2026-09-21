import ApolloWMCore
import AppKit
import Synchronization

/// One layout slot: a macOS desktop (Space) and one of our own workspaces
/// on it (1-9, Hyprland style).
public struct Desk: Hashable, Sendable, CustomStringConvertible {
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
        /// Write frames of different windows concurrently.
        public var parallel = true
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
    public struct Floating: Sendable {
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

    /// Time spent writing frames per animation step.
    public private(set) var applyTimes = Durations()
    /// Time between animation steps (1 / achieved frame rate).
    public private(set) var stepIntervals = Durations()

    public var onSettled: (() -> Void)?
    public var log: (String) -> Void = { print($0) }

    private var springs: [CGWindowID: AnimatedRect] = [:]
    private var timer: Timer?
    private var lastStep: CFTimeInterval = 0

    public init(area: CGRect, options: Options = Options()) {
        self.screenArea = area
        self.options = options
    }

    // MARK: Layout

    public func adopt(_ newWindows: [AXWindow]) {
        for window in newWindows where windows[window.windowID] == nil {
            let id = window.windowID
            windows[id] = window
            originalFrames[id] = window.frame
            measureLimits(of: window)
            if floatsByItself(window) { continue }
            layouts.assign(id, to: desk) { $0.insert(id) }
        }
        relayout()
    }

    /// Tiles a new window on the shown desktop. A point (usually the mouse)
    /// picks the tile to split, like a drop; otherwise the last tile is split.
    public func add(_ window: AXWindow, at point: CGPoint?) {
        let id = window.windowID
        guard windows[id] == nil else { return }
        windows[id] = window
        originalFrames[id] = window.frame
        measureLimits(of: window)
        if floatsByItself(window) {
            relayout()
            return
        }
        layouts.assign(id, to: desk) { tree in
            if let point {
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
        fullscreen = fullscreen.filter { $0.value != id }
        layouts.remove(id)
        relayout()
    }

    /// Dialogs, panels and windows that cannot be resized (or whose minimum
    /// and maximum size are the same) float where the app put them instead of
    /// taking a tile. Returns true when the window was made floating.
    private func floatsByItself(_ window: AXWindow) -> Bool {
        let id = window.windowID
        let fixed = minimums[id].flatMap { minimum in maximums[id].map { maximum in
            abs(minimum.width - maximum.width) < 2 && abs(minimum.height - maximum.height) < 2
        } } ?? false
        let reason: String
        if window.subrole != kAXStandardWindowSubrole {
            reason = window.subrole
        } else if !window.isResizable {
            reason = "not resizable"
        } else if fixed {
            reason = "fixed size"
        } else {
            return false
        }
        var frame = window.frame ?? defaultFloatFrame(for: id)
        // Keep it inside the usable area.
        frame.origin.x = min(max(frame.minX, area.minX), max(area.maxX - frame.width, area.minX))
        frame.origin.y = min(max(frame.minY, area.minY), max(area.maxY - frame.height, area.minY))
        floating[id] = Floating(desk: desk, frame: frame)
        log("floats by itself (\(reason)): \(window.title)")
        return true
    }

    /// Learns a new window's size limits up front (see `AXWindow.measureLimits`).
    private func measureLimits(of window: AXWindow) {
        guard let limits = window.measureLimits(largest: area.insetBy(dx: options.gaps.outer, dy: options.gaps.outer)) else {
            log("limits for \(window.title.isEmpty ? "\(window.windowID)" : window.title): app did not answer, learning later")
            return
        }
        let id = window.windowID
        minimums[id] = limits.minimum == .zero ? nil : limits.minimum
        maximums[id] = limits.maximum == .infinite ? nil : limits.maximum
        log("limits for \(window.title.isEmpty ? "\(id)" : window.title): min \(Self.describe(limits.minimum)) max \(Self.describe(limits.maximum)) (asked)")
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
        log("\(windows[id]?.title ?? "\(id)") moved to desktop \(target)")
        layouts.assign(id, to: target) { $0.insert(id) }
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

    public var isAnimating: Bool { timer != nil }

    /// The desk a window belongs to, tiled or floating.
    public func desk(of id: CGWindowID) -> Desk? {
        layouts.space(of: id) ?? floating[id]?.desk
    }

    /// Recomputes the layout and lets every window glide to its new tile.
    /// Windows not on the shown desktop are left alone.
    public func relayout() {
        layouts[desk].freezeDirections(in: area, gaps: options.gaps)
        let frames = targetFrames()
        let held = [dragging, resizing]
        for id in springs.keys where frames[id] == nil || held.contains(id) { springs[id] = nil }
        for (id, rect) in frames where !held.contains(id) {
            springs[id, default: AnimatedRect(windows[id]?.frame ?? rect)].target = rect
        }
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
        var frames = tree.layout(in: area, gaps: options.gaps, minimums: minimums, maximums: maximums)
        if let id = fullscreen[desk], frames[id] != nil {
            frames[id] = DwindleTree<CGWindowID>.centered(fullArea, maximum: maximums[id])
        }
        for (id, state) in floating where state.desk == desk {
            frames[id] = state.frame
        }
        // Windows of this desktop's other workspaces go (or stay) aside.
        var aside: [CGWindowID: Int] = [:]
        for (id, home) in layouts.spaceOf where home.space == space && home.workspace != workspace {
            aside[id] = home.workspace
        }
        for (id, state) in floating where state.desk.space == space && state.desk.workspace != workspace {
            aside[id] = state.desk.workspace
        }
        for (id, home) in aside where id != dragging {
            var frame = parked[id] ?? springs[id]?.current ?? windows[id]?.frame ?? fullArea
            frame.origin.x = home < workspace ? screenArea.minX - frame.width + 1 : screenArea.maxX - 1
            parked[id] = frame
            frames[id] = frame
        }
        parked = parked.filter { aside[$0.key] != nil }
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
        timer?.invalidate()
        timer = nil
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
            let frame = window.frame ?? state.frame
            layouts.assign(id, to: desk) { tree in
                tree.insert(id, at: CGPoint(x: frame.midX, y: frame.midY), in: area, gaps: options.gaps,
                            minimums: minimums, maximums: maximums)
            }
            log("tiled: \(window.title)")
        } else if tree.contains(id) {
            if fullscreen[desk] == id { fullscreen[desk] = nil }
            layouts.remove(id)
            floating[id] = Floating(desk: desk, frame: lastFloatFrame[id] ?? defaultFloatFrame(for: id))
            window.raise()
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
            window.raise()
            log("fullscreen: \(window.title)")
        }
        relayout()
    }

    // MARK: Drag and drop

    /// The user picked up `id`: it leaves the layout and the rest closes the gap.
    public func beginDrag(_ id: CGWindowID) {
        guard dragging == nil else { return }
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
            state.frame = windows[id]?.frame ?? state.frame
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
            springs[id] = AnimatedRect(window.frame ?? area)
        }
        log("drop: \(windows[id]?.title ?? "\(id)") at \(Int(point.x)),\(Int(point.y))")
        relayout()
    }

    // MARK: Resize by mouse

    /// The user grabbed an edge of `id`. From now on the window follows the
    /// mouse (macOS resizes it) and its neighbors follow the window.
    public func beginResize(_ id: CGWindowID) {
        guard dragging == nil, resizing == nil, tree.contains(id) || floating[id] != nil else { return }
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
            state.frame = windows[id]?.frame ?? state.frame
            floating[id] = state
            windows[id]?.invalidateCache()
            return
        }
        if let window = windows[id] {
            window.invalidateCache()
            springs[id] = AnimatedRect(window.frame ?? area)
        }
        log("resize end: \(windows[id]?.title ?? "\(id)")")
        relayout()
    }

    // MARK: Animation loop

    public func resetStats() {
        applyTimes = Durations()
        stepIntervals = Durations()
    }

    private func startLoop() {
        guard timer == nil else { return }
        lastStep = 0
        let timer = Timer(timeInterval: 1 / options.frameRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
            if options.resize == .smooth {
                spring.step(dt, response: options.response)
            } else {
                spring.stepResizingOnce(dt, response: options.response)
            }
            springs[id] = spring
            if let window = windows[id] { work.append((id, window, spring.current)) }
        }

        if !work.isEmpty {
            let start = CACurrentMediaTime()
            let gone = apply(work)
            applyTimes.add(CACurrentMediaTime() - start)
            for id in gone { forget(id) }
        }

        if springs.values.allSatisfy(\.isSettled) {
            timer?.invalidate()
            timer = nil
            onSettled?()
            scheduleFitCheck(retry: true)
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
            guard let window = windows[id], let actual = window.frame else { continue }
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
                window.setFrame(target)
            }
            scheduleFitCheck(retry: false)
        }
        if changed { relayout() }
    }

    private static func describe(_ size: CGSize) -> String {
        func side(_ v: CGFloat) -> String { v.isFinite ? "\(Int(v))" : "-" }
        return "\(side(size.width))x\(side(size.height))"
    }

    /// Writes frames; returns windows that no longer exist.
    private func apply(_ work: [(CGWindowID, AXWindow, CGRect)]) -> [CGWindowID] {
        if !options.parallel || work.count == 1 {
            return work.compactMap { $0.1.setFrame($0.2) ? nil : $0.0 }
        }
        let gone = Mutex<[CGWindowID]>([])
        DispatchQueue.concurrentPerform(iterations: work.count) { i in
            let (id, window, rect) = work[i]
            if !window.setFrame(rect) { gone.withLock { $0.append(id) } }
        }
        return gone.withLock { $0 }
    }

    private func forget(_ id: CGWindowID) {
        // A failed write can also mean a busy app; only drop windows that are really gone.
        guard windows[id]?.position == nil else { return }
        log("window gone: \(windows[id]?.title ?? "\(id)")")
        remove(id)
    }
}
