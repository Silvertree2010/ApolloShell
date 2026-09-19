import AppKit
import ApolloShellCore
import QuartzCore
import SwiftUI

/// Where an edge window sits.
enum DrawerEdge {
    /// Top centered, right below the menu bar (Caelestia: Dashboard).
    case top
    /// Right, vertically centered (Caelestia: session menu, OSD).
    case right
    /// Bottom-right corner (Caelestia: Utilities).
    case bottomRight
    /// Bottom centered, where Apple's Dock used to sit (Launcher).
    case bottom
}

/// How an edge window opens and closes. The content is moved via the
/// sublayerTransform of the container - Core Animation computes that on the
/// GPU, unlike an animated setFrame, which has AppKit set the frame bit by
/// bit on the main thread and re-render the glass every time. On top of
/// that, the window fades in and out.
enum DrawerMotion {
    /// Caelestia: slides out of the edge by its own size (+5), 500 ms on
    /// `MotionCurve.spatial` with a slight overshoot, fading in on the same
    /// curve.
    case slide
    /// Launcher: grows out of the center of the bottom edge (a bit smaller
    /// and lower) and takes the same path back. Springs instead of a fixed
    /// duration, critically damped like Apple: fast start, soft settle, no
    /// bounce-back (that belongs to swipe gestures, not a key press). The
    /// first version (28 pt, translation only) was barely noticeable.
    case grow

    /// Closed state of the sublayerTransform.
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

    /// The sublayerTransform motion; `from`/`to` are set by the caller.
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

    /// Duration and curve of the fade in/out. Shorter than the spring while
    /// growing, so the glass is there right away.
    func fade(opening: Bool) -> (duration: TimeInterval, curve: CAMediaTimingFunction) {
        switch self {
        case .slide: (MotionCurve.spatialDuration, .shellSpatial)
        case .grow: (opening ? Grow.fadeIn : Grow.fadeOut, Grow.easeOut)
        }
    }

    private enum Grow {
        /// Spring response in seconds (Apple's "response"): how fast the
        /// target is reached. A bit calmer opening, snappier closing.
        static let openResponse: CGFloat = 0.42
        static let closeResponse: CGFloat = 0.28
        static let fadeIn: TimeInterval = 0.16
        static let fadeOut: TimeInterval = 0.14
        /// Closed state: `travel` points lower and scaled down to `closedScale`.
        static let travel: CGFloat = 40
        static let closedScale: CGFloat = 0.92
        static var easeOut: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) }

        /// Under "reduce motion", the identity, so only the fade remains.
        ///
        /// The sublayerTransform rotates around the layer's anchorPoint.
        /// Measured offline: for view layers that is (0,0), i.e. bottom
        /// left, and y points up. So the panel grows out of the Dock
        /// instead of the corner, the pivot is moved to the center of the
        /// bottom edge: shift there, scale, shift back, then offset
        /// downward.
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

        /// Critically damped spring from Apple's "response" (mass 1):
        /// stiffness (2*pi/response)^2, damping 4*pi*zeta/response with zeta = 1.
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

/// Dimming of the whole screen behind the window; a click on it closes it
/// (Caelestia: session menu).
struct DrawerScrim {
    /// How dark, 0...1.
    let amount: CGFloat
    let duration: TimeInterval
    let curve: CAMediaTimingFunction
}

/// Glass panel that sticks to a screen edge and comes out of it
/// (`DrawerMotion`), optionally in front of a dimmed screen (`DrawerScrim`).
/// Shared building block for Dashboard, Utilities, OSD, session menu and
/// Launcher.
///
/// It opens wherever the pointer is, and the mouse opens it at the edge of
/// EVERY screen - not just the main screen. As long as it is open, it stays
/// on its screen, even if the pointer wanders over to another one.
///
/// The window is larger than what is visible by the corner radius and
/// therefore overhangs the screen edge(s): that way the glass corners sit
/// outside the edge, and the panel looks as if it were growing out of it.
/// The content only occupies the visible part. At the top the glass extends
/// over the menu bar to the edge; the content starts below the menu bar and
/// the notch.
@MainActor
final class EdgeDrawer<Content: View>: NSObject, NSWindowDelegate {
    let edge: DrawerEdge
    let motion: DrawerMotion
    let scrim: DrawerScrim?
    /// Visible size (excluding the part that overhangs the edge). Only
    /// changes via `resize(to:)` (Utilities: cards on/off, more rows).
    private(set) var size: NSSize
    let cornerRadius: CGFloat
    /// A click into another app closes it (default). Off for purely
    /// display-only windows like the OSD.
    var closesOnResignKey = true
    /// Accept keyboard input (Esc closes). Off for the OSD, so it never
    /// takes focus.
    let takesKeyboard: Bool
    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}
    /// Before `applyGeometry`, as soon as the target screen is known - for
    /// the Dashboard's scale (`Dashboard.prepareForScreen`). Other edge
    /// windows leave it `nil`.
    var prepareForScreen: ((NSScreen) -> Void)?
    /// After the close animation, once the window is gone - not when it
    /// reopened before that.
    var onHidden: () -> Void = {}

    /// Caelestia: appears when the mouse hits the edge, and goes away when
    /// it leaves the area (rules in ApolloShellCore/EdgeHover). Top
    /// (Dashboard) and bottom right (Utilities).
    var opensOnHover = false {
        didSet {
            #if DEBUG
            // Self-test: no mouse monitoring alongside the real shell.
            if EditModeSelfTest.invisible { return }
            #endif
            updateHoverMonitor()
        }
    }
    /// Screens with a fullscreen app on them: there the mouse at the edge
    /// opens nothing (same as Caelestia). It keeps working on the other
    /// screens.
    var suspendedScreens: Set<CGDirectDisplayID> = []
    /// While editing (Dashboard, Bento pages): keeps the window open no
    /// matter where the mouse is - hover does not close it, `Esc` does not
    /// close it, a click into another app (Nexus) does not close it, and
    /// `toggle()`/`open()`/`close()` from outside have no effect. Unpinning
    /// closes it on its own, unless the pointer is still in the flyout
    /// area - then the usual hover behavior takes over from there;
    /// otherwise the window would stay open indefinitely (`unpin()`).
    ///
    /// While `isPinned` is set, additionally (Spec Section 4,
    /// "window-manager-safe"): `.stationary` instead of `.transient`
    /// (window managers like AeroSpace/yabai/Amethyst would otherwise tile
    /// or move a `.transient` window along once it stays open longer than a
    /// swipe), a non-standard accessibility subrole and excluded from the
    /// window menu - like `EditModePanel`, but only as long as pinned (an
    /// unpinned edge window stays `.transient`: a window manager keyboard
    /// shortcut should still be able to close it). The value applies to
    /// `builtPanel`, if it is already built, and to any newly built one
    /// (`makePanel()`).
    var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            builtPanel?.setPinned(isPinned)
            guard oldValue, !isPinned else { return }
            unpin()
        }
    }
    private var hoverState = EdgeHoverState.hidden
    private var hoverMonitor: Any?
    /// While open: check the mouse position ourselves. The global monitor
    /// does not see movements over our own windows (panel, bar).
    private var hoverTimer: Timer?

    private let rootView: Content
    /// Only built on first open. Not as a `lazy var`: its initializer is
    /// not recognized as MainActor by Swift 6.3.3 and warns that `Content`'s
    /// View conformance may not cross over there.
    private var builtPanel: DrawerPanel?
    private var panel: DrawerPanel {
        if let builtPanel { return builtPanel }
        let panel = makePanel()
        builtPanel = panel
        return panel
    }
    private let container: NSView
    private var builtScrim: ScrimWindow?
    /// Glass and the SwiftUI content inside it; `resize(to:)` resets their frames.
    private var glass: NSGlassEffectView?
    private var hosting: NSView?
    /// The tinted area under the glass, when a theme applies.
    private var panelLayer: CAGradientLayer?
    private(set) var isOpen = false
    private var generation = 0

    /// Which screen the window is currently on, or was last on.
    private(set) var currentScreen: ShellScreen?

    /// Top edge only: strip under the menu bar and camera notch. The glass
    /// reaches to the screen edge (like Utilities at the bottom right), the
    /// content only starts below that - in the notch it would be cut off.
    ///
    /// No longer a fixed value: not every screen has a menu bar, and only
    /// the built-in one has a notch anyway. It is redetermined for the
    /// target screen on open (`applyGeometry`).
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

    /// Tints the edge window's glass according to the theme: panel color as
    /// tint, panel radius as corner. Without a theme everything stays as it
    /// was. Set when building and on every open, so a theme change reaches
    /// it by the next open at the latest.
    /// Tints the edge window per the theme (see `ThemedGlass`).
    private func applyTheme() {
        panelLayer = ThemedGlass.apply(to: glass, fallbackRadius: cornerRadius, previous: panelLayer)
    }

    /// Height of the menu bar or the notch, whichever is larger (menu bar
    /// hidden: then only the notch counts). Screens without a menu bar
    /// yield 0.
    private static func menuBarInset(_ screen: NSScreen?) -> CGFloat {
        guard let screen else { return 0 }
        return max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
    }

    /// While editing (`isPinned`), neither the icon nor the keyboard
    /// shortcut has any effect - the window stays until editing ends.
    func toggle() {
        guard !isPinned else { return }
        isOpen ? close() : open()
    }

    /// The window's frame on the screen while open - for windows that must
    /// avoid it (toolbar and gallery of edit mode). Includes the overhang
    /// at the edge; that is enough for avoiding it.
    var openFrame: NSRect? { isOpen ? builtPanel?.frame : nil }
    #if DEBUG
    var debugLevel: Int? { builtPanel?.level.rawValue }

    /// Self-test: a drag with the left button straight to this window,
    /// points in the hosting view from the top left (like SwiftUI's `.global`).
    func debugDrag(from start: CGPoint, to end: CGPoint, steps: Int = 8) {
        guard let panel = builtPanel, let hosting else { return }
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent? {
            let location = hosting.convert(NSPoint(x: point.x, y: point.y), to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: panel.windowNumber, context: nil,
                                      eventNumber: 0, clickCount: 1, pressure: 1)
        }
        if let down = event(.leftMouseDown, start) { panel.sendEvent(down) }
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            if let drag = event(.leftMouseDragged, point) { panel.sendEvent(drag) }
        }
        if let up = event(.leftMouseUp, end) { panel.sendEvent(up) }
    }

    var debugWindowHeight: CGFloat { builtPanel?.frame.height ?? 0 }

    /// Self-test: force every view in the window to lay out again, so
    /// measurement views report their position again after a size change.
    func debugRelayout() {
        func mark(_ view: NSView) {
            view.needsLayout = true
            view.subviews.forEach(mark)
        }
        guard let root = builtPanel?.contentView else { return }
        mark(root)
        root.layoutSubtreeIfNeeded()
    }

    /// Self-test: window and hosting frames for debugging.
    var debugFrames: String {
        "Window \(builtPanel?.frame ?? .zero), Host \(hosting?.frame ?? .zero), Host in window \(hosting.map { $0.convert($0.bounds, to: nil) } ?? .zero)"
    }

    /// Self-test: a click at this point in window coordinates.
    func debugClick(atWindowPoint location: NSPoint) {
        guard let panel = builtPanel else { return }
        if let hosting {
            // Via the hosting view like in the Dashboard (proven effective there).
            let host = hosting.convert(location, from: nil)
            debugClick(at: CGPoint(x: host.x, y: host.y))
            return
        }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: panel.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1) {
                panel.sendEvent(e)
            }
        }
    }

    /// Self-test: a click at this point (hosting view, top left).
    func debugClick(at point: CGPoint) {
        guard let panel = builtPanel, let hosting else { return }
        let location = hosting.convert(NSPoint(x: point.x, y: point.y), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: panel.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1) {
                panel.sendEvent(e)
            }
        }
    }

    /// Self-test: a rectangle in the hosting view (top left) in screen
    /// coordinates.
    func debugScreenRect(ofHostRect rect: CGRect) -> NSRect? {
        guard let panel = builtPanel, let hosting else { return nil }
        let inWindow = hosting.convert(rect, to: nil)
        return panel.convertToScreen(inWindow)
    }
    #endif

    /// Take keyboard input while open - e.g. for renaming a page in edit
    /// mode, when another edge window (Control Center) has since become
    /// the key window. Only for windows that accept keyboard input at all
    /// (`takesKeyboard`).
    func takeKeyboard() {
        guard isOpen, takesKeyboard else { return }
        panel.makeKey()
    }

    /// Via keyboard shortcut or icon.
    func open() {
        guard !isPinned else { return }
        guard let screen = ShellScreens.underPointer() else { return }
        open(byHover: false, on: screen)
    }

    /// On a specific screen instead of the one under the pointer - for an
    /// edit session that starts from Nexus (`isPinned`).
    func open(on screen: NSScreen) {
        // Via the display identifier; if that finds nothing (screen just
        // disappeared), then wherever the pointer is - a pinned window that
        // silently fails to open would leave the edit session without a panel.
        guard let target = ShellScreens.matching(screen) ?? ShellScreens.underPointer() else { return }
        open(byHover: false, on: target)
    }

    /// Opened via the mouse, it does not take focus: the app underneath
    /// keeps the keyboard, since one is only passing by.
    private func open(byHover: Bool, on screen: ShellScreen) {
        guard !isOpen else { return }
        applyTheme()
        isOpen = true
        generation += 1
        afterClose = nil
        prepareForScreen?(screen.screen)
        // Before the first access to `panel`: it builds its window from
        // the container's size, and that depends on the screen.
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

    /// Close and only run `then` once the panel is completely off screen.
    /// For actions that would otherwise collide with the panel: while it is
    /// the key window, posted keys (Control-Command-Q) end up with us
    /// instead of the app in front, and the eyedropper or a screenshot
    /// would see the half-faded glass. If it opens again before that,
    /// `then` is dropped - the user changed their mind.
    ///
    /// While fading out, the panel is still clickable. A click during this
    /// time waits as well, a second one (double click) is dropped
    /// (`DrawerCloseStep`).
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

    // MARK: - Resizing

    /// Adopt the dimensions for this screen. At the top, the window height
    /// depends on the menu bar, and that is not the same height on every
    /// screen (a second screen may have none at all, depending on settings).
    private func applyGeometry(on screen: ShellScreen) {
        currentScreen = screen
        let inset = edge == .top ? Self.menuBarInset(screen.screen) : 0
        let wanted = Self.windowSize(for: edge, size: size, radius: cornerRadius, topInset: inset)
        guard inset != topInset || container.frame.size != wanted else { return }
        topInset = inset
        container.setFrameSize(wanted)
        // As in `resize(to:)`: set the content area explicitly, not via
        // autoresizing.
        if let glass {
            glass.frame = container.bounds
            glass.contentView?.frame = glass.bounds
        }
        hosting?.frame = visibleRectInWindow
    }

    /// New visible size, immediately and without animation.
    ///
    /// Why without: while open, the content also changes in the same pass
    /// (card removed, row added) - it jumps anyway, an animated frame would
    /// only lag behind it and show too little or too much glass for a few
    /// frames. Nothing is noticeable while closed: the window is not on
    /// screen, and `open()` slides it out of the edge with the new size.
    ///
    /// The edge holds: at the bottom right the window grows upward, at the
    /// top downward, at the right in both directions around the center.
    func resize(to newSize: NSSize) {
        guard newSize != size else { return }
        size = newSize
        container.setFrameSize(Self.windowSize(for: edge, size: newSize, radius: cornerRadius, topInset: topInset))
        guard let builtPanel else { return }
        if let screen = currentScreen ?? ShellScreens.underPointer() {
            builtPanel.setFrame(windowFrame(on: screen), display: builtPanel.isVisible)
        }
        // The glass grows via autoresizing with the container. Its content
        // area does NOT: with autoresizing it came out distorted in the
        // visual test (14.09.: 451 -> 162 gave 10, then 852) - so it is set
        // explicitly to the glass size. The SwiftUI content only occupies
        // the visible part.
        if let glass {
            glass.frame = container.bounds
            glass.contentView?.frame = glass.bounds
        }
        hosting?.frame = visibleRectInWindow
    }

    /// For visual tests and checks: where the window, glass and content
    /// currently sit. Builds the window but does not show it.
    func probeGeometry() -> (window: NSRect, container: NSRect, glass: NSRect, content: NSRect, hosting: NSRect) {
        _ = panel
        return (panel.frame, container.frame, glass?.frame ?? .zero, glass?.contentView?.frame ?? .zero,
                hosting?.frame ?? .zero)
    }

    // MARK: - Mouse at the edge

    /// Global monitor for mouse movement only: needs no permission (only
    /// keyboard monitors need accessibility access). The check per movement
    /// is a rectangle comparison.
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

    /// Unpin (editing finished/cancelled): without this the window would
    /// stay open indefinitely, since `hoverMoved()` checked nothing while
    /// `isPinned` and `hoverState` has been stale since then. If the
    /// pointer is still in the flyout area, the usual hover behavior takes
    /// over from there (stay open until it leaves); otherwise it closes
    /// right away.
    private func unpin() {
        guard isOpen else { return }
        guard opensOnHover, let target = currentScreen, !suspendedScreens.contains(target.displayID),
              let area = hoverArea(on: target, open: true), area.contains(NSEvent.mouseLocation)
        else {
            close()
            return
        }
        hoverState = EdgeHoverState(visible: true, shortcutActive: false)
    }

    private func hoverMoved() {
        guard opensOnHover else { return }
        // While editing it stays open on its screen, no matter where the
        // mouse is.
        if isOpen && isPinned { return }
        // Open: the screen the window is on - otherwise a pointer wandering
        // over would immediately close it again. Closed: the one under the
        // pointer, so the edge of every screen opens it.
        let target = isOpen ? currentScreen : ShellScreens.underPointer()
        guard let target, !suspendedScreens.contains(target.displayID),
              let area = hoverArea(on: target, open: isOpen)
        else { return }
        let next = hoverState.moved(inArea: area.contains(NSEvent.mouseLocation))
        if next.visible && !isOpen {
            open(byHover: true, on: target)
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

    // MARK: - Switching screens

    /// Reconnected or resolution changed: if the open window's screen is
    /// gone, it closes - otherwise it would sit on a frame that no longer
    /// exists. If it is still there, it is remeasured.
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

    // MARK: - Geometry

    /// Window = visible + radius at every edge it sticks to (plus the
    /// menu-bar strip at the top).
    private static func windowSize(for edge: DrawerEdge, size: NSSize, radius: CGFloat, topInset: CGFloat) -> NSSize {
        switch edge {
        case .top: NSSize(width: size.width, height: size.height + topInset + radius)
        case .right: NSSize(width: size.width + radius, height: size.height)
        case .bottomRight: NSSize(width: size.width + radius, height: size.height + radius)
        case .bottom: NSSize(width: size.width, height: size.height + radius)
        }
    }

    /// Where the visible part sits in the window (AppKit coordinates, y up).
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
            // Glass flush with the top edge (above the menu bar), the
            // radius strip overhangs the screen. It used to end below the
            // menu bar - with macOS 26's translucent menu bar that looked
            // like a floating window with a gap.
            return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - topInset - size.height,
                          width: windowSize.width, height: windowSize.height)
        case .right:
            return NSRect(x: frame.maxX - size.width, y: frame.midY - size.height / 2,
                          width: windowSize.width, height: windowSize.height)
        case .bottomRight:
            return NSRect(x: frame.maxX - size.width, y: frame.minY - cornerRadius,
                          width: windowSize.width, height: windowSize.height)
        case .bottom:
            // Flush with the bottom edge; the bottom corners overhang.
            return NSRect(x: frame.midX - size.width / 2, y: frame.minY - cornerRadius,
                          width: windowSize.width, height: windowSize.height)
        }
    }

    // MARK: - Motion

    /// Sets the content offset, either animated or immediately. Always
    /// starts from the visible value, so flipping mid-motion does not jump.
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

    // MARK: - Window

    private func makePanel() -> DrawerPanel {
        // With dimming, one level above.
        let level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + (scrim == nil ? 0 : 1))
        let panel = DrawerPanel(size: container.frame.size, level: level, takesKeyboard: takesKeyboard)
        panel.delegate = self
        panel.setPinned(isPinned)
        panel.onEscape = { [weak self] in
            guard let self, !self.isPinned else { return }
            self.close()
        }

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
        if closesOnResignKey && !isPinned { close() }
    }
}

/// Borderless panel for edge windows. A level above everything, like the
/// session menu - at the top also above the menu bar, so the glass reaches
/// to the edge. May overhang the screen border.
final class DrawerPanel: ShellPanel {
    var onEscape: () -> Void = {}

    /// Behavior/subrole/window menu outside of editing - what
    /// `setPinned(false)` restores.
    private static let unpinnedBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
    /// While `EdgeDrawer.isPinned` (Spec Section 4): like `EditModePanel`,
    /// but only for that long - see `isPinned`.
    private static let pinnedBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

    init(size: NSSize, level: NSWindow.Level, takesKeyboard: Bool) {
        super.init(size: size, level: level,
                   behavior: Self.unpinnedBehavior,
                   takesKeyboard: takesKeyboard, mayLeaveScreen: true)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }

    /// Task 7 (Spec Section 4, "window-manager-safe"): while editing, a
    /// window manager should leave the pinned edge window exactly as
    /// untouched as the edit mode's own windows (`EditModePanel`) -
    /// `.stationary` instead of `.transient`, a non-standard subrole and
    /// out of the window menu. Unpinning restores the three previous
    /// values.
    func setPinned(_ pinned: Bool) {
        collectionBehavior = pinned ? Self.pinnedBehavior : Self.unpinnedBehavior
        setAccessibilitySubrole(pinned ? .unknown : nil)
        isExcludedFromWindowsMenu = pinned
    }
}

/// Fullscreen dimming behind an edge window (`DrawerScrim`). Sits above the
/// menu bar and Dock, catches clicks and then closes the window.
final class ScrimWindow: ShellPanel {
    var onClick: () -> Void = {}

    init() {
        super.init(level: .popUpMenu, behavior: [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary])
        backgroundColor = .black
        contentView = ClickView { [weak self] in self?.onClick() }
    }
}

/// Accepts even the very first click, even if the app is not active.
private final class ClickView: NSView {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { action() }
}
