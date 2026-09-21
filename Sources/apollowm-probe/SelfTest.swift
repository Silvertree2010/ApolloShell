import AppKit
import ApolloWM

/// Stress test for a throwaway machine (the test VM): random steps (open,
/// close, float, fullscreen, workspace, drag, resize, mirror) with TextEdit
/// windows, and after each step, once everything has settled, checks that
///   - every tiled window is where the layout wants it (within 3 pt),
///   - no two tiled windows overlap,
///   - every tiled window lies inside the usable area.
/// Seeded, so a failure can be replayed with the same seed.
@MainActor
final class SelfTest {
    private let engine: TilingEngine
    private let watcher: WindowWatcher
    private var random: SeededRandom
    private let seed: UInt64
    private let steps: Int
    private var stepNumber = 0
    private var failures: [String] = []
    private var lastAction = "start"

    init(engine: TilingEngine, watcher: WindowWatcher, seed: UInt64, steps: Int) {
        self.engine = engine
        self.watcher = watcher
        self.seed = seed
        self.steps = steps
        random = SeededRandom(seed: seed)
    }

    func run() {
        print("selftest: seed \(seed), \(steps) steps")
        openWindow { self.openWindow { self.openWindow { self.settled { self.check(); self.next() } } } }
    }

    // MARK: Steps

    private func next() {
        stepNumber += 1
        guard stepNumber <= steps else { return finish() }
        let tiled = engine.tree.ids
        let managed = Array(engine.windows.keys).sorted()
        var actions: [(String, () -> Void)] = [("mirror", { self.engine.mirror() })]
        if managed.count < 6 { actions.append(("open", {})) }
        if managed.count > 1 { actions.append(("close", {})) }
        if !managed.isEmpty {
            actions.append(("float", { self.engine.toggleFloating(self.pick(managed)) }))
        }
        if !tiled.isEmpty {
            actions.append(("fullscreen", { self.engine.toggleFullscreen(self.pick(tiled)) }))
            actions.append(("drag", { self.drag(self.pick(tiled)) }))
            actions.append(("resize", { self.resize(self.pick(tiled)) }))
        }
        actions.append(("workspace", { self.workspaceRoundTrip() }))

        let (name, action) = actions[Int(random.next() % UInt64(actions.count))]
        lastAction = name
        switch name {
        case "open":
            openWindow { self.settled { self.check(); self.next() } }
        case "close":
            let id = pick(managed)
            lastAction = "close \(title(id))"
            engine.windows[id]?.close()
            settled { self.check(); self.next() }
        case "workspace":
            action()
        default:
            action()
            settled { self.check(); self.next() }
        }
    }

    private func drag(_ id: CGWindowID) {
        let area = engine.area
        let point = CGPoint(x: area.minX + CGFloat(random.unit()) * area.width,
                            y: area.minY + CGFloat(random.unit()) * area.height)
        lastAction = "drag \(title(id)) to \(Int(point.x)),\(Int(point.y))"
        engine.beginDrag(id)
        engine.endDrag(at: point)
    }

    private func resize(_ id: CGWindowID) {
        guard var frame = engine.windows[id]?.frame else { return }
        let delta = CGFloat(random.unit() * 400 - 200)
        if random.next() % 2 == 0 { frame.size.width += delta } else { frame.size.height += delta }
        lastAction = "resize \(title(id)) by \(Int(delta))"
        engine.beginResize(id)
        engine.write(id, frame)
        engine.updateResize(to: frame)
        engine.endResize()
    }

    /// Goes to workspace 2, checks, and comes back.
    private func workspaceRoundTrip() {
        let from = engine.workspace
        let to = from == 1 ? 2 : 1
        lastAction = "workspace \(from) -> \(to)"
        engine.switchWorkspace(to: to)
        settled {
            self.check()
            self.lastAction = "workspace \(to) -> \(from)"
            self.engine.switchWorkspace(to: from)
            self.settled { self.check(); self.next() }
        }
    }

    private func openWindow(then: @escaping () -> Void) {
        let before = engine.windows.count
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        script.arguments = ["-e", "tell application \"TextEdit\" to make new document",
                            "-e", "tell application \"TextEdit\" to activate"]
        try? script.run()
        lastAction = "open"
        // Wait until the watcher has picked the new window up.
        poll(until: { self.engine.windows.count > before }, timeout: 4) { found in
            if !found { self.fail("open: no new window picked up") }
            then()
        }
    }

    // MARK: Checks

    private func check() {
        let targets = engine.targetFrames()
        let tiled = engine.tree.ids
        var frames: [CGWindowID: CGRect] = [:]
        for id in tiled {
            guard let target = targets[id], let actual = engine.windows[id]?.frame else { continue }
            frames[id] = actual
            let off = max(abs(actual.minX - target.minX), abs(actual.minY - target.minY),
                          abs(actual.maxX - target.maxX), abs(actual.maxY - target.maxY))
            if off > 3 { fail("\(title(id)) is \(Int(off)) pt off its tile (target \(target), actual \(actual))") }
            if !engine.area.insetBy(dx: -1, dy: -1).contains(actual) {
                fail("\(title(id)) sticks out of the area (\(actual))")
            }
        }
        let ids = Array(frames.keys)
        for (i, a) in ids.enumerated() {
            for b in ids[(i + 1)...] {
                let overlap = frames[a]!.intersection(frames[b]!)
                if !overlap.isNull, overlap.width > 2, overlap.height > 2 {
                    fail("\(title(a)) and \(title(b)) overlap by \(Int(overlap.width))x\(Int(overlap.height))")
                }
            }
        }
    }

    private func fail(_ message: String) {
        let line = "step \(stepNumber) (\(lastAction)): \(message)"
        failures.append(line)
        print("FAIL " + line)
    }

    private func finish() {
        print("selftest done: \(steps) steps, \(failures.count) failures, dropped frames \(engine.droppedFrames)")
        engine.restoreAll()
        exit(failures.isEmpty ? 0 : 1)
    }

    // MARK: Helpers

    /// Waits until the glide, the snapshot swap and the fit check are over.
    private func settled(then: @escaping () -> Void) {
        poll(until: { !self.engine.isAnimating }, timeout: 5) { done in
            if !done { self.fail("still animating after 5 s") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { MainActor.assumeIsolated { then() } }
        }
    }

    private func poll(until condition: @escaping () -> Bool, timeout: TimeInterval,
                      then: @escaping (Bool) -> Void) {
        let deadline = CACurrentMediaTime() + timeout
        func check() {
            if condition() { return then(true) }
            if CACurrentMediaTime() > deadline { return then(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { MainActor.assumeIsolated { check() } }
        }
        check()
    }

    private func pick<T>(_ items: [T]) -> T { items[Int(random.next() % UInt64(items.count))] }

    private func title(_ id: CGWindowID) -> String {
        let title = engine.windows[id]?.title ?? ""
        return title.isEmpty ? "#\(id)" : "\(title) #\(id)"
    }
}

/// SplitMix64: small, fast, reproducible.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
