import ApolloWMCore
import AppKit
import Synchronization

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
    public private(set) var layouts = SpaceLayouts<SpaceID, CGWindowID>()
    /// The desktop currently shown on the main display.
    public private(set) var space: SpaceID = 0
    public private(set) var windows: [CGWindowID: AXWindow] = [:]
    public private(set) var dragging: CGWindowID?
    /// Sizes windows refused to go below, learned by measuring after each glide.
    public private(set) var minimums: [CGWindowID: CGSize] = [:]

    /// Layout of the shown desktop.
    public var tree: DwindleTree<CGWindowID> { layouts[space] }

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
            layouts.assign(id, to: space) { $0.insert(id) }
        }
        relayout()
    }

    /// Tiles a new window on `space` (default: the shown desktop). On the shown
    /// desktop a point (usually the mouse) picks the tile to split, like a
    /// drop; otherwise the last tile is split.
    public func add(_ window: AXWindow, at point: CGPoint?, space target: SpaceID? = nil) {
        let id = window.windowID
        guard windows[id] == nil else { return }
        windows[id] = window
        let target = target ?? space
        layouts.assign(id, to: target) { tree in
            if let point, target == space {
                tree.insert(id, at: point, in: area, gaps: options.gaps, minimums: minimums)
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
        layouts.remove(id)
        relayout()
    }

    /// The window now lives on another desktop (the user moved it there).
    public func move(_ id: CGWindowID, to target: SpaceID) {
        guard windows[id] != nil, id != dragging, layouts.space(of: id) != target else { return }
        log("\(windows[id]?.title ?? "\(id)") moved to desktop \(target)")
        layouts.assign(id, to: target) { $0.insert(id) }
        relayout()
    }

    /// The user switched desktops: arrange the windows shown there.
    public func switchSpace(to target: SpaceID) {
        guard target != space else { return }
        log("desktop \(space) -> \(target)")
        space = target
        // A drag cannot survive a desktop switch; the window stays where it is.
        if let id = dragging {
            dragging = nil
            layouts.assign(id, to: target) { $0.insert(id) }
        }
        relayout()
    }

    public var isAnimating: Bool { timer != nil }

    /// Recomputes the layout and lets every window glide to its new tile.
    /// Windows not on the shown desktop are left alone.
    public func relayout() {
        let frames = tree.layout(in: area, gaps: options.gaps, minimums: minimums)
        for id in springs.keys where frames[id] == nil { springs[id] = nil }
        for (id, rect) in frames {
            springs[id, default: AnimatedRect(windows[id]?.frame ?? rect)].target = rect
        }
        startLoop()
    }

    /// Reverses the window order. Used by the probe to force big moves.
    public func mirror() {
        let ids = tree.ids
        for id in ids { layouts.remove(id) }
        for id in ids.reversed() { layouts.assign(id, to: space) { $0.insert(id) } }
        relayout()
    }

    public func window(at point: CGPoint) -> CGWindowID? {
        tree.id(at: point, in: area, gaps: options.gaps, minimums: minimums)
    }

    /// Where the engine last put the window (nil while dragged or unknown).
    public func expectedFrame(of id: CGWindowID) -> CGRect? {
        springs[id]?.current
    }

    public func targetFrames() -> [CGWindowID: CGRect] {
        tree.layout(in: area, gaps: options.gaps, minimums: minimums)
    }

    // MARK: Drag and drop

    /// The user picked up `id`: it leaves the layout and the rest closes the gap.
    public func beginDrag(_ id: CGWindowID) {
        guard dragging == nil, tree.contains(id) else { return }
        dragging = id
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
        layouts.assign(id, to: space) { tree in
            tree.insert(id, at: point, in: area, gaps: options.gaps, minimums: minimums)
        }
        if let window = windows[id] {
            window.invalidateCache()
            springs[id] = AnimatedRect(window.frame ?? area)
        }
        log("drop: \(windows[id]?.title ?? "\(id)") at \(Int(point.x)),\(Int(point.y))")
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
            spring.step(dt, response: options.response)
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
            if learnMinimums() { relayout() }
        }
    }

    /// Compares where windows ended up with their tiles. A window that stayed
    /// bigger refused the size; remember that as its minimum.
    /// Returns true when a minimum grew, so the layout must be redone.
    private func learnMinimums() -> Bool {
        var changed = false
        for (id, target) in tree.layout(in: area, gaps: options.gaps, minimums: minimums) {
            guard id != dragging, let actual = windows[id]?.frame else { continue }
            var minimum = minimums[id] ?? .zero
            if actual.width > target.width + 4, actual.width > minimum.width + 1 {
                minimum.width = actual.width
            }
            if actual.height > target.height + 4, actual.height > minimum.height + 1 {
                minimum.height = actual.height
            }
            if minimum != (minimums[id] ?? .zero) {
                log("minimum for \(windows[id]?.title ?? "\(id)"): \(Int(minimum.width))x\(Int(minimum.height))")
                minimums[id] = minimum
                changed = true
            }
        }
        return changed
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
