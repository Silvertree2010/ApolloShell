import AppKit
import ApolloWM

// Measurement tool for the drag-and-glide spike.
//
//   apollowm-probe bench [--max N] [--serial]
//       Tiles the windows on the main display, animates big layout changes,
//       prints frame rate and write cost, checks where windows really ended up,
//       then puts every window back where it was.
//   apollowm-probe run [--max N] [--serial]
//       Tiles and stays live: pick up a window by its title bar and the others
//       close the gap; drop it and everything glides into place. Ctrl+C restores.

setvbuf(stdout, nil, _IOLBF, 0)
let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? ""
func option(_ name: String) -> String? {
    args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
}

guard mode == "bench" || mode == "run" else {
    print("usage: apollowm-probe bench|run [--max N] [--serial]")
    exit(2)
}
guard WindowDiscovery.isTrusted(prompt: true) else {
    print("Accessibility access missing. Allow your terminal in System Settings > Privacy & Security > Accessibility, then run again.")
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

guard let area = WindowDiscovery.mainArea() else { print("no display"); exit(1) }
var found = WindowDiscovery.tileableWindows(in: area)
if let max = option("--max").flatMap(Int.init) { found = Array(found.prefix(max)) }
guard !found.isEmpty else { print("no windows to tile on the main display"); exit(1) }

print("area \(area)")
for w in found {
    // App frame and window-server frame must agree, or drag detection is blind.
    let app = w.frame.map { "\(Int($0.minX)),\(Int($0.minY))" } ?? "-"
    let server = w.serverFrame.map { "\(Int($0.minX)),\(Int($0.minY))" } ?? "-"
    print("  tile: [\(w.pid)] \(w.title.isEmpty ? "(untitled)" : w.title)  app \(app) server \(server)")
}

let originals = found.map { ($0, $0.frame) }
let enhancedUI = EnhancedUIGuard()
enhancedUI.disable(for: Set(found.map(\.pid)))

@MainActor func restoreAndExit(_ code: Int32) -> Never {
    for (window, frame) in originals {
        guard let frame else { continue }
        window.invalidateCache()
        window.setFrame(frame)
    }
    enhancedUI.restore()
    print("restored \(originals.count) windows")
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
options.parallel = !args.contains("--serial")
let engine = TilingEngine(area: area, options: options)

@MainActor func report(_ label: String) {
    let fps = engine.stepIntervals.median.map { String(format: "%.0f fps", 1 / $0) } ?? "-"
    print("\(label): \(fps) | step interval \(engine.stepIntervals.summary) | frame writes \(engine.applyTimes.summary)")
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
        ("serial   tile",   { engine.options.parallel = false }),
        ("serial   mirror", { engine.mirror() }),
        ("serial   mirror", { engine.mirror() }),
        ("parallel mirror", { engine.options.parallel = true; engine.mirror() }),
        ("parallel mirror", { engine.mirror() }),
    ]
    var current = "serial   tile"
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
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
        MainActor.assumeIsolated {
            print("bench did not finish in 30s")
            restoreAndExit(1)
        }
    }

default:
    let tracker = DragTracker(engine: engine)
    guard tracker.start() else {
        print("could not watch the mouse (event tap refused)")
        restoreAndExit(1)
    }
    engine.onSettled = { report("settled") }
    engine.adopt(found)
    print("live. drag a window by its title bar. Ctrl+C puts everything back.")
    withExtendedLifetime((tracker, signalSources)) { app.run() }
}

withExtendedLifetime(signalSources) { app.run() }
