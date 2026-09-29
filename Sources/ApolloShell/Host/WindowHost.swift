import AppKit
import SwiftUI
import ApolloConfig
import ApolloRuntime
import ApolloProviders
import ApolloShellCore
import ApolloStyle

@MainActor
protocol WindowHostLink: AnyObject {
    func close(_ surfaceID: String, screenKey: String)
    func surfaceDidFinishOpening(id: String, screenKey: String)
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
    var hovered = false
    var ticker: (any FrameTicker)?
    var placed = false
    var offset: CGPoint?
    var observing = false
    var fitPending = false
    var remeasurePending = false
    var lastFitting: CGSize?
    var flyout = EdgeInsets()
    var pendingContent: AnyView?
    var flyoutShrink: DispatchWorkItem?

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
    let fusion = FusionCoordinator()
    private var fusionToken: SurfaceFrames.Token?
    private var fusionRegistered = false
    var makeTicker: (any HostWindow) -> (any FrameTicker)? = { window in
        (window as? AppKitHostWindow).map { DisplayLinkTicker(view: $0.container) }
    }
    var context: RenderContext? {
        didSet {
            context?.hits.onChange = { [weak self] _ in self?.pointerMoved() }
            context?.onFlyoutExtent = { [weak self] key, extent in self?.flyoutExtent(key, extent) }
            context?.elementFrames.onChange = { [weak self] key in self?.syncAttached(to: key) }
            context?.onFlyoutBulges = { [weak self] key, bulges in self?.flyoutBulges(key, bulges) }
            fusion.context = context
            updateFusion()
        }
    }
    var screens: [String: ScreenGeometry] = [:]
    weak var link: (any WindowHostLink)?
    var log: (String) -> Void = { _ in }
    var onReservesChanged: ([PanelReserve]) -> Void = { _ in }
    var publishSize: @MainActor (String, String, CGSize) -> Void = { _, _, _ in }
    private(set) var controllers: [String: SurfaceWindowController] = [:]
    private(set) var stats = WindowHostStats()
    private var reserves: [PanelReserve] = []
    private var spaceObserver: NSObjectProtocol?
    private weak var spaceCenter: NotificationCenter?
    var onSpaceChange: () -> Void = {}
    var pointer: @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    var scheduleTimer: @MainActor (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    var onOpenChanged: @MainActor () -> Void = {}
    var afterLayout: @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { MainActor.assumeIsolated { work() } }
    }
    var later: @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
        DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
    }
    static let hoverPoll: TimeInterval = 0.25
    static let flyoutShrinkDelay: TimeInterval = 0.5
    var watchPointer: @MainActor (@escaping @MainActor () -> Void) -> (@MainActor () -> Void) = PointerWatch.live
    private var stopPointer: (@MainActor () -> Void)?
    private var attachSyncing: Set<String> = []

    static let windowKinds: Set<String> = ["panel", "popup", "overlay", "toast", "osd", "window"]

    init(factory: any HostWindowFactory = AppKitWindowFactory()) {
        self.factory = factory
        animators.register(JellyAnimator(springs: { [weak self] in self?.fusion.settings.springs }))
        fusion.member = { [weak self] key in self?.fusionMember(key) }
        fusion.fillStyle = { [weak self] screen in self?.fusionFill(screen) ?? ComputedStyle(values: [:]) }
        fusion.makeTicker = { [weak self] screen in
            guard let self, let window = self.auxiliary.windows["fusion/skin@" + screen] else { return nil }
            return self.makeTicker(window)
        }
    }

    var painter: (any BackgroundPainter)? {
        backgroundPainter ?? (fusionRegistered ? fusion : nil)
    }

    private var hasFusionMembers: Bool {
        controllers.values.contains { !FusionCoordinator.groupName($0.surface).isEmpty }
    }

    func updateFusion() {
        let next = context.map { FusionSettings(tokens: $0.styles.environment.tokens, reduceMotion: $0.styles.environment.reduceMotion) } ?? .standard
        fusion.apply(next)
        let wanted = next.isOn && hasFusionMembers && context != nil
        guard wanted != fusionRegistered else { return }
        fusionRegistered = wanted
        let geometries = screens.values.sorted { $0.key < $1.key }
        if wanted {
            fusion.screensChanged(screens)
            fusionToken = frames.observe { [weak self] key, frame in self?.fusion.frameChanged(key, frame) }
            auxiliary.register(fusion, screens: geometries)
        } else {
            fusionToken?.cancel()
            fusionToken = nil
            auxiliary.unregister(fusion.ownerID, screens: geometries)
        }
        for (key, controller) in controllers {
            controller.window.setContent(content(controller.surface, insets: controller.insets, flyout: controller.flyout))
            sync(key)
        }
    }

    func fusionMember(_ key: String) -> FusionMember? {
        guard let controller = controllers[key], let context else { return nil }
        let surface = controller.surface
        let group = FusionCoordinator.groupName(surface)
        guard !group.isEmpty else { return nil }
        let style = context.styles.resolve(surface: surface)
        let radius = style.customProperties["--fuse-radius"].flatMap { Double($0.replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespaces)) }.map { CGFloat($0) }
            ?? StyleValues.radius(style["border-radius"])
        let order = controllers.keys.sorted().firstIndex(of: key) ?? 0
        return FusionMember(group: group, fill: surface.property("fuse-fill").isTruthy, screenKey: surface.screenKey,
                            side: FusionCoordinator.side(anchor: surface.property("anchor").plainText), radius: radius,
                            calm: controller.spec.kind == "panel", level: controller.spec.level, order: order)
    }

    func fusionFill(_ screen: String) -> ComputedStyle {
        guard let context else { return ComputedStyle(values: [:]) }
        let members = controllers.keys.sorted().compactMap { key -> (String, FusionMember)? in
            guard let member = fusionMember(key), member.screenKey == screen else { return nil }
            return (key, member)
        }
        guard let chosen = members.first(where: { $0.1.fill }) ?? members.first, let controller = controllers[chosen.0] else { return ComputedStyle(values: [:]) }
        let style = context.styles.resolve(surface: controller.surface)
        return ComputedStyle(values: style.values.filter { SurfaceBackground.properties.contains($0.key) })
    }

    func flyoutBulges(_ key: String, _ bulges: [FlyoutBulge]) {
        guard fusionRegistered, let controller = controllers[key], controller.shown else { return }
        let open = controller.openFrame
        let pieces = bulges.filter { $0.open && $0.joined && $0.rect.width > 0.5 && $0.rect.height > 0.5 }.map { bulge in
            (key: bulge.key, rect: CGRect(x: open.minX + bulge.rect.minX, y: open.maxY - bulge.rect.maxY, width: bulge.rect.width, height: bulge.rect.height),
             radius: bulge.radius, side: FusionCoordinator.side(bulge.side))
        }
        fusion.flyouts(key, pieces)
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
        let key = SurfaceHost.key(surface.id, surface.screenKey)
        if controllers[key] == nil { build(surface) } else { sync(key) }
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
        let wasOn = fusionRegistered
        for (key, controller) in controllers {
            controller.window.setContent(content(controller.surface, insets: controller.insets, flyout: controller.flyout))
            sync(key)
        }
        if wasOn, fusionRegistered { auxiliary.sync(screens.values.sorted { $0.key < $1.key }) }
    }

    func screensChanged(_ screens: [String: ScreenGeometry]) {
        guard !screens.isEmpty else { return }
        self.screens = screens
        if fusionRegistered { fusion.screensChanged(screens) }
        for key in controllers.keys { sync(key) }
        auxiliary.sync(screens.values.sorted { $0.key < $1.key })
    }

    func resync() {
        for key in controllers.keys { sync(key) }
    }

    private func content(_ surface: SurfaceInstance, insets: EdgeInsets, flyout: EdgeInsets = EdgeInsets()) -> AnyView {
        guard let context else { return AnyView(EmptyView()) }
        let occluded = context.occluded.contains(SurfaceHost.key(surface.id, surface.screenKey))
        let view = SurfaceView(surface: surface, context: context, insets: insets, painter: painter, occluded: occluded).padding(flyout)
        guard surface.ir.kind != "window" else { return AnyView(view) }
        let style = context.styles.resolve(surface: surface)
        let anchor = SurfacePlacement(kind: surface.ir.kind, property: surface.property, style: style).anchor
        return AnyView(view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(anchor)))
    }

    static func alignment(_ anchor: SurfacePlacement.Anchor) -> Alignment {
        switch anchor {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        case .center, .fill: .center
        }
    }

    func flyoutExtent(_ key: String, _ extent: EdgeInsets) {
        guard let controller = controllers[key], controller.spec.kind != "window" else { return }
        controller.flyoutShrink?.cancel()
        controller.flyoutShrink = nil
        let current = controller.flyout
        if extent.top >= current.top, extent.bottom >= current.bottom, extent.leading >= current.leading, extent.trailing >= current.trailing {
            applyFlyout(key, extent)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.applyFlyout(key, extent) }
        }
        controller.flyoutShrink = work
        scheduleTimer(Self.flyoutShrinkDelay, work)
    }

    private func applyFlyout(_ key: String, _ extent: EdgeInsets) {
        guard let controller = controllers[key], controller.flyout != extent else { return }
        controller.flyout = extent
        controller.pendingContent = content(controller.surface, insets: controller.insets, flyout: extent)
        sync(key)
        if let pending = controller.pendingContent {
            controller.pendingContent = nil
            controller.window.setContent(pending)
        }
    }

    static func expand(_ frame: CGRect, by extent: EdgeInsets) -> CGRect {
        CGRect(x: frame.minX - extent.leading, y: frame.minY - extent.bottom,
               width: frame.width + extent.leading + extent.trailing, height: frame.height + extent.top + extent.bottom)
    }

    private func build(_ surface: SurfaceInstance) {
        guard Self.windowKinds.contains(surface.ir.kind), context != nil else { return }
        guard surface.ir.kind != "window" || surface.isVisible else { return }
        let key = SurfaceHost.key(surface.id, surface.screenKey)
        let spec = SurfaceWindowSpec(surface: surface)
        let window = factory.make(spec: spec, content: content(surface, insets: EdgeInsets()))
        stats.windowsCreated += 1
        let controller = SurfaceWindowController(surface: surface, window: window, spec: spec)
        controller.wasOpen = false
        let id = surface.id, screenKey = surface.screenKey
        window.onCloseRequest = { [weak self] in self?.link?.close(id, screenKey: screenKey) }
        window.onKey = { [weak self] chord in self?.link?.keyPressed(chord, surfaceID: id, screenKey: screenKey) ?? false }
        window.onResize = { [weak self] in self?.userResized(key) }
        window.onOcclusion = { [weak self] visible in self?.occlusionChanged(key, visible: visible) }
        window.onFittingChange = { [weak self] in self?.fittingChanged(key) }
        controllers[key] = controller
        sync(key)
        if !FusionCoordinator.groupName(surface).isEmpty, !fusionRegistered { updateFusion() }
    }

    private func tearDown(_ key: String) {
        guard let controller = controllers.removeValue(forKey: key) else { return }
        controller.timeout?.cancel()
        controller.flyoutShrink?.cancel()
        controller.ticker?.stop()
        controller.ticker = nil
        controller.window.close()
        stats.windowsClosed += 1
        frames.publish(key, nil)
        context?.hits.remove(key)
        context?.elementFrames.remove(key)
        updateReserves()
        updateClickThrough()
    }

    func updateClickThrough() {
        let tracking = controllers.values.contains { $0.spec.clickThrough == .auto && $0.shown }
        guard tracking else {
            stopPointer?()
            stopPointer = nil
            return
        }
        if stopPointer == nil { stopPointer = watchPointer { [weak self] in self?.pointerMoved() } }
        pointerMoved()
    }

    func pointerMoved() {
        guard let hits = context?.hits else { return }
        let point = pointer()
        for (key, controller) in controllers where controller.spec.clickThrough == .auto && controller.shown {
            let frame = controller.window.frame
            let local = CGPoint(x: point.x - frame.minX - controller.flyout.leading, y: frame.maxY - point.y - controller.flyout.top)
            controller.window.setIgnoresMouse(!(frame.contains(point) && hits.contains(local, surfaceKey: key)))
        }
    }

    private func occlusionChanged(_ key: String, visible: Bool) {
        guard let controller = controllers[key], let context else { return }
        if visible { context.occluded.remove(key) } else { context.occluded.insert(key) }
        controller.window.setContent(content(controller.surface, insets: controller.insets, flyout: controller.flyout))
    }

    private func remeasure(_ key: String) {
        guard let controller = controllers[key], controller.spec.kind != "window", !controller.remeasurePending else { return }
        controller.remeasurePending = true
        afterLayout { [weak self, weak controller] in
            guard let self, let controller, self.controllers[key] === controller else { return }
            controller.remeasurePending = false
            guard controller.window.fittingSize != controller.lastFitting else { return }
            self.sync(key)
        }
    }

    private func fittingChanged(_ key: String) {
        guard let controller = controllers[key], controller.spec.kind != "window", !controller.fitPending else { return }
        controller.fitPending = true
        later { [weak self, weak controller] in
            guard let self, let controller, self.controllers[key] === controller else { return }
            controller.fitPending = false
            let fitting = controller.window.fittingSize
            guard fitting != controller.lastFitting else { return }
            controller.lastFitting = fitting
            self.sync(key)
        }
    }

    private func userResized(_ key: String) {
        guard let controller = controllers[key], controller.spec.kind == "window", controller.shown else { return }
        let frame = controller.window.frame
        guard frame != controller.openFrame else { return }
        let resized = frame.size != controller.openFrame.size
        controller.openFrame = frame
        frames.publish(key, frame)
        if resized { publishSize(controller.surface.id, controller.surface.screenKey, frame.size) }
        if !attachSyncing.contains(key) { syncAttached(to: key) }
    }

    private func sync(_ key: String) {
        guard let controller = controllers[key], let context else { return }
        let surface = controller.surface
        let spec = SurfaceWindowSpec(surface: surface)
        if spec != controller.spec {
            if Self.needsNewWindow(old: controller.spec, new: spec) {
                tearDown(key)
                build(surface)
                return
            }
            controller.spec = spec
            controller.window.apply(spec)
        }
        if fusionRegistered { controller.window.setLevel(fusion.level(for: key, base: spec.level)) }
        guard let screen = screens[surface.screenKey] else {
            log("surface \(surface.id): no screen \(surface.screenKey)")
            return
        }
        observeProperties(controller, key: key)
        let style = context.styles.resolve(surface: surface)
        let placement = SurfacePlacement(kind: surface.ir.kind, property: surface.property, style: style)
        let fit = controller.window.fittingSize, flyout = controller.flyout
        controller.lastFitting = fit
        let fitting = CGSize(width: max(0, fit.width - flyout.leading - flyout.trailing), height: max(0, fit.height - flyout.top - flyout.bottom))
        let layout = SurfaceLayout.compute(placement: placement, spec: spec, radius: StyleValues.radius(style["border-radius"]), screen: screen, fitting: fitting)
        if layout.insets != controller.insets {
            controller.insets = layout.insets
            controller.pendingContent = content(surface, insets: layout.insets, flyout: flyout)
        }
        var frame = layout.frame
        if let attach = SurfacePlacement.attachment(surface.property), let target = attachedRect(attach, screenKey: surface.screenKey) {
            frame = SurfacePlacement.attached(size: frame.size, to: target, side: attach.side, offset: CGPoint(x: placement.offsetX, y: placement.offsetY), visible: screen.visible)
        }
        if spec.kind == "window" {
            controller.window.setMinSize(CGSize(width: StyleValues.points(style["min-width"]) ?? 0, height: StyleValues.points(style["min-height"]) ?? 0))
            if surface.isVisible && !controller.placed {
                controller.placed = true
                if !controller.window.restoreFrame() { controller.window.setFrame(frame) }
            }
            controller.openFrame = controller.window.frame
            if let pending = controller.pendingContent {
                controller.pendingContent = nil
                controller.window.setContent(pending)
            }
        } else {
            let offset = CGPoint(x: placement.offsetX, y: placement.offsetY)
            let glide = controller.shown && controller.offset != nil && controller.offset != offset
            controller.offset = offset
            controller.openFrame = frame
            if let pending = controller.pendingContent {
                controller.pendingContent = nil
                controller.window.setContent(pending, frame: Self.expand(frame, by: flyout), glide: glide)
            } else {
                controller.window.setFrame(Self.expand(frame, by: flyout), glide: glide)
            }
        }
        if surface.isVisible { remeasure(key) }
        let opening = surface.isOpen && !controller.wasOpen
        let closing = !surface.isOpen && controller.wasOpen
        controller.wasOpen = surface.isOpen
        if opening || closing { onOpenChanged() }
        if surface.isVisible && !controller.shown {
            controller.shown = true
            present(controller, key: key, placement: placement, screen: screen, focus: opening)
        } else if opening {
            finishOpening(controller)
        } else if !surface.isVisible && controller.shown {
            controller.shown = false
            dismiss(controller, key: key, placement: placement, screen: screen, closing: closing)
        } else if closing {
            finishClosing(controller, key: key)
        } else if controller.shown && controller.ticker == nil {
            frames.publish(key, controller.openFrame)
        }
        if controller.shown { publishSize(surface.id, surface.screenKey, controller.openFrame.size) }
        updateReserves()
        updateClickThrough()
        if !attachSyncing.contains(key) { syncAttached(to: key) }
    }

    func attachedRect(_ attach: SurfacePlacement.Attachment, screenKey: String) -> CGRect? {
        let same = SurfaceHost.key(attach.surface, screenKey)
        let key = controllers[same] != nil ? same : controllers.keys.sorted().first { controllers[$0]?.surface.id == attach.surface }
        guard let key, let controller = controllers[key], controller.shown,
              let rect = context?.elementFrames.frame(attach.element, surfaceKey: key) else { return nil }
        let outer = controller.window.frame, flyout = controller.flyout
        return CGRect(x: outer.minX + flyout.leading + rect.minX, y: outer.maxY - flyout.top - rect.maxY, width: rect.width, height: rect.height)
    }

    func syncAttached(to key: String) {
        guard let target = controllers[key]?.surface.id ?? key.split(separator: "@").first.map(String.init) else { return }
        attachSyncing.insert(key)
        defer { attachSyncing.remove(key) }
        for other in controllers.keys.sorted() where other != key && !attachSyncing.contains(other) {
            guard let controller = controllers[other], SurfacePlacement.attachment(controller.surface.property)?.surface == target else { continue }
            sync(other)
        }
    }

    private func observeProperties(_ controller: SurfaceWindowController, key: String) {
        guard !controller.observing else { return }
        controller.observing = true
        withObservationTracking {
            for cell in controller.surface.properties.values { _ = cell.value }
        } onChange: { [weak self, weak controller] in
            MainActor.assumeIsolated {
                self?.later {
                    guard let self, let controller, self.controllers[key] === controller else { return }
                    controller.observing = false
                    self.sync(key)
                }
            }
        }
    }

    static func needsNewWindow(old: SurfaceWindowSpec, new: SurfaceWindowSpec) -> Bool {
        old.kind == "panel" && old.sticky && !new.sticky
    }

    func shownKeys(_ surfaceID: String) -> Set<String> {
        Set(controllers.filter { $0.value.surface.id == surfaceID && $0.value.shown }.keys)
    }

    func restartTimeout(_ surfaceID: String, keys: Set<String>? = nil) {
        for (key, controller) in controllers where controller.surface.id == surfaceID && controller.shown && keys?.contains(key) ?? true {
            scheduleTimeout(controller)
        }
    }

    private func geometry(_ controller: SurfaceWindowController, placement: SurfacePlacement, screen: ScreenGeometry) -> MotionGeometry {
        MotionGeometry(edge: MotionEdge(anchor: placement.anchor), size: controller.openFrame.size, topInset: max(0, screen.frame.maxY - screen.visible.maxY), flipped: false)
    }

    private func motion(_ spec: SurfaceWindowSpec) -> String? {
        if spec.animates { return spec.motion }
        return spec.scrim != nil ? "none" : nil
    }

    private func present(_ controller: SurfaceWindowController, key: String, placement: SurfacePlacement, screen: ScreenGeometry, focus: Bool) {
        let spec = controller.spec
        guard let motion = motion(spec) else {
            controller.window.show(focus: focus)
            frames.publish(key, controller.openFrame)
            scheduleTimeout(controller)
            if focus { finishOpening(controller) }
            return
        }
        let animator = animators.animator(motion)
        let geometry = geometry(controller, placement: placement, screen: screen)
        track(controller, key: key, animator: animator, geometry: geometry, opening: true)
        controller.window.animate(opening: true, focus: focus, animator: animator, geometry: geometry, scrim: spec.scrim, screen: screen.frame) { [weak self, weak controller] in
            guard let self, let controller, controller.shown else { return }
            if focus { self.finishOpening(controller) }
            guard controller.ticker == nil else { return }
            self.frames.publish(key, controller.openFrame)
        }
        scheduleTimeout(controller)
    }

    private func dismiss(_ controller: SurfaceWindowController, key: String, placement: SurfacePlacement, screen: ScreenGeometry, closing: Bool) {
        controller.timeout?.cancel()
        let spec = controller.spec
        guard let motion = motion(spec), closing else {
            stopTicker(controller)
            controller.window.hide()
            frames.publish(key, nil)
            if closing { finishClosing(controller, key: key) }
            return
        }
        let animator = animators.animator(motion)
        let geometry = geometry(controller, placement: placement, screen: screen)
        track(controller, key: key, animator: animator, geometry: geometry, opening: false)
        controller.window.animate(opening: false, focus: false, animator: animator, geometry: geometry, scrim: spec.scrim, screen: screen.frame) { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.stopTicker(controller)
            self.frames.publish(key, nil)
            self.finishClosing(controller, key: key)
        }
    }

    private func finishOpening(_ controller: SurfaceWindowController) {
        link?.surfaceDidFinishOpening(id: controller.surface.id, screenKey: controller.surface.screenKey)
    }

    private func finishClosing(_ controller: SurfaceWindowController, key: String) {
        link?.surfaceDidFinishClosing(id: controller.surface.id, screenKey: controller.surface.screenKey)
    }

    private func stopTicker(_ controller: SurfaceWindowController) {
        controller.ticker?.stop()
        controller.ticker = nil
    }

    private func track(_ controller: SurfaceWindowController, key: String, animator: any SurfaceAnimator, geometry: MotionGeometry, opening: Bool) {
        stopTicker(controller)
        guard frames.hasObservers, let ticker = makeTicker(controller.window) else { return }
        controller.ticker = ticker
        let open = controller.openFrame
        let total = animator.duration(opening: opening)
        ticker.start { [weak self, weak controller, weak ticker] elapsed in
            guard let self, let controller, let ticker, controller.ticker === ticker else { return false }
            let progress = animator.progress(at: elapsed, opening: opening)
            self.frames.publish(key, animator.visibleFrame(open: open, geometry: geometry, progress: progress))
            let going = elapsed < total && self.frames.hasObservers
            if !going { controller.ticker = nil }
            return going
        }
    }

    private func scheduleTimeout(_ controller: SurfaceWindowController, after delay: TimeInterval? = nil) {
        controller.timeout?.cancel()
        controller.timeout = nil
        guard let seconds = controller.spec.timeout else { return }
        if delay == nil { controller.hovered = false }
        let id = controller.surface.id, screenKey = controller.surface.screenKey
        let work = DispatchWorkItem { [weak self, weak controller] in
            MainActor.assumeIsolated {
                guard let self, let controller, self.controllers.values.contains(where: { $0 === controller }) else { return }
                if controller.openFrame.contains(self.pointer()) {
                    controller.hovered = true
                    self.scheduleTimeout(controller, after: Self.hoverPoll)
                } else if controller.hovered {
                    self.scheduleTimeout(controller)
                } else {
                    self.link?.close(id, screenKey: screenKey)
                }
            }
        }
        controller.timeout = work
        scheduleTimer(delay ?? seconds, work)
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

extension WindowHost {
    func reservedEdges() -> [String: ReservedEdges] {
        var result: [String: ReservedEdges] = [:]
        for controller in controllers.values where controller.spec.reserve && controller.shown {
            let key = controller.surface.screenKey
            guard let screen = screens[key]?.frame else { continue }
            let frame = controller.openFrame
            var edges = result[key] ?? ReservedEdges()
            switch SurfacePlacement(kind: controller.surface.ir.kind, property: controller.surface.property, style: .init()).anchor {
            case .left: edges.left = max(edges.left, frame.maxX - screen.minX)
            case .right: edges.right = max(edges.right, screen.maxX - frame.minX)
            case .top: edges.top = max(edges.top, screen.maxY - frame.minY)
            case .bottom: edges.bottom = max(edges.bottom, frame.maxY - screen.minY)
            default: continue
            }
            result[key] = edges
        }
        return result
    }

    func hoverTargets() -> [EdgeHoverController.Target] {
        controllers.keys.sorted().compactMap { key in
            guard let controller = controllers[key], controller.spec.hoverEdge,
                  let screen = screens[controller.surface.screenKey] else { return nil }
            let surface = controller.surface
            let anchor = SurfacePlacement(kind: surface.ir.kind, property: surface.property, style: .init()).anchor
            return EdgeHoverController.Target(key: key, surfaceID: surface.id, screenKey: surface.screenKey, anchor: anchor,
                                              frame: controller.openFrame, screen: screen.frame, margin: controller.spec.hoverMargin,
                                              gap: controller.spec.hoverGap, isOpen: surface.isOpen)
        }
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

@MainActor
enum PointerWatch {
    static func live(_ moved: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { _ in MainActor.assumeIsolated { moved() } }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            moved()
            return event
        }
        return {
            if let global { NSEvent.removeMonitor(global) }
            if let local { NSEvent.removeMonitor(local) }
        }
    }
}
