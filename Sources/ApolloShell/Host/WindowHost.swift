import AppKit
import SwiftUI
import ApolloConfig
import ApolloRuntime
import ApolloProviders

@MainActor
protocol WindowHostLink: AnyObject {
    func close(_ surfaceID: String)
    func surfaceDidFinishClosing(id: String, screenKey: String)
    func keyPressed(_ chord: String, surfaceID: String, screenKey: String) -> Bool
}

struct WindowHostStats: Equatable {
    var windowsCreated = 0
    var windowsClosed = 0
    var spaceChanges = 0
    var restyles = 0
}

@MainActor
final class SurfaceWindowController {
    let surface: SurfaceInstance
    let window: any HostWindow
    var spec: SurfaceWindowSpec
    var shown = false
    var wasOpen: Bool
    var insets = EdgeInsets()
    var openFrame: CGRect = .zero
    var timeout: DispatchWorkItem?

    init(surface: SurfaceInstance, window: any HostWindow, spec: SurfaceWindowSpec) {
        self.surface = surface
        self.window = window
        self.spec = spec
        wasOpen = surface.isOpen
    }
}

@MainActor
final class WindowHost: SurfaceHosting {
    let model = SurfaceHost()
    let factory: any HostWindowFactory
    let animators = AnimatorRegistry.builtin()
    let frames = SurfaceFrames()
    lazy var auxiliary = AuxiliaryWindows(factory: factory)
    var backgroundPainter: (any BackgroundPainter)?
    var makeTicker: (any HostWindow) -> (any FrameTicker)? = { window in
        (window as? AppKitHostWindow).map { DisplayLinkTicker(view: $0.container) }
    }
    var context: RenderContext?
    var screens: [String: ScreenGeometry] = [:]
    weak var link: (any WindowHostLink)?
    var log: (String) -> Void = { _ in }
    var onReservesChanged: ([PanelReserve]) -> Void = { _ in }
    private(set) var controllers: [String: SurfaceWindowController] = [:]
    private(set) var stats = WindowHostStats()
    private var reserves: [PanelReserve] = []
    private var spaceObserver: NSObjectProtocol?
    private weak var spaceCenter: NotificationCenter?
    var onSpaceChange: () -> Void = {}

    static let windowKinds: Set<String> = ["panel", "popup", "overlay", "toast", "osd", "window"]

    init(factory: any HostWindowFactory = AppKitWindowFactory()) {
        self.factory = factory
    }

    var windows: [String: any HostWindow] { controllers.mapValues(\.window) }

    func observeSpaces(_ center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        if let spaceObserver { spaceCenter?.removeObserver(spaceObserver) }
        spaceCenter = center
        spaceObserver = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanged() }
        }
    }

    func spaceChanged() {
        stats.spaceChanges += 1
        onSpaceChange()
    }

    func surfaceAdded(_ surface: SurfaceInstance) {
        model.surfaceAdded(surface)
        let key = SurfaceHost.key(surface.id, surface.screenKey)
        if controllers[key] == nil { build(surface) } else { sync(key) }
    }

    func surfaceChanged(_ surface: SurfaceInstance) {
        model.surfaceChanged(surface)
        sync(SurfaceHost.key(surface.id, surface.screenKey))
    }

    func surfaceReplaced(_ surface: SurfaceInstance) {
        model.surfaceReplaced(surface)
        let key = SurfaceHost.key(surface.id, surface.screenKey)
        tearDown(key)
        build(surface)
    }

    func surfaceRemoved(id: String, screenKey: String) {
        model.surfaceRemoved(id: id, screenKey: screenKey)
        tearDown(SurfaceHost.key(id, screenKey))
    }

    func restyle(_ context: RenderContext) {
        self.context = context
        stats.restyles += 1
        for (key, controller) in controllers {
            controller.window.setContent(content(controller.surface, insets: controller.insets))
            sync(key)
        }
    }

    func screensChanged(_ screens: [String: ScreenGeometry]) {
        guard !screens.isEmpty else { return }
        self.screens = screens
        for key in controllers.keys { sync(key) }
        auxiliary.sync(screens.values.sorted { $0.key < $1.key })
    }

    func resync() {
        for key in controllers.keys { sync(key) }
    }

    private func content(_ surface: SurfaceInstance, insets: EdgeInsets) -> AnyView {
        guard let context else { return AnyView(EmptyView()) }
        return AnyView(SurfaceView(surface: surface, context: context, insets: insets, painter: backgroundPainter))
    }

    private func build(_ surface: SurfaceInstance) {
        guard Self.windowKinds.contains(surface.ir.kind), context != nil else { return }
        let key = SurfaceHost.key(surface.id, surface.screenKey)
        let spec = SurfaceWindowSpec(surface: surface)
        let window = factory.make(spec: spec, content: content(surface, insets: EdgeInsets()))
        stats.windowsCreated += 1
        let controller = SurfaceWindowController(surface: surface, window: window, spec: spec)
        controller.wasOpen = false
        let id = surface.id, screenKey = surface.screenKey
        window.onCloseRequest = { [weak self] in self?.link?.close(id) }
        window.onKey = { [weak self] chord in self?.link?.keyPressed(chord, surfaceID: id, screenKey: screenKey) ?? false }
        controllers[key] = controller
        sync(key)
    }

    private func tearDown(_ key: String) {
        guard let controller = controllers.removeValue(forKey: key) else { return }
        controller.timeout?.cancel()
        controller.window.close()
        stats.windowsClosed += 1
        frames.publish(key, nil)
        updateReserves()
    }

    private func sync(_ key: String) {
        guard let controller = controllers[key], let context else { return }
        let surface = controller.surface
        let spec = SurfaceWindowSpec(surface: surface)
        if spec != controller.spec {
            controller.spec = spec
            controller.window.apply(spec)
        }
        guard let screen = screens[surface.screenKey] else {
            log("surface \(surface.id): no screen \(surface.screenKey)")
            return
        }
        let style = context.styles.resolve(StyleResolver.subject(for: surface), ancestors: [], parent: nil)
        let placement = SurfacePlacement(kind: surface.ir.kind, property: surface.property, style: style)
        let layout = SurfaceLayout.compute(placement: placement, spec: spec, radius: StyleValues.radius(style["border-radius"]), screen: screen, fitting: controller.window.fittingSize)
        if layout.insets != controller.insets {
            controller.insets = layout.insets
            controller.window.setContent(content(surface, insets: layout.insets))
        }
        controller.openFrame = layout.frame
        controller.window.setFrame(layout.frame)
        let opening = surface.isOpen && !controller.wasOpen
        let closing = !surface.isOpen && controller.wasOpen
        controller.wasOpen = surface.isOpen
        if surface.isVisible && !controller.shown {
            controller.shown = true
            present(controller, key: key, placement: placement, screen: screen, focus: opening)
        } else if !surface.isVisible && controller.shown {
            controller.shown = false
            dismiss(controller, key: key, placement: placement, screen: screen, closing: closing)
        } else if closing {
            finishClosing(controller, key: key)
        } else if controller.shown {
            frames.publish(key, layout.frame)
        }
        updateReserves()
    }

    private func geometry(_ controller: SurfaceWindowController, placement: SurfacePlacement, screen: ScreenGeometry) -> MotionGeometry {
        MotionGeometry(edge: MotionEdge(anchor: placement.anchor), size: controller.openFrame.size, topInset: max(0, screen.frame.maxY - screen.visible.maxY), flipped: false)
    }

    private func present(_ controller: SurfaceWindowController, key: String, placement: SurfacePlacement, screen: ScreenGeometry, focus: Bool) {
        let spec = controller.spec
        guard spec.animates else {
            controller.window.show(focus: focus)
            frames.publish(key, controller.openFrame)
            scheduleTimeout(controller)
            return
        }
        let animator = animators.animator(spec.motion)
        let geometry = geometry(controller, placement: placement, screen: screen)
        track(controller, key: key, animator: animator, geometry: geometry, opening: true)
        controller.window.animate(opening: true, animator: animator, geometry: geometry, scrim: spec.scrim, screen: screen.frame) {}
        scheduleTimeout(controller)
    }

    private func dismiss(_ controller: SurfaceWindowController, key: String, placement: SurfacePlacement, screen: ScreenGeometry, closing: Bool) {
        controller.timeout?.cancel()
        let spec = controller.spec
        guard spec.animates, closing else {
            controller.window.hide()
            frames.publish(key, nil)
            if closing { finishClosing(controller, key: key) }
            return
        }
        let animator = animators.animator(spec.motion)
        let geometry = geometry(controller, placement: placement, screen: screen)
        track(controller, key: key, animator: animator, geometry: geometry, opening: false)
        controller.window.animate(opening: false, animator: animator, geometry: geometry, scrim: spec.scrim, screen: screen.frame) { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.frames.publish(key, nil)
            self.finishClosing(controller, key: key)
        }
    }

    private func finishClosing(_ controller: SurfaceWindowController, key: String) {
        link?.surfaceDidFinishClosing(id: controller.surface.id, screenKey: controller.surface.screenKey)
    }

    private func track(_ controller: SurfaceWindowController, key: String, animator: any SurfaceAnimator, geometry: MotionGeometry, opening: Bool) {
        guard frames.hasObservers, let ticker = makeTicker(controller.window) else { return }
        let open = controller.openFrame
        let total = animator.duration(opening: opening)
        ticker.start { [weak self] elapsed in
            guard let self else { return false }
            let progress = animator.progress(at: elapsed, opening: opening)
            self.frames.publish(key, animator.visibleFrame(open: open, geometry: geometry, progress: progress))
            return elapsed < total && self.frames.hasObservers
        }
    }

    private func scheduleTimeout(_ controller: SurfaceWindowController) {
        controller.timeout?.cancel()
        guard let seconds = controller.spec.timeout else { return }
        let id = controller.surface.id
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.link?.close(id) }
        }
        controller.timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func updateReserves() {
        var next: [PanelReserve] = []
        for key in controllers.keys.sorted() {
            guard let controller = controllers[key], controller.spec.reserve, controller.shown else { continue }
            let frame = controller.openFrame
            let anchor = SurfacePlacement(kind: controller.surface.ir.kind, property: controller.surface.property, style: .init()).anchor
            switch anchor {
            case .left: next.append(PanelReserve(screen: controller.surface.screenKey, edge: .left, size: frame.width))
            case .right: next.append(PanelReserve(screen: controller.surface.screenKey, edge: .right, size: frame.width))
            case .top: next.append(PanelReserve(screen: controller.surface.screenKey, edge: .top, size: frame.height))
            case .bottom: next.append(PanelReserve(screen: controller.surface.screenKey, edge: .bottom, size: frame.height))
            default: break
            }
        }
        guard next != reserves else { return }
        reserves = next
        onReservesChanged(next)
    }
}

struct SurfaceLayout: Equatable {
    var frame: CGRect
    var insets: EdgeInsets

    static func compute(placement: SurfacePlacement, spec: SurfaceWindowSpec, radius: CGFloat, screen: ScreenGeometry, fitting: CGSize) -> SurfaceLayout {
        var frame = placement.frame(screen: screen.frame, visible: screen.visible, fitting: fitting)
        var insets = EdgeInsets()
        if spec.overhang, radius > 0 {
            let edges = placement.anchoredEdges
            if edges.contains(.left) { frame.origin.x -= radius; frame.size.width += radius; insets.leading += radius }
            if edges.contains(.right) { frame.size.width += radius; insets.trailing += radius }
            if edges.contains(.bottom) { frame.origin.y -= radius; frame.size.height += radius; insets.bottom += radius }
            if edges.contains(.top) { frame.size.height += radius; insets.top += radius }
        }
        if spec.safeArea {
            let menuBottom = screen.visible.maxY < screen.frame.maxY ? screen.visible.maxY : screen.frame.maxY
            let reach = frame.maxY - max(menuBottom, frame.minY)
            if reach > 0, frame.maxY > menuBottom { insets.top = max(insets.top, reach) }
        }
        return SurfaceLayout(frame: frame, insets: insets)
    }
}
