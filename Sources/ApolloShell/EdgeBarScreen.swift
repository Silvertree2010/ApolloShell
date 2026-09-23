import AppKit
import ApolloShellCore
import os
import SwiftUI

/// The bar along one edge (top, bottom, right) of ONE screen: its window and
/// its view. Like `SidebarScreen`, but without a status popout yet; the
/// models belong to the manager (`Sidebar`) and are shared by all bars.
@MainActor
final class EdgeBarScreen {
    let edge: BarEdge
    private let panel = EdgeBarPanel()
    private let state = EdgeBarPanelState()
    private let log = Logger(category: "sidebar")
    /// Which screen this is - refreshed on every rebuild.
    private(set) var info: ScreenInfo
    /// The last valid frame. Without it the bar does not show itself.
    private var lastFrame: NSRect?
    /// The foreground app is in full screen on THIS screen.
    private(set) var isHiddenForFullscreen = false

    init(edge: BarEdge, screen: ShellScreen, settings: ShellSettingsStore, context: BarModuleContext) {
        self.edge = edge
        info = screen.info
        let hosting = FirstMouseHostingView(
            rootView: EdgeBarRoot(settings: settings, edge: edge, state: state, context: context).shellTheme()
        )
        // The window size is the manager's (`EdgeBarGeometry`), not the view's.
        hosting.sizingOptions = []
        // Islands leave most of the panel transparent: clear it, or whatever
        // stood there before keeps showing.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        panel.contentView = hosting
    }

    /// New measurements from the manager.
    ///
    /// - `frame`: from `EdgeBarGeometry` for this screen.
    /// - `coversMenuBar`: a top bar over Apple's menu bar has to stand above
    ///   it (level 25, measured 22.09.: the menu bar is 24, its status items
    ///   25) and meets the camera housing; everything else stays at the
    ///   sidebar's level, below the Dock and the menu bar.
    func update(screen: ShellScreen, frame: NSRect, coversMenuBar: Bool) {
        info = screen.info
        let covers = edge == .top && coversMenuBar
        let level: NSWindow.Level = covers ? .statusBar : .floating
        if panel.level != level { panel.level = level }
        let notch = covers ? BarNotch(screenMinX: screen.frame.minX, leftArea: screen.screen.auxiliaryTopLeftArea,
                                      rightArea: screen.screen.auxiliaryTopRightArea) : nil
        if state.notch != notch { state.notch = notch }
        lastFrame = frame
        // Compare with the real panel frame: macOS moves windows by itself
        // when a screen is replugged.
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        showIfNeeded()
    }

    #if DEBUG
    var debugLevel: Int { panel.level.rawValue }
    #endif

    /// The screen is gone, deselected, or the bar was switched off.
    func tearDown() {
        panel.orderOut(nil)
        lastFrame = nil
    }

    /// Full screen on: invisible and click-through, not ordered out - the
    /// same reasons as `SidebarScreen.setHiddenForFullscreen` (a panel shown
    /// again mid-swipe stuck to one space).
    func setHiddenForFullscreen(_ hidden: Bool) {
        guard hidden != isHiddenForFullscreen else { return }
        isHiddenForFullscreen = hidden
        log.notice("\(self.edge.rawValue, privacy: .public) bar \(hidden ? "away (full screen)" : "back", privacy: .public)")
        panel.alphaValue = hidden ? 0 : 1
        panel.ignoresMouseEvents = hidden
        if !hidden { showIfNeeded() }
    }

    /// Only bring it forward when it should be visible and is not - see
    /// `SidebarScreen.showIfNeeded` for why not unconditionally.
    private func showIfNeeded() {
        guard lastFrame != nil, !panel.isVisible else { return }
        panel.orderFrontRegardless()
        // Stays still while switching desktops (`StickySpace`).
        StickySpace.pin(panel)
    }
}

/// A borderless panel that never takes focus - the sidebar's panel
/// (`SidebarPanel`, see there for the reasons) with a level chosen per bar by
/// `EdgeBarScreen.update`. `canHide = false`: "Hide Others" must not take
/// the bars along.
final class EdgeBarPanel: ShellPanel {
    init() {
        super.init(level: .floating, behavior: [.canJoinAllSpaces, .stationary, .ignoresCycle], deferred: false)
        canHide = false
        becomesKeyOnlyIfNeeded = true
    }
}
