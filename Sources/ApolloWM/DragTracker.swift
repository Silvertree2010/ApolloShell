import AppKit

/// Watches the mouse (listen-only, never blocks or alters events) and turns
/// a title-bar drag of a tiled window into `beginDrag` / `endDrag`.
///
/// macOS moves the window itself while the user drags; we only notice that
/// the window left the spot we put it in, with its size unchanged. A drag
/// that changes the size is an edge resize and is ignored for now.
@MainActor
public final class DragTracker {
    private let engine: TilingEngine
    private var tap: CFMachPort?

    private var downPoint: CGPoint?
    private var candidate: CGWindowID?
    /// The candidate's frame at mouse-down. Compared against this, not the
    /// layout target, since apps may refuse a target size (minimum sizes).
    private var startFrame: CGRect?

    /// Prints every decision to stderr (set APOLLOWM_TRACE=1).
    public var trace = ProcessInfo.processInfo.environment["APOLLOWM_TRACE"] == "1"

    private func note(_ message: @autoclosure () -> String) {
        if trace { FileHandle.standardError.write(Data((message() + "\n").utf8)) }
    }

    public init(engine: TilingEngine) {
        self.engine = engine
    }

    /// Returns false when the event tap cannot be created (missing permission).
    public func start() -> Bool {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: mask,
                                          callback: dragTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func handle(_ type: CGEventType, at point: CGPoint) {
        switch type {
        case .leftMouseDown:
            downPoint = point
            candidate = engine.dragging == nil ? engine.window(at: point) : nil
            startFrame = candidate.flatMap { engine.windows[$0]?.serverFrame }
            note("down \(Int(point.x)),\(Int(point.y)) candidate \(candidate.map(String.init) ?? "none")")

        case .leftMouseDragged:
            guard let id = candidate else { return }
            guard let downPoint else { return }
            guard let window = engine.windows[id], let start = startFrame else {
                note("  -> candidate \(id) no longer tiled")
                candidate = nil
                return
            }
            guard let actual = window.serverFrame else {
                note("  -> window server has no frame for \(id)")
                candidate = nil
                return
            }
            let moved = abs(actual.minX - start.minX) > 2 || abs(actual.minY - start.minY) > 2
            let resized = abs(actual.width - start.width) > 2 || abs(actual.height - start.height) > 2
            note("drag \(Int(point.x)),\(Int(point.y)) now \(Int(actual.minX)),\(Int(actual.minY)) \(Int(actual.width))x\(Int(actual.height)) app \(window.frame.map { "\(Int($0.minX)),\(Int($0.minY))" } ?? "-") at down \(Int(start.minX)),\(Int(start.minY)) \(Int(start.width))x\(Int(start.height))")
            if resized {
                note("  -> resize, ignored")
                candidate = nil
            } else if moved {
                candidate = nil
                note("  -> pick up")
                engine.beginDrag(id)
            } else if hypot(point.x - downPoint.x, point.y - downPoint.y) > 40 {
                // Mouse travelled but the window stayed: text selection etc.
                note("  -> window did not follow, gave up")
                candidate = nil
            }

        case .leftMouseUp:
            note("up \(Int(point.x)),\(Int(point.y)) dragging \(engine.dragging.map(String.init) ?? "none")")
            if engine.dragging != nil { engine.endDrag(at: point) }
            downPoint = nil
            candidate = nil
            startFrame = nil

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        default:
            break
        }
    }
}

private let dragTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    if let refcon {
        let tracker = Unmanaged<DragTracker>.fromOpaque(refcon).takeUnretainedValue()
        let location = event.location
        MainActor.assumeIsolated { tracker.handle(type, at: location) }
    }
    return Unmanaged.passUnretained(event)
}
