import AppKit
import ApolloShellCore
import QuartzCore
import SwiftUI

enum DrawerEdge {
    case top
    case right
    case bottomRight
    case bottom
}

enum DrawerMotion {
    case slide
    case grow

    @MainActor
    func closedTransform(edge: DrawerEdge, size: NSSize, topInset: CGFloat, container: NSView) -> CATransform3D {
        switch self {
        case .slide:
            switch edge {
            case .top: CATransform3DMakeTranslation(0, size.height + topInset + 5, 0)
            case .right: CATransform3DMakeTranslation(size.width + 5, 0, 0)
            case .bottomRight, .bottom: CATransform3DMakeTranslation(0, -(size.height + 5), 0)
            }
        case .grow:
            Grow.closedTransform(for: container)
        }
    }

    func transformAnimation(opening: Bool) -> CABasicAnimation {
        switch self {
        case .slide:
            let animation = CABasicAnimation(keyPath: "sublayerTransform")
            animation.duration = MotionCurve.spatialDuration
            animation.timingFunction = .shellSpatial
            return animation
        case .grow:
            return Grow.spring(response: opening ? Grow.openResponse : Grow.closeResponse)
        }
    }

    func fade(opening: Bool) -> (duration: TimeInterval, curve: CAMediaTimingFunction) {
        switch self {
        case .slide: (MotionCurve.spatialDuration, .shellSpatial)
        case .grow: (opening ? Grow.fadeIn : Grow.fadeOut, Grow.easeOut)
        }
    }

    private enum Grow {
        static let openResponse: CGFloat = 0.42
        static let closeResponse: CGFloat = 0.28
        static let fadeIn: TimeInterval = 0.16
        static let fadeOut: TimeInterval = 0.14
        static let travel: CGFloat = 40
        static let closedScale: CGFloat = 0.92
        static var easeOut: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) }

        @MainActor
        static func closedTransform(for view: NSView) -> CATransform3D {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                return CATransform3DIdentity
            }
            guard let layer = view.layer else { return CATransform3DIdentity }
            let size = layer.bounds.size
            let flipped = layer.isGeometryFlipped
            let pivot = CGPoint(x: layer.anchorPoint.x * size.width, y: layer.anchorPoint.y * size.height)
            let bottomCenter = CGPoint(x: size.width / 2, y: flipped ? size.height : 0)
            let dx = bottomCenter.x - pivot.x
            let dy = bottomCenter.y - pivot.y
            let down: CGFloat = flipped ? 1 : -1

            var transform = CATransform3DMakeTranslation(-dx, -dy, 0)
            transform = CATransform3DConcat(transform, CATransform3DMakeScale(closedScale, closedScale, 1))
            transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(dx, dy + down * travel, 0))
            return transform
        }

        static func spring(response: CGFloat) -> CASpringAnimation {
            let spring = CASpringAnimation(keyPath: "sublayerTransform")
            spring.mass = 1
            spring.stiffness = pow(2 * .pi / response, 2)
            spring.damping = 4 * .pi / response
            spring.initialVelocity = 0
            spring.duration = spring.settlingDuration
            return spring
        }
    }
}

struct DrawerScrim {
    let amount: CGFloat
    let duration: TimeInterval
    let curve: CAMediaTimingFunction
}

@MainActor
final class EdgeDrawer<Content: View>: NSObject, NSWindowDelegate {
    let edge: DrawerEdge
    let motion: DrawerMotion
    let scrim: DrawerScrim?
    private(set) var size: NSSize
    let cornerRadius: CGFloat
    var closesOnResignKey = true
    let takesKeyboard: Bool
    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}
    var onHidden: () -> Void = {}

    var opensOnHover = false {
        didSet { updateHoverMonitor() }
    }
    var suspendedScreens: Set<CGDirectDisplayID> = []
    private var hoverState = EdgeHoverState.hidden
    private var hoverMonitor: Any?
    private var hoverTimer: Timer?

    private let rootView: Content
    private var builtPanel: DrawerPanel?
    private var panel: DrawerPanel {
        if let builtPanel { return builtPanel }
        let panel = makePanel()
        builtPanel = panel
        return panel
    }
    private let container: NSView
    private var builtScrim: ScrimWindow?
    private var glass: NSGlassEffectView?
    private var hosting: NSView?
    private var panelLayer: CAGradientLayer?
    private(set) var isOpen = false
    private var generation = 0

    private(set) var currentScreen: ShellScreen?

    private var topInset: CGFloat

    init(edge: DrawerEdge, size: NSSize, cornerRadius: CGFloat, takesKeyboard: Bool = true,
         motion: DrawerMotion = .slide, scrim: DrawerScrim? = nil, rootView: Content) {
        self.edge = edge
        self.motion = motion
        self.scrim = scrim
        self.size = size
        self.cornerRadius = cornerRadius
        self.takesKeyboard = takesKeyboard
        self.rootView = rootView
        topInset = edge == .top ? Self.menuBarInset(NSScreen.screens.first) : 0
        container = NSView(frame: NSRect(
            origin: .zero,
            size: Self.windowSize(for: edge, size: size, radius: cornerRadius, topInset: topInset)
        ))
        super.init()
        observeScreenChanges()
    }

    private func applyTheme() {
        panelLayer = ThemedGlass.apply(to: glass, fallbackRadius: cornerRadius, previous: panelLayer)
    }

    private static func menuBarInset(_ screen: NSScreen?) -> CGFloat {
        guard let screen else { return 0 }
        return max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
    }

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        open(byHover: false)
    }

    private func open(byHover: Bool) {
        guard !isOpen, let screen = ShellScreens.underPointer() else { return }
        applyTheme()
        isOpen = true
        generation += 1
        afterClose = nil
        applyGeometry(on: screen)
        if byHover {
            hoverState = EdgeHoverState(visible: true, shortcutActive: false)
        } else {
            let inArea = hoverArea(on: screen, open: true)?.contains(NSEvent.mouseLocation) ?? false
            hoverState = .openedByShortcut(mouseInArea: inArea)
        }
        startHoverTimer()
        onOpen()

        panel.setFrame(windowFrame(on: screen), display: false)
        if !panel.isVisible {
            setSlide(closed: true, animated: false)
            panel.alphaValue = 0
        }
        if let scrim, let scrimWindow = scrimWindow() {
            scrimWindow.setFrame(screen.frame, display: false)
            if !scrimWindow.isVisible { scrimWindow.alphaValue = 0 }
            scrimWindow.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = scrim.duration
                context.timingFunction = scrim.curve
                scrimWindow.animator().alphaValue = scrim.amount
            }
        }
        if takesKeyboard && !byHover {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        setSlide(closed: false, animated: true)
        let fade = motion.fade(opening: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fade.duration
            context.timingFunction = fade.curve
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        generation += 1
        let current = generation
        hoverState = .hidden
        hoverTimer?.invalidate()
        hoverTimer = nil
        onClose()

        setSlide(closed: true, animated: true)
        if let scrim, let scrimWindow = builtScrim {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = scrim.duration
                context.timingFunction = scrim.curve
                scrimWindow.animator().alphaValue = 0
            }
        }
        let fade = motion.fade(opening: false)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fade.duration
            context.timingFunction = fade.curve
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
                self.builtScrim?.orderOut(nil)
                self.onHidden()
                let action = self.afterClose
                self.afterClose = nil
                action?()
            }
        })
    }

    func close(then: @escaping @MainActor () -> Void) {
        let step = DrawerCloseStep(
            isOpen: isOpen,
            isVisible: builtPanel?.isVisible ?? false,
            hasPendingAction: afterClose != nil
        )
        switch step {
        case .closeThenRun:
            close()
            afterClose = then
        case .runAfterFade:
            afterClose = then
        case .drop:
            break
        case .runNow:
            then()
        }
    }

    private var afterClose: (@MainActor () -> Void)?

    private func applyGeometry(on screen: ShellScreen) {
        currentScreen = screen
        let inset = edge == .top ? Self.menuBarInset(screen.screen) : 0
        let wanted = Self.windowSize(for: edge, size: size, radius: cornerRadius, topInset: inset)
        guard inset != topInset || container.frame.size != wanted else { return }
        topInset = inset
        container.setFrameSize(wanted)
        if let glass {
            glass.frame = container.bounds
            glass.contentView?.frame = glass.bounds
        }
        hosting?.frame = visibleRectInWindow
    }

    func resize(to newSize: NSSize) {
        guard newSize != size else { return }
        size = newSize
        container.setFrameSize(Self.windowSize(for: edge, size: newSize, radius: cornerRadius, topInset: topInset))
        guard let builtPanel else { return }
        if let screen = currentScreen ?? ShellScreens.underPointer() {
            builtPanel.setFrame(windowFrame(on: screen), display: builtPanel.isVisible)
        }
        if let glass {
            glass.frame = container.bounds
            glass.contentView?.frame = glass.bounds
        }
        hosting?.frame = visibleRectInWindow
    }

    func probeGeometry() -> (window: NSRect, container: NSRect, glass: NSRect, content: NSRect, hosting: NSRect) {
        _ = panel
        return (panel.frame, container.frame, glass?.frame ?? .zero, glass?.contentView?.frame ?? .zero,
                hosting?.frame ?? .zero)
    }

    private func updateHoverMonitor() {
        if opensOnHover, hoverMonitor == nil {
            hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                MainActor.assumeIsolated { self?.hoverMoved() }
            }
        } else if !opensOnHover, let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
            hoverMonitor = nil
        }
    }

    private func startHoverTimer() {
        guard opensOnHover, hoverTimer == nil else { return }
        hoverTimer = .repeating(every: 0.05, owner: self) { $0.hoverMoved() }
    }

    private func hoverMoved() {
        guard opensOnHover else { return }
        let target = isOpen ? currentScreen : ShellScreens.underPointer()
        guard let target, !suspendedScreens.contains(target.displayID),
              let area = hoverArea(on: target, open: isOpen)
        else { return }
        let next = hoverState.moved(inArea: area.contains(NSEvent.mouseLocation))
        if next.visible && !isOpen {
            open(byHover: true)
        } else if !next.visible && isOpen {
            close()
        } else {
            hoverState = next
        }
    }

    private func hoverArea(on screen: ShellScreen, open: Bool) -> NSRect? {
        switch edge {
        case .top:
            let inset = Self.menuBarInset(screen.screen)
            return EdgeHoverArea.top(screen: screen.frame, width: size.width, depth: inset + size.height,
                                     margin: cornerRadius, open: open)
        case .bottomRight:
            return EdgeHoverArea.bottomRight(screen: screen.frame, width: size.width, height: size.height,
                                             margin: cornerRadius, open: open)
        case .right, .bottom:
            return nil
        }
    }

    private func observeScreenChanges() {
        ShellScreens.onChange { [weak self] in
            guard let self, self.isOpen, let current = self.currentScreen else { return }
            guard let same = ShellScreens.current().first(where: { $0.displayID == current.displayID }) else {
                self.close()
                return
            }
            self.applyGeometry(on: same)
            self.builtPanel?.setFrame(self.windowFrame(on: same), display: true)
            self.builtScrim?.setFrame(same.frame, display: true)
        }
    }

    private static func windowSize(for edge: DrawerEdge, size: NSSize, radius: CGFloat, topInset: CGFloat) -> NSSize {
        switch edge {
        case .top: NSSize(width: size.width, height: size.height + topInset + radius)
        case .right: NSSize(width: size.width + radius, height: size.height)
        case .bottomRight: NSSize(width: size.width + radius, height: size.height + radius)
        case .bottom: NSSize(width: size.width, height: size.height + radius)
        }
    }

    private var visibleRectInWindow: NSRect {
        switch edge {
        case .top: NSRect(x: 0, y: 0, width: size.width, height: size.height)
        case .right: NSRect(x: 0, y: 0, width: size.width, height: size.height)
        case .bottomRight, .bottom: NSRect(x: 0, y: cornerRadius, width: size.width, height: size.height)
        }
    }

    private func windowFrame(on screen: ShellScreen) -> NSRect {
        let frame = screen.frame
        let windowSize = container.frame.size
        switch edge {
        case .top:
            return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - topInset - size.height,
                          width: windowSize.width, height: windowSize.height)
        case .right:
            return NSRect(x: frame.maxX - size.width, y: frame.midY - size.height / 2,
                          width: windowSize.width, height: windowSize.height)
        case .bottomRight:
            return NSRect(x: frame.maxX - size.width, y: frame.minY - cornerRadius,
                          width: windowSize.width, height: windowSize.height)
        case .bottom:
            return NSRect(x: frame.midX - size.width / 2, y: frame.minY - cornerRadius,
                          width: windowSize.width, height: windowSize.height)
        }
    }

    private func setSlide(closed: Bool, animated: Bool) {
        guard let layer = container.layer else { return }
        let target = closed
            ? motion.closedTransform(edge: edge, size: size, topInset: topInset, container: container)
            : CATransform3DIdentity
        let current = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = target
        CATransaction.commit()

        guard animated else {
            layer.removeAnimation(forKey: "drawer.slide")
            return
        }
        let animation = motion.transformAnimation(opening: !closed)
        animation.fromValue = NSValue(caTransform3D: current)
        animation.toValue = NSValue(caTransform3D: target)
        layer.add(animation, forKey: "drawer.slide")
    }

    private func makePanel() -> DrawerPanel {
        let level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + (scrim == nil ? 0 : 1))
        let panel = DrawerPanel(size: container.frame.size, level: level, takesKeyboard: takesKeyboard)
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }

        let glass = NSGlassEffectView(frame: container.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.cornerRadius = cornerRadius

        let content = NSView(frame: container.bounds)
        let hosting = FirstMouseHostingView(rootView: rootView.shellTheme())
        hosting.sizingOptions = []
        hosting.frame = visibleRectInWindow
        content.addSubview(hosting)
        glass.contentView = content
        self.glass = glass
        applyTheme()
        self.hosting = hosting

        container.wantsLayer = true
        container.addSubview(glass)
        panel.contentView = container
        return panel
    }

    private func scrimWindow() -> ScrimWindow? {
        guard scrim != nil else { return nil }
        if let builtScrim { return builtScrim }
        let window = ScrimWindow()
        window.onClick = { [weak self] in self?.close() }
        builtScrim = window
        return window
    }

    func windowDidResignKey(_ notification: Notification) {
        if closesOnResignKey { close() }
    }
}

final class DrawerPanel: ShellPanel {
    var onEscape: () -> Void = {}

    init(size: NSSize, level: NSWindow.Level, takesKeyboard: Bool) {
        super.init(size: size, level: level,
                   behavior: [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary],
                   takesKeyboard: takesKeyboard, mayLeaveScreen: true)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }
}

final class ScrimWindow: ShellPanel {
    var onClick: () -> Void = {}

    init() {
        super.init(level: .popUpMenu, behavior: [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary])
        backgroundColor = .black
        contentView = ClickView { [weak self] in self?.onClick() }
    }
}

private final class ClickView: NSView {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("nicht benutzt") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { action() }
}
