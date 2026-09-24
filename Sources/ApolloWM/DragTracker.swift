import AppKit

@MainActor
public final class DragTracker {
    private let engine: TilingEngine
    private var tap: CFMachPort?

    public var superFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    public var scrollPans = true
    public var scrollSpeed: CGFloat = 1.5
    public var invertScroll = false

    public var trace = ProcessInfo.processInfo.environment["APOLLOWM_TRACE"] == "1"

    private var downPoint: CGPoint?
    private var candidate: CGWindowID?
    private var startFrame: CGRect?

    private enum SuperGesture {
        case move(CGWindowID, grab: CGPoint, size: CGSize)
        case resize(CGWindowID, start: CGRect, mouse: CGPoint, left: Bool, top: Bool)
    }
    private var gesture: SuperGesture?

    public init(engine: TilingEngine) {
        self.engine = engine
    }

    private func note(_ message: @autoclosure () -> String) {
        if trace { FileHandle.standardError.write(Data((message() + "\n").utf8)) }
    }

    public func start() -> Bool {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseDragged, .rightMouseUp,
                                    .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
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

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
    }

    private func isSuper(_ flags: CGEventFlags) -> Bool {
        flags.intersection(superFlags) == superFlags
    }

    fileprivate func handle(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags,
                            scroll: CGVector = .zero) -> Bool {
        if type == .scrollWheel {
            guard scrollPans, engine.isCanvas, isSuper(flags) else { return false }
            let delta = abs(scroll.dx) > abs(scroll.dy) ? scroll.dx : scroll.dy
            engine.pan(by: (invertScroll ? delta : -delta) * scrollSpeed)
            return true
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            note("event tap was disabled (\(type.rawValue)), re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            gesture = nil
            candidate = nil
            downPoint = nil
            if engine.dragging != nil { engine.endDrag(at: point) }
            if engine.resizing != nil { engine.endResize() }
            return false
        }
        if handleSuper(type, at: point, flags: flags) { return true }
        handleTitleBar(type, at: point)
        return false
    }

    private func handleSuper(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags) -> Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown:
            guard gesture == nil, isSuper(flags), engine.dragging == nil, engine.resizing == nil,
                  let id = engine.window(at: point),
                  let window = engine.windows[id], let frame = window.serverFrame else { return false }
            engine.raise(id)
            if type == .leftMouseDown {
                gesture = .move(id, grab: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY), size: frame.size)
                note("super move: \(window.title)")
                engine.beginDrag(id)
            } else {
                gesture = .resize(id, start: frame, mouse: point, left: point.x < frame.midX, top: point.y < frame.midY)
                note("super resize: \(window.title)")
                engine.beginResize(id)
            }
            return true

        case .leftMouseDragged:
            guard case .move(let id, let grab, let size) = gesture else { return false }
            engine.write(id, CGRect(x: point.x - grab.x, y: point.y - grab.y,
                                    width: size.width, height: size.height))
            return true

        case .rightMouseDragged:
            guard case .resize(let id, let start, let mouse, let left, let top) = gesture else { return false }
            let dx = point.x - mouse.x, dy = point.y - mouse.y
            let minimum = engine.minimums[id] ?? .zero
            let minWidth = max(minimum.width, 60), minHeight = max(minimum.height, 40)
            var frame = start
            if left {
                let width = max(start.width - dx, minWidth)
                frame.origin.x = start.maxX - width
                frame.size.width = width
            } else {
                frame.size.width = max(start.width + dx, minWidth)
            }
            if top {
                let height = max(start.height - dy, minHeight)
                frame.origin.y = start.maxY - height
                frame.size.height = height
            } else {
                frame.size.height = max(start.height + dy, minHeight)
            }
            engine.write(id, frame)
            engine.updateResize(to: frame)
            return true

        case .leftMouseUp:
            guard case .move = gesture else { return false }
            gesture = nil
            engine.endDrag(at: point)
            return true

        case .rightMouseUp:
            guard case .resize = gesture else { return false }
            gesture = nil
            engine.endResize()
            return true

        default:
            return false
        }
    }

    private func handleTitleBar(_ type: CGEventType, at point: CGPoint) {
        switch type {
        case .leftMouseDown:
            downPoint = point
            candidate = engine.dragging == nil ? engine.window(at: point) : nil
            startFrame = candidate.flatMap { engine.windows[$0]?.serverFrame }
            note("down \(Int(point.x)),\(Int(point.y)) candidate \(candidate.map(String.init) ?? "none")")

        case .leftMouseDragged:
            if let id = engine.resizing {
                if let frame = engine.windows[id]?.serverFrame { engine.updateResize(to: frame) }
                return
            }
            guard let id = candidate else { return }
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
            if resized {
                note("  -> resize")
                candidate = nil
                engine.beginResize(id)
                engine.updateResize(to: actual)
            } else if moved {
                note("  -> pick up")
                candidate = nil
                engine.beginDrag(id)
            }

        case .leftMouseUp:
            note("up \(Int(point.x)),\(Int(point.y)) dragging \(engine.dragging.map(String.init) ?? "none")")
            if let id = candidate, let start = startFrame, let actual = engine.windows[id]?.serverFrame {
                if abs(actual.width - start.width) > 2 || abs(actual.height - start.height) > 2 {
                    note("  -> late resize")
                    engine.beginResize(id)
                    engine.updateResize(to: actual)
                } else if abs(actual.minX - start.minX) > 2 || abs(actual.minY - start.minY) > 2 {
                    note("  -> late move")
                    engine.beginDrag(id)
                }
            }
            if engine.dragging != nil { engine.endDrag(at: point) }
            if engine.resizing != nil { engine.endResize() }
            downPoint = nil
            candidate = nil
            startFrame = nil

        default:
            break
        }
    }
}

private let dragTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tracker = Unmanaged<DragTracker>.fromOpaque(refcon).takeUnretainedValue()
    let location = event.location
    let flags = event.flags
    let scroll = type == .scrollWheel
        ? CGVector(dx: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
                   dy: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        : .zero
    let swallow = MainActor.assumeIsolated {
        tracker.handle(type, at: location, flags: flags, scroll: scroll)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
