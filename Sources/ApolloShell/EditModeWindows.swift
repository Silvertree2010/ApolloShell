import AppKit
import ApolloShellCore
import os
import SwiftUI

// The windows of global edit mode (design/2026-09-18-bento-
// dashboard.md section 4, design/2026-09-19-shell-edit-plan.md task 3):
// a scrim over every screen, a floating toolbar and a floating gallery on
// the screen where the mode began. Dashboard and Control Center remain
// their own edge windows (`Dashboard`, `UtilitiesPanel`) and pin themselves
// via `ShellEditor.addBeginHandler`.

/// Levels of the mode windows relative to the pinned edge windows
/// (`EdgeDrawer` uses `.popUpMenu`, with its own scrim `.popUpMenu + 1` -
/// only the session menu has one). The mode's scrim sits just below that,
/// so it doesn't dim the Dashboard and Control Center; the toolbar and
/// gallery sit above, so they stand above everything.
enum EditModeLevel {
    static let scrim = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
    static let controls = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
}

/// Basis of every edit-mode window: borderless, non-activating, on all
/// spaces, not in the window menu, with a non-standard accessibility
/// subrole - this way window managers like AeroSpace, yabai or Amethyst
/// leave it alone (they don't tile, move or hide it), see the "Robustness"
/// section of the spec and task 6 (debug log of the actual values).
class EditModePanel: ShellPanel {
    init(size: NSSize = .zero, level: NSWindow.Level, takesKeyboard: Bool = false) {
        super.init(
            size: size, level: level,
            // On every space, even in another app's fullscreen on a second
            // screen; `stationary` keeps it under the pointer during a
            // space switch instead of moving along; `ignoresCycle` takes it
            // out of Cmd+Tab/Cmd+`.
            behavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle],
            takesKeyboard: takesKeyboard, mayLeaveScreen: true
        )
        // "Floating window" instead of a normal document window: the
        // dedicated category for tool palettes that most window managers
        // exempt from their window management. AppKit itself sets
        // `self.level = .floating` in the process (measured 09-19: scrim/
        // toolbar/gallery ended up below the menu bar, Dock and the pinned
        // edge windows because of this) - so set the desired level again
        // afterward.
        isFloatingPanel = true
        self.level = level
        // No tool palette in the window menu - that should only list
        // documents of user apps, not the shell's own editing surface.
        isExcludedFromWindowsMenu = true
        // Non-standard subrole: scripts/extensions that search for
        // "normal" windows via accessibility (many window managers do
        // this) skip it as an additional safeguard beyond level and
        // `collectionBehavior`.
        setAccessibilitySubrole(.unknown)
        Self.logCreation(level: self.level, behavior: collectionBehavior, subrole: accessibilitySubrole())
    }

    /// Task 6: for the live test with AeroSpace/yabai/Amethyst - the actual
    /// values, not just the intent in the code. DEBUG only, not shipped
    /// behavior (just one log entry, `Logger` is stripped in release
    /// builds anyway). `level` here is always `self.level` after
    /// `isFloatingPanel`, never the parameter from `init` - otherwise the
    /// log would have shown the broken state before the fix above.
    #if DEBUG
    private static let log = Logger(category: "edit-mode-windows")
    private static func logCreation(level: NSWindow.Level, behavior: NSWindow.CollectionBehavior, subrole: NSAccessibility.Subrole?) {
        log.debug("Edit mode window: level \(level.rawValue, privacy: .public), behavior \(behavior.rawValue, privacy: .public), subrole \(subrole?.rawValue ?? "-", privacy: .public)")
    }
    #else
    private static func logCreation(level: NSWindow.Level, behavior: NSWindow.CollectionBehavior, subrole: NSAccessibility.Subrole?) {}
    #endif
}

/// Builds a glass panel with SwiftUI content, placed centered over a point
/// on the screen, and fades it in/out. Shared code for the toolbar and the
/// gallery - both are pure content panels without an edge, unlike
/// `EdgeDrawer` (which sticks to a screen edge and has a radius overhang).
@MainActor
final class FloatingGlassPanel<Content: View> {
    private let panel: EditModePanel
    private let glass: NSGlassEffectView
    private let hosting: FirstMouseHostingView<AnyView>
    private var panelLayer: CAGradientLayer?
    /// Like `EdgeDrawer.generation`: a quick hide-then-show-again (leaving
    /// the mode, immediately starting it again) must not be hit by the
    /// delayed `orderOut` of the old `hide()` - otherwise the panel that
    /// was just shown again disappears once the old fade-out animation
    /// finishes.
    private var generation = 0

    init(cornerRadius: CGFloat, takesKeyboard: Bool, level: NSWindow.Level, @ViewBuilder content: @escaping () -> Content) {
        panel = EditModePanel(level: level, takesKeyboard: takesKeyboard)
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        // `FirstMouseHostingView` like the bar, toasts and edge windows:
        // the panel never becomes the key window (`takesKeyboard: false`),
        // and a normal `NSHostingView` swallows the first click in that
        // case - for a window that never becomes key, practically every
        // click. Toolbar buttons and dragging from the gallery otherwise
        // didn't react (live test 09-19).
        let hosting = FirstMouseHostingView(rootView: AnyView(content().shellTheme()))
        hosting.sizingOptions = [.intrinsicContentSize]
        // Hosting in its own container, as with the edge windows
        // (`EdgeDrawer.makePanel`): `ThemedGlass` places the theme surface
        // in the glass's `contentView`. If that were the hosting view
        // directly, the color surface would sit in its layers ABOVE the
        // SwiftUI content - toolbar and gallery appeared empty with the
        // theme applied (live test 09-19; screenshots and the self-test
        // run without a theme).
        let content = NSView()
        hosting.autoresizingMask = [.width, .height]
        content.addSubview(hosting)
        glass.contentView = content
        panel.contentView = glass
        self.glass = glass
        self.hosting = hosting
        panelLayer = ThemedGlass.apply(to: glass, fallbackRadius: cornerRadius)
    }

    /// Shows the panel centered over `point` on `screen` (window
    /// coordinates, y upward), shifted up by `raise` (this way the toolbar
    /// gets out of the way of the Control Center panel).
    func show(on screen: NSScreen, centeredAt point: NSPoint, raise: CGFloat = 0) {
        generation += 1
        panelLayer = ThemedGlass.apply(to: glass, fallbackRadius: panel.contentView == nil ? 0 : glass.cornerRadius, previous: panelLayer)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(size)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.setFrameOrigin(NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2 + raise))
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionCurve.spatialDuration
            context.timingFunction = .shellSpatial
            panel.animator().alphaValue = 1
        }
    }

    /// Re-measure and reposition if the content has changed (gallery tab
    /// switched, toolbar should get out of the way of the Control Center)
    /// - without fading in/out.
    func reposition(on screen: NSScreen, centeredAt point: NSPoint, raise: CGFloat = 0) {
        guard panel.isVisible else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(size)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.setFrameOrigin(NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2 + raise))
    }

    func hide() {
        guard panel.isVisible else { return }
        generation += 1
        let current = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = MotionCurve.spatialDuration
            context.timingFunction = .shellSpatial
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, panel] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                panel.orderOut(nil)
            }
        })
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }
    var level: Int { panel.level.rawValue }
    #if DEBUG
    var debugWindow: NSWindow { panel }
    #endif

    #if DEBUG
    /// Self-test: a click (press, release) sent directly to this window,
    /// `point` in window coordinates from the top left - not routed through
    /// the system, the real mouse stays untouched.
    func debugClick(fromTopLeft point: NSPoint) {
        let location = NSPoint(x: point.x, y: panel.frame.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: panel.windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            panel.sendEvent(event)
        }
    }
    #endif

    /// Measured size of the content (for placement before showing).
    var size: NSSize {
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }
}

/// Dimming of a single screen during editing: about 35% black over a
/// light blur (`.hudWindow`, dark and subdued like macOS's own HUD
/// palettes). A click only clears the selection - unlike `ScrimWindow`
/// (edge window) it never ends the mode, see section 4: "clicks on the
/// scrim only clear the selection".
final class EditModeScrimView: NSView {
    var onClick: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let effect = NSVisualEffectView(frame: bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        addSubview(effect)
        let dim = NSView(frame: bounds)
        dim.autoresizingMask = [.width, .height]
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        addSubview(dim)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }
}

@MainActor
final class EditModeScrimPanel {
    private let panel: EditModePanel
    private let view: EditModeScrimView
    /// See `FloatingGlassPanel.generation`.
    private var generation = 0

    var onClick: () -> Void {
        get { view.onClick }
        set { view.onClick = newValue }
    }

    init() {
        panel = EditModePanel(level: EditModeLevel.scrim)
        view = EditModeScrimView(frame: .zero)
        panel.contentView = view
    }

    var isVisible: Bool { panel.isVisible }
    var level: Int { panel.level.rawValue }
    #if DEBUG
    var debugWindow: NSWindow { panel }
    #endif

    #if DEBUG
    /// Self-test: click in the center of the scrim.
    func debugClickCenter() {
        let location = NSPoint(x: panel.frame.width / 2, y: panel.frame.height / 2)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: panel.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1) {
                panel.sendEvent(e)
            }
        }
    }
    #endif

    func show(on screen: NSScreen) {
        generation += 1
        panel.setFrame(screen.frame, display: true)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionCurve.spatialDuration
            context.timingFunction = .shellSpatial
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        generation += 1
        let current = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = MotionCurve.spatialDuration
            context.timingFunction = .shellSpatial
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, panel] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                panel.orderOut(nil)
            }
        })
    }
}

/// Holds an `EditModeScrimPanel` for every screen, a toolbar and a gallery
/// on the screen where the mode began. Registers with `ShellEditor`
/// (`addBeginHandler`/`addEndHandler`) and observes `editor.galleryVisible`
/// to show or hide the gallery without callers needing their own callback.
@MainActor
final class EditModeWindows {
    private let editor: ShellEditor
    private var scrims: [ObjectIdentifier: EditModeScrimPanel] = [:]
    private var toolbar: FloatingGlassPanel<EditToolbarView>?
    private var gallery: FloatingGlassPanel<EditGalleryView>?
    private var editScreen: NSScreen?
    /// Frame of the pinned panels on the editing screen (`nil` while
    /// closed). The toolbar and gallery orient themselves by it: the
    /// gallery under the dashboard instead of right on top of it, the
    /// toolbar above the Control Center only if it would really overlap it
    /// horizontally. Before: the gallery was always in the screen center
    /// (on a 14-inch display, over the bottom third of the dashboard) and
    /// the toolbar was always raised by the full panel height (right up to
    /// the dashboard), even though the Control Center sits on the right.
    var dashboardFrame: () -> NSRect? = { nil }
    var utilitiesFrame: () -> NSRect? = { nil }
    private var galleryObservation: Task<Void, Never>?
    /// The toolbar ("Discard changes?" instead of the three buttons) and
    /// gallery (notice "No room on this page") change their size without
    /// fading in/out - without their own re-measurement the text stayed
    /// cut off (measured 09-19).
    private var toolbarSizeObservation: Task<Void, Never>?
    private var galleryNoticeObservation: Task<Void, Never>?

    init(editor: ShellEditor) {
        self.editor = editor
        editor.addBeginHandler { [weak self] screen in self?.begin(on: screen) }
        editor.addEndHandler { [weak self] in self?.end() }
    }

    /// Task 6: the intended order of the levels as a DEBUG check, not just
    /// a comment - normal windows < sidebar (`.floating`) < scrim <
    /// pinned edge windows (`EdgeDrawer`, `.popUpMenu`/+1) <
    /// toolbar/gallery, and the scrim above the menu bar and Dock. Fails
    /// immediately in debug builds instead of only being noticed later in
    /// a live test with AeroSpace/yabai/Amethyst.
    #if DEBUG
    private static let stackingLog = Logger(category: "edit-mode-windows")
    private static func assertStackingOrder() {
        assert(EditModeLevel.scrim.rawValue > NSWindow.Level.mainMenu.rawValue,
               "Scrim must be above the menu bar and Dock")
        assert(EditModeLevel.scrim.rawValue < NSWindow.Level.popUpMenu.rawValue,
               "Scrim must be below the pinned edge windows")
        assert(EditModeLevel.controls.rawValue > NSWindow.Level.popUpMenu.rawValue + 1,
               "Toolbar/gallery must be above the pinned edge windows")
        stackingLog.debug("""
            Edit mode levels: sidebar \(NSWindow.Level.floating.rawValue, privacy: .public), \
            scrim \(EditModeLevel.scrim.rawValue, privacy: .public), \
            edge windows \(NSWindow.Level.popUpMenu.rawValue, privacy: .public)/+1, \
            toolbar/gallery \(EditModeLevel.controls.rawValue, privacy: .public)
            """)
    }
    #else
    private static func assertStackingOrder() {}
    #endif

    private func begin(on screen: NSScreen) {
        Self.assertStackingOrder()
        editScreen = screen
        for candidate in NSScreen.screens {
            let scrim = scrims[ObjectIdentifier(candidate)] ?? {
                let panel = EditModeScrimPanel()
                panel.onClick = { [weak self] in
                    // Click elsewhere: clear every selection (and thus any
                    // open options popover), in both panels.
                    self?.editor.dashboard.selectedWidgetID = nil
                    self?.editor.selectedToggleID = nil
                    self?.editor.selectedBarEntryID = nil
                    self?.editor.dashboard.renamingPageID = nil
                }
                scrims[ObjectIdentifier(candidate)] = panel
                return panel
            }()
            scrim.show(on: candidate)
        }
        let toolbar = self.toolbar ?? {
            let panel = FloatingGlassPanel(cornerRadius: 26, takesKeyboard: false, level: EditModeLevel.controls) {
                EditToolbarView(editor: self.editor)
            }
            self.toolbar = panel
            return panel
        }()
        let gallery = self.gallery ?? {
            let panel = FloatingGlassPanel(cornerRadius: 22, takesKeyboard: false, level: EditModeLevel.controls) {
                EditGalleryView(editor: self.editor)
            }
            self.gallery = panel
            return panel
        }()
        placeToolbar(toolbar, on: screen)
        placeGallery(gallery, on: screen)
        // The Dashboard's and Control Center's listeners run in the same
        // `begin` - depending on order, sometimes only after this one.
        // Their frames are settled immediately after opening (the
        // movement is just a level shift), so reposition again one cycle
        // later.
        DispatchQueue.main.async { [weak self] in
            self?.repositionToolbar()
            self?.repositionGallery()
        }
        if editor.galleryVisible { gallery.show(on: screen, centeredAt: galleryCenter(on: screen)) }
        observeGallery()
        observeToolbarSize()
        observeGalleryNotice()
        observeDashboardScale()
    }

    private func end() {
        for scrim in scrims.values { scrim.hide() }
        toolbar?.hide()
        gallery?.hide()
        galleryObservation?.cancel()
        galleryObservation = nil
        toolbarSizeObservation?.cancel()
        toolbarSizeObservation = nil
        galleryNoticeObservation?.cancel()
        galleryNoticeObservation = nil
        dashboardScaleObservation?.cancel()
        dashboardScaleObservation = nil
        editScreen = nil
    }

    /// Reacts to `editor.galleryVisible` (toolbar, task 4 popover Esc),
    /// without every caller needing to know the windows themselves.
    private func observeGallery() {
        galleryObservation?.cancel()
        galleryObservation = Task { [weak self] in
            guard let self else { return }
            for await visible in Observations({ self.editor.galleryVisible }) {
                guard let screen = self.editScreen, let gallery = self.gallery else { continue }
                if visible {
                    gallery.show(on: screen, centeredAt: self.galleryCenter(on: screen))
                } else {
                    gallery.hide()
                }
            }
        }
    }

    /// Re-measure the toolbar as soon as `editor.pendingCancelConfirmation`
    /// flips (task 6: "Discard changes?" instead of the three buttons is
    /// wider/a different height).
    private func observeToolbarSize() {
        toolbarSizeObservation?.cancel()
        toolbarSizeObservation = Task { [weak self] in
            guard let self else { return }
            for await _ in Observations({ self.editor.pendingCancelConfirmation }) {
                self.repositionToolbar()
            }
        }
    }

    /// Everything that changes the gallery's height: the notice (task 3:
    /// "No room on this page" needs more height than the grid alone), the
    /// tab (every surface brings its own number of tiles) and "Show all"
    /// (more kinds on the dashboard tab). Without this the panel keeps the
    /// height it was opened with and cuts off the last row.
    private struct GallerySize: Equatable, Sendable {
        let notice: String?
        let tab: GalleryTab
        let showsAll: Bool
    }

    private func observeGalleryNotice() {
        galleryNoticeObservation?.cancel()
        galleryNoticeObservation = Task { [weak self] in
            guard let self else { return }
            for await _ in Observations({
                GallerySize(notice: self.editor.galleryNotice, tab: self.editor.galleryTab,
                            showsAll: self.editor.showsAllInGallery)
            }) {
                // One cycle later, like the scale observer below: SwiftUI
                // only lays the new tiles out after this turn, and
                // `reposition` measures the hosting view as it stands.
                DispatchQueue.main.async { [weak self] in self?.repositionGallery() }
            }
        }
    }

    /// Toolbar slider: the dashboard changes its size, the gallery follows
    /// one cycle later (under the new bottom edge).
    private var dashboardScaleObservation: Task<Void, Never>?
    private func observeDashboardScale() {
        dashboardScaleObservation?.cancel()
        dashboardScaleObservation = Task { [weak self] in
            guard let self else { return }
            for await _ in Observations({ self.editor.dashboard.scale }) {
                DispatchQueue.main.async { [weak self] in self?.repositionGallery() }
            }
        }
    }

    private func repositionToolbar() {
        guard let screen = editScreen, let toolbar else { return }
        toolbar.reposition(on: screen, centeredAt: toolbarCenter(on: screen, size: toolbar.size))
    }

    private func repositionGallery() {
        guard let screen = editScreen, let gallery else { return }
        gallery.reposition(on: screen, centeredAt: galleryCenter(on: screen))
    }

    /// Bottom center; if it would overlap the Control Center there
    /// (narrow screen), just above its top edge instead.
    private func toolbarCenter(on screen: NSScreen, size: NSSize) -> NSPoint {
        let bottom = screen.visibleFrame.minY + 20
        var center = NSPoint(x: screen.frame.midX, y: bottom + size.height / 2)
        let rect = NSRect(x: center.x - size.width / 2, y: bottom, width: size.width, height: size.height)
        if let utilities = utilitiesFrame(), utilities.intersects(rect.insetBy(dx: -8, dy: -8)) {
            center.y = utilities.maxY + 16 + size.height / 2
        }
        return center
    }

    /// From the Control Center panel (`UtilitiesPanel.onHeightChange`): if
    /// it grows or shrinks during editing (card off/on, button added/
    /// removed), the toolbar immediately gets out of the way instead of
    /// only on the next screen change.
    func utilitiesHeightChanged() {
        guard editor.isEditing else { return }
        repositionToolbar()
    }

    private func placeToolbar(_ toolbar: FloatingGlassPanel<EditToolbarView>, on screen: NSScreen) {
        toolbar.show(on: screen, centeredAt: toolbarCenter(on: screen, size: toolbar.size))
    }

    /// Only measure/place, don't show it - `editor.galleryVisible` handles
    /// that via `observeGallery()`.
    private func placeGallery(_ gallery: FloatingGlassPanel<EditGalleryView>, on screen: NSScreen) {
        gallery.reposition(on: screen, centeredAt: galleryCenter(on: screen))
    }

    /// Centered between the bottom edge of the dashboard and the toolbar;
    /// in the screen center if no dashboard is open. If it doesn't quite
    /// fit there (small screen), it stays at least under the dashboard.
    #if DEBUG
    /// For `EditModeSelfTest`: what's actually on the screen right now.
    var debugVisibleScrims: Int { scrims.values.filter(\.isVisible).count }
    var debugToolbarFrame: NSRect? { toolbar.flatMap { $0.isVisible ? $0.frame : nil } }
    var debugGalleryFrame: NSRect? { gallery.flatMap { $0.isVisible ? $0.frame : nil } }
    var debugLevels: (scrim: Int, controls: Int) { (EditModeLevel.scrim.rawValue, EditModeLevel.controls.rawValue) }
    func debugClickToolbar(fromTopLeft point: NSPoint) { toolbar?.debugClick(fromTopLeft: point) }
    func debugClickScrim() { scrims.values.first(where: \.isVisible)?.debugClickCenter() }
    func debugClickGallery(fromTopLeft point: NSPoint) { gallery?.debugClick(fromTopLeft: point) }
    /// For the window-manager check of the self-test: every window of the
    /// mode with a name, in the order they are stacked.
    var debugWindows: [(String, NSWindow)] {
        scrims.values.enumerated().map { ("scrim \($0.offset + 1)", $0.element.debugWindow) }
            + [toolbar.map { ("toolbar", $0.debugWindow) }, gallery.map { ("gallery", $0.debugWindow) }].compactMap { $0 }
    }

    var debugPanelLevels: [Int] {
        scrims.values.map(\.level) + [toolbar?.level, gallery?.level].compactMap { $0 }
    }
    #endif

    private func galleryCenter(on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        guard let dashboard = dashboardFrame(), dashboard.intersects(screen.frame) else {
            return NSPoint(x: visible.midX, y: visible.midY)
        }
        let top = min(dashboard.minY, visible.maxY) - 16
        let bottom = visible.minY + 20 + (toolbar?.size.height ?? 56) + 16
        let height = gallery?.size.height ?? 380
        // Enough room under the dashboard: center it there. Otherwise
        // (large scale, measured at 150%: the gallery slid under the edge
        // and over the toolbar) directly above the toolbar - it then
        // covers the bottom part of the dashboard, which can't be avoided
        // at that size; "+" hides it again.
        let centerY = top - bottom >= height ? (top + bottom) / 2 : bottom + height / 2
        return NSPoint(x: visible.midX, y: centerY)
    }
}
