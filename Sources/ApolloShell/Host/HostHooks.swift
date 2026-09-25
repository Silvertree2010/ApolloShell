import AppKit
import SwiftUI
import ApolloStyle
import ApolloRuntime

@MainActor
final class SurfaceFrames {
    typealias Observer = @MainActor (_ key: String, _ frame: CGRect) -> Void

    final class Token {
        fileprivate let id: Int
        fileprivate weak var owner: SurfaceFrames?

        fileprivate init(id: Int, owner: SurfaceFrames) {
            self.id = id
            self.owner = owner
        }

        @MainActor func cancel() {
            owner?.remove(id)
        }
    }

    private var observers: [Int: Observer] = [:]
    private var nextID = 0
    private(set) var frames: [String: CGRect] = [:]
    private(set) var published = 0

    var hasObservers: Bool { !observers.isEmpty }

    func observe(_ observer: @escaping Observer) -> Token {
        nextID += 1
        observers[nextID] = observer
        for (key, frame) in frames { observer(key, frame) }
        return Token(id: nextID, owner: self)
    }

    fileprivate func remove(_ id: Int) {
        observers[id] = nil
    }

    func publish(_ key: String, _ frame: CGRect?) {
        guard frames[key] != frame else { return }
        frames[key] = frame
        guard hasObservers else { return }
        published += 1
        for observer in observers.values { observer(key, frame ?? .null) }
    }
}

@MainActor
protocol FrameTicker: AnyObject {
    func start(_ tick: @escaping @MainActor (TimeInterval) -> Bool)
    func stop()
}

@MainActor
final class DisplayLinkTicker: NSObject, FrameTicker {
    private var link: CADisplayLink?
    private var tick: (@MainActor (TimeInterval) -> Bool)?
    private var started: CFTimeInterval = 0
    private weak var view: NSView?

    init(view: NSView) {
        self.view = view
    }

    func start(_ tick: @escaping @MainActor (TimeInterval) -> Bool) {
        link?.invalidate()
        self.tick = tick
        started = CACurrentMediaTime()
        guard let view else { return }
        let link = view.displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        tick = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let elapsed = link.targetTimestamp - started
        let going = MainActor.assumeIsolated { tick?(elapsed) ?? false }
        if !going {
            link.invalidate()
            self.link = nil
            tick = nil
        }
    }
}

enum BackgroundChoice {
    case standard
    case replaced(AnyView)
    case suppressed
}

@MainActor
protocol BackgroundPainter: AnyObject {
    func background(for surface: SurfaceInstance, style: ComputedStyle) -> BackgroundChoice
}

@MainActor
enum SurfaceBackground {
    static let properties = ["background", "background-color", "background-image", "box-shadow", "border", "border-color", "border-width", "-apollo-glass", "backdrop-filter"]

    static func resolve(_ painter: (any BackgroundPainter)?, surface: SurfaceInstance, style: ComputedStyle) -> (style: ComputedStyle, painted: AnyView?) {
        guard let painter else { return (style, nil) }
        switch painter.background(for: surface, style: style) {
        case .standard: return (style, nil)
        case .suppressed: return (stripped(style), nil)
        case .replaced(let view): return (stripped(style), view)
        }
    }

    static func stripped(_ style: ComputedStyle) -> ComputedStyle {
        var values = style.values
        for name in properties { values[name] = nil }
        return ComputedStyle(values: values)
    }
}

struct AuxiliaryWindowSpec: Equatable {
    var id: String
    var frame: CGRect
    var level: NSWindow.Level
}

@MainActor
protocol AuxiliaryWindowOwner: AnyObject {
    var ownerID: String { get }
    func windows(on screen: ScreenGeometry) -> [AuxiliaryWindowSpec]
    func content(for id: String, screen: ScreenGeometry) -> AnyView
}

struct ScreenGeometry: Equatable {
    var key: String
    var frame: CGRect
    var visible: CGRect
    var name: String?
    var notch = false
}

@MainActor
final class AuxiliaryWindows {
    private var owners: [any AuxiliaryWindowOwner] = []
    private(set) var windows: [String: any HostWindow] = [:]
    private(set) var created = 0
    private let factory: any HostWindowFactory

    init(factory: any HostWindowFactory) {
        self.factory = factory
    }

    func register(_ owner: any AuxiliaryWindowOwner, screens: [ScreenGeometry]) {
        owners.removeAll { $0.ownerID == owner.ownerID }
        owners.append(owner)
        sync(screens)
    }

    func unregister(_ ownerID: String, screens: [ScreenGeometry]) {
        owners.removeAll { $0.ownerID == ownerID }
        sync(screens)
    }

    func sync(_ screens: [ScreenGeometry]) {
        var wanted: Set<String> = []
        for owner in owners {
            for screen in screens {
                for spec in owner.windows(on: screen) {
                    let key = owner.ownerID + "/" + spec.id + "@" + screen.key
                    wanted.insert(key)
                    let window: any HostWindow
                    if let existing = windows[key] {
                        window = existing
                    } else {
                        window = factory.makeAuxiliary(content: owner.content(for: spec.id, screen: screen))
                        windows[key] = window
                        created += 1
                    }
                    window.setLevel(spec.level)
                    window.setFrame(spec.frame)
                    window.show(focus: false)
                }
            }
        }
        for (key, window) in windows where !wanted.contains(key) {
            window.close()
            windows[key] = nil
        }
    }
}
