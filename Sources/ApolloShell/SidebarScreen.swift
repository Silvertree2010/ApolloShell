import AppKit
import ApolloShellCore
import os
import SwiftUI

/// The bar of ONE screen: its window, its view and its status popout. The
/// models in it belong to the manager and are shared.
@MainActor
final class SidebarScreen {
    private let panel = SidebarPanel()
    private let log = Logger(category: "sidebar")
    /// The detail window of the status capsule (Wi-Fi, Bluetooth, battery). It
    /// lies in the window of this bar and makes it wider while it is open.
    private let popout = StatusPopout()
    /// Which screen this is - refreshed on every rebuild.
    private(set) var info: ScreenInfo
    private var frame: NSRect
    private var visibleTop: CGFloat
    /// The last valid frame. Without it the bar does not show itself.
    private var lastFrame: NSRect?
    private var expanded = false
    /// The foreground app is in full screen on THIS screen.
    private(set) var isHiddenForFullscreen = false
    /// This popout opens - the manager closes the others.
    var onPopoutOpen: (ObjectIdentifier) -> Void = { _ in }

    init(screen: ShellScreen, settings: ShellSettingsStore, context: BarModuleContext, editor: ShellEditor? = nil) {
        info = screen.info
        frame = screen.frame
        visibleTop = screen.visibleFrame.maxY

        // SwiftUI draws the glass (`SidebarRoot`), not NSGlassEffectView: only
        // in the same GlassEffectContainer does the popout merge with the
        // bar.
        let hosting = FirstMouseHostingView(
            rootView: SidebarRoot(settings: settings, context: context, popout: popout.model, editor: editor).shellTheme()
        )
        // Without this the view has a say in the window size and fights with
        // `layout()` as soon as the window grows wider for a popout.
        hosting.sizingOptions = []
        // The transparent part of the wide window has to be cleared, otherwise
        // whatever was on the screen before keeps standing there.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        panel.contentView = hosting
        popout.hostWindow = panel
        popout.setExpanded = { [weak self] in self?.setExpanded($0) }
        popout.onOpen = { [weak self] in
            guard let self else { return }
            self.onPopoutOpen(ObjectIdentifier(self))
        }
        // SwiftUI reports symbol frames in view coordinates (top = 0,
        // NSHostingView is flipped); AppKit converts them through the window
        // onto the screen.
        popout.screenRect = { [weak hosting] rect in
            guard let hosting, let window = hosting.window else { return nil }
            return window.convertToScreen(hosting.convert(rect, to: nil))
        }

        layout()
        showIfNeeded()
    }

    /// The same screen, but maybe with new measurements or in a new
    /// place.
    func update(screen: ShellScreen) {
        info = screen.info
        frame = screen.frame
        visibleTop = screen.visibleFrame.maxY
        layout()
        showIfNeeded()
    }

    /// The screen is gone or deselected: close the popout, remove the window.
    func tearDown() {
        popout.close()
        panel.orderOut(nil)
        lastFrame = nil
    }

    func closePopout() {
        popout.close()
    }

    /// Full screen on: away. Full screen off: back again. `.canJoinAllSpaces`
    /// would otherwise fetch the panel into full-screen spaces too (see `SidebarPanel`).
    ///
    /// Invisible and click-through instead of `orderOut`: the message "no
    /// more full screen" comes back in the middle of the swipe animation to
    /// the desktop. A panel shown again at that point hung, measured, on
    /// this one space only and was missing on all the others. When it stays
    /// shown, it keeps all spaces.
    func setHiddenForFullscreen(_ hidden: Bool) {
        guard hidden != isHiddenForFullscreen else { return }
        isHiddenForFullscreen = hidden
        log.notice("Sidebar \(hidden ? "weg (Vollbild)" : "wieder da", privacy: .public)")
        if hidden {
            // Without a bar the popout would have nothing to hang on.
            popout.close()
        }
        panel.alphaValue = hidden ? 0 : 1
        panel.ignoresMouseEvents = hidden
        if !hidden { showIfNeeded() }
    }

    /// Only bring it forward when it should be visible and is not right now.
    /// An unconditional orderFrontRegardless on every space change can flicker
    /// during Mission Control. (The first version did that, because overlay
    /// panels went missing after space changes now and then; if it goes
    /// missing despite `isVisible`, this is the place for it.)
    private func showIfNeeded() {
        guard lastFrame != nil, !panel.isVisible else { return }
        panel.orderFrontRegardless()
    }

    /// With the popout open: a wider window, the bar stays 44 wide on the
    /// left, the rest is transparent until the glass grows into it.
    private func setExpanded(_ expanded: Bool) {
        guard expanded != self.expanded else { return }
        self.expanded = expanded
        layout()
    }

    /// At the left edge of this screen: down to the edge, up to the bottom
    /// edge of the menu bar. Screens without a menu bar have no deduction
    /// there, and then the bar reaches all the way to the top.
    private func layout() {
        let width = expanded ? StatusPopout.expandedWidth : Sidebar.width
        let rect = NSRect(x: frame.minX, y: frame.minY, width: width, height: visibleTop - frame.minY)
        lastFrame = rect
        // Compare with the real panel frame, not with `lastFrame`: macOS moves
        // windows by itself when a screen is replugged.
        guard panel.frame != rect else { return }
        panel.setFrame(rect, display: true)
    }
}

/// A borderless panel that never takes focus.
///
/// - Level `.floating`: above normal windows, below the Dock (20) and the
///   menu bar (24). Because the bar ends below the menu bar, the two never
///   get in each other's way.
/// - On all spaces, stays put when swiping between spaces, not in Cmd+Tab.
///   Without `.fullScreenAuxiliary` - which on its own does NOT keep it out
///   of full-screen spaces on macOS 26(a full-screen space is a space too,
///   and `.canJoinAllSpaces` counts there). No combination of level and
///   collectionBehavior manages that; so `FullscreenMonitor` recognises full
///   screen itself, and the bar becomes invisible and click-through there
///   (see `setHiddenForFullscreen`).
/// - No window shadow: on the launcher that gave a second, almost square
///   frame around the glass.
/// - `canHide = false`: "Hide Others" should not make it disappear.
final class SidebarPanel: ShellPanel {
    init() {
        super.init(level: .floating, behavior: [.canJoinAllSpaces, .stationary, .ignoresCycle], deferred: false)
        canHide = false
        becomesKeyOnlyIfNeeded = true
    }
}
