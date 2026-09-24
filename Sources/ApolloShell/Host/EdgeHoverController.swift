import AppKit
import ApolloShellCore

@MainActor
final class EdgeHoverController {
    struct Target: Equatable {
        var key: String
        var surfaceID: String
        var screenKey: String
        var anchor: SurfacePlacement.Anchor
        var frame: CGRect
        var screen: CGRect
        var margin: CGFloat
        var gap: CGFloat
        var isOpen: Bool
    }

    static let interval: TimeInterval = 0.05

    var targets: @MainActor () -> [Target] = { [] }
    var pointer: @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    var isFullscreen: @MainActor (String) -> Bool = { _ in false }
    var open: @MainActor (String, String) -> Void = { _, _ in }
    var close: @MainActor (String) -> Void = { _ in }
    var makeTimer: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Timer? = { interval, tick in
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
    }
    private(set) var states: [String: EdgeHoverState] = [:]
    private var timer: Timer?
    private(set) var running = false

    func refresh() {
        let wanted = !targets().isEmpty
        guard wanted != running else { return }
        running = wanted
        timer?.invalidate()
        timer = nil
        if wanted {
            timer = makeTimer(Self.interval) { [weak self] in self?.tick() }
        } else {
            states = [:]
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        running = false
        states = [:]
    }

    func tick() {
        let list = targets()
        let point = pointer()
        let keys = Set(list.map(\.key))
        states = states.filter { keys.contains($0.key) }
        for target in list {
            var state = states[target.key] ?? .hidden
            if !target.isOpen && state.visible { state = .hidden }
            let inOpen = Self.area(target, open: true).contains(point)
            if target.isOpen && !state.visible {
                states[target.key] = .openedByShortcut(mouseInArea: inOpen)
                continue
            }
            let inArea = state.visible ? inOpen : (!isFullscreen(target.screenKey) && Self.area(target, open: false).contains(point))
            let next = state.moved(inArea: inArea)
            states[target.key] = next
            if next.visible && !state.visible {
                open(target.surfaceID, target.screenKey)
            } else if !next.visible && state.visible {
                close(target.surfaceID)
            }
        }
    }

    static func area(_ target: Target, open: Bool) -> CGRect {
        let thickness = EdgeHoverArea.edgeThickness
        let screen = target.screen
        let frame = target.frame
        let strip: CGRect
        switch target.anchor {
        case .left:
            strip = CGRect(x: screen.minX - thickness, y: frame.minY, width: 2 * thickness, height: frame.height)
        case .right:
            strip = CGRect(x: screen.maxX - thickness, y: frame.minY, width: 2 * thickness, height: frame.height)
        case .top, .topLeft, .topRight, .bottom, .bottomLeft, .bottomRight:
            var minX = frame.minX
            var maxX = frame.maxX
            if [.topLeft, .bottomLeft].contains(target.anchor) { minX = max(minX, screen.minX + target.gap) }
            if [.topRight, .bottomRight].contains(target.anchor) { maxX = min(maxX, screen.maxX - target.gap) }
            let top = [.top, .topLeft, .topRight].contains(target.anchor)
            let y = top ? screen.maxY - thickness : screen.minY - thickness
            strip = CGRect(x: minX, y: y, width: max(0, maxX - minX), height: 2 * thickness)
        case .center, .fill:
            return .null
        }
        guard open else { return strip }
        return frame.insetBy(dx: -target.margin, dy: -target.margin).union(strip)
    }
}
