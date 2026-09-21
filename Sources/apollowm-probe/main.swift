import AppKit
import ApolloWM

// Measurement tool for the drag-and-glide spike.
//
//   apollowm-probe bench [--max N]
//       Tiles the windows on the main display, animates big layout changes,
//       prints frame rate and write cost, checks where windows really ended up,
//       then puts every window back where it was.
//   apollowm-probe selftest [--seed N] [--steps N]
//       For the test VM only: random steps with TextEdit windows, checking
//       after each that windows sit on their tiles and never overlap.
//   apollowm-probe spaces
//       Read-only: prints the shown desktop and the desktop of every window.
//   apollowm-probe run [--max N]
//       Tiles and stays live: pick up a window by its title bar and the others
//       close the gap; drop it and everything glides into place. Ctrl+C restores.

setvbuf(stdout, nil, _IOLBF, 0)
let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? ""
func option(_ name: String) -> String? {
    args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
}

guard ["bench", "run", "spaces", "selftest"].contains(mode) else {
    print("usage: apollowm-probe bench|run|spaces|selftest [--max N] [--seed N] [--steps N] [--resize proxy|smooth|snap] [--no-focus-follows-mouse] [--reserve-left PT]")
    exit(2)
}

// Read-only: which desktop is shown and where every normal window lives.
if mode == "spaces" {
    print("shown desktop: \(Spaces.current().map(String.init) ?? "unknown")")
    let infos = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for info in infos where (info[kCGWindowLayer as String] as? Int) == 0 {
        guard let id = info[kCGWindowNumber as String] as? CGWindowID,
              let owner = info[kCGWindowOwnerName as String] as? String else { continue }
        let onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) == true
        let space = Spaces.of(id).map(String.init) ?? "none/all"
        print("  \(owner) #\(id) desktop \(space)\(onScreen ? " (on screen)" : "")")
    }
    exit(0)
}
guard WindowDiscovery.isTrusted(prompt: true) else {
    print("Accessibility access missing. Allow your terminal in System Settings > Privacy & Security > Accessibility, then run again.")
    exit(1)
}

if WindowDiscovery.isStageManagerOn {
    print("warning: Stage Manager is on. It moves windows on every app switch and fights tiling.")
}

// Trace: a background thread pings the main thread every 5 ms and reports
// when it answers late, to tell a blocked main thread from a slow ticker.
if ProcessInfo.processInfo.environment["APOLLOWM_TRACE"] == "1" {
    Thread.detachNewThread {
        while true {
            let sent = CACurrentMediaTime()
            let answered = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { answered.signal() }
            answered.wait()
            let late = (CACurrentMediaTime() - sent) * 1000
            if late > 25 { FileHandle.standardError.write(Data(String(format: "main thread blocked %.0f ms\n", late).utf8)) }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
}

let app = NSApplication.shared
// Accessory, not prohibited: proxy glides show our own snapshot windows.
app.setActivationPolicy(.accessory)

guard let area = WindowDiscovery.mainArea() else { print("no display"); exit(1) }
var found = WindowDiscovery.tileableWindows(in: area)
if let max = option("--max").flatMap(Int.init) { found = Array(found.prefix(max)) }
// Bench needs windows; run mode starts empty and picks windows up as they appear.
guard !found.isEmpty || mode == "run" || mode == "selftest" else { print("no windows to tile on the main display"); exit(1) }

print("area \(area)")
for w in found {
    // App frame and window-server frame must agree, or drag detection is blind.
    let app = w.frame.map { "\(Int($0.minX)),\(Int($0.minY))" } ?? "-"
    let server = w.serverFrame.map { "\(Int($0.minX)),\(Int($0.minY))" } ?? "-"
    let space = Spaces.of(w.windowID).map(String.init) ?? "-"
    print("  tile: [\(w.pid)] \(w.title.isEmpty ? "(untitled)" : w.title)  app \(app) server \(server) desktop \(space)")
}

let enhancedUI = EnhancedUIGuard()
enhancedUI.disable(for: Set(found.map(\.pid)))

/// Set once the engine exists; puts every managed window back.
var restoreWindows: (() -> Void)?

@MainActor func restoreAndExit(_ code: Int32) -> Never {
    restoreWindows?()
    enhancedUI.restore()
    print("restored all windows")
    exit(code)
}

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let signalSources = [SIGINT, SIGTERM].map { sig in
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { MainActor.assumeIsolated { restoreAndExit(0) } }
    source.resume()
    return source
}

var options = TilingEngine.Options()
options.resize = option("--resize").flatMap(ResizeAnimation.init(rawValue:)) ?? .proxy
if options.resize == .proxy && !CGPreflightScreenCaptureAccess() {
    print("Screen Recording not allowed: proxy glides fall back to smooth. Asking macOS for it.")
    CGRequestScreenCaptureAccess()
}
// ApolloShell's sidebar sits on the left edge, 44 pt wide.
options.reserved.left = option("--reserve-left").flatMap(Double.init).map { CGFloat($0) } ?? 44
let engine = TilingEngine(area: area, options: options)

// The arrangement survives restarts: loaded before adopting, saved after
// every glide and on quit.
let layoutFile = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ApolloWM/probe-layout.json")
@MainActor func saveLayout(now: Bool = false) {
    guard let data = try? JSONEncoder().encode(engine.snapshot()) else { return }
    // Writing syncs to disk (fsync); off the main thread except on quit.
    let write = { @Sendable in
        try? FileManager.default.createDirectory(at: layoutFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: layoutFile, options: .atomic)
    }
    if now { write() } else { DispatchQueue.global(qos: .utility).async(execute: write) }
}
if mode == "run", let data = try? Data(contentsOf: layoutFile),
   let snapshot = try? JSONDecoder().decode(TilingEngine.Snapshot.self, from: data) {
    let existing = Set((CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
        .compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
    engine.restore(snapshot, alive: { existing.contains($0) })
}
restoreWindows = {
    if mode == "run" { saveLayout(now: true) }
    engine.restoreAll()
}
if let space = Spaces.current() {
    print("shown desktop \(space)")
    engine.switchSpace(to: space)
}

@MainActor func report(_ label: String) {
    let fps = engine.stepIntervals.median.map { String(format: "%.0f fps", 1 / $0) } ?? "-"
    print("\(label): \(fps) | proxies \(engine.proxyGlides) | step interval \(engine.stepIntervals.summary) | main thread per frame \(engine.applyTimes.summary) | dropped \(engine.droppedFrames)")
    engine.resetStats()
}

/// Largest distance between where a window should be and where it is.
@MainActor func verify() {
    for (id, target) in engine.targetFrames() {
        guard let window = engine.windows[id] else { continue }
        guard let actual = window.frame else { print("  verify: \(window.title) unreadable"); continue }
        let dx = max(abs(actual.minX - target.minX), abs(actual.maxX - target.maxX))
        let dy = max(abs(actual.minY - target.minY), abs(actual.maxY - target.maxY))
        let off = max(dx, dy)
        print("  verify: \(window.title.isEmpty ? "(untitled)" : window.title) off by \(Int(off.rounded()))pt\(off > 2 ? "  <-- app refused the frame (min size?)" : "")")
    }
}

switch mode {
case "bench":
    var steps: [(String, () -> Void)] = [
        ("tile",   {}),
        ("mirror", { engine.mirror() }),
        ("mirror", { engine.mirror() }),
        ("mirror", { engine.mirror() }),
        ("mirror", { engine.mirror() }),
    ]
    var current = "tile"
    steps.removeFirst().1()
    engine.onSettled = {
        report(current)
        guard !steps.isEmpty else {
            verify()
            restoreAndExit(0)
        }
        let next = steps.removeFirst()
        current = next.0
        // Short pause so each animation starts from rest.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { next.1() } }
    }
    engine.adopt(found)
    engine.startSnapshots(every: 0.5)
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
        MainActor.assumeIsolated {
            print("bench did not finish in 30s")
            restoreAndExit(1)
        }
    }

case "selftest":
    engine.adopt(found)
    let watcher = WindowWatcher(engine: engine)
    watcher.start()
    let test = SelfTest(engine: engine, watcher: watcher,
                        seed: option("--seed").flatMap(UInt64.init) ?? UInt64(Date().timeIntervalSince1970),
                        steps: option("--steps").flatMap(Int.init) ?? 60)
    test.run()
    withExtendedLifetime((watcher, test, signalSources)) { app.run() }

default:
    let tracker = DragTracker(engine: engine)
    guard tracker.start() else {
        print("could not watch the mouse (event tap refused)")
        restoreAndExit(1)
    }
    engine.onSettled = {
        report("settled")
        saveLayout()
    }
    engine.adopt(found)
    engine.startSnapshots()
    let watcher = WindowWatcher(engine: engine)
    watcher.start()
    let keys = KeyBindings(engine: engine)
    if !keys.start() { print("could not watch the keyboard (event tap refused)") }
    let focus = FocusFollowsMouse(engine: engine)
    focus.isEnabled = !args.contains("--no-focus-follows-mouse")
    if !focus.start() { print("could not follow the mouse (event tap refused)") }
    print("live. drag a window by its title bar, or hold fn (Super) and drag anywhere.")
    print("fn+space floats, fn+F fills the area, fn+1..9 switches workspace. Ctrl+C puts everything back.")
    withExtendedLifetime((tracker, watcher, keys, focus, signalSources)) { app.run() }
}

withExtendedLifetime(signalSources) { app.run() }
