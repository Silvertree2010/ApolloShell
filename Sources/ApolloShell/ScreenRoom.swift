import AppKit
import ApolloShellCore

/// The room the edge bars leave on each screen - the one place panels ask
/// before they place themselves against the screen.
///
/// macOS's `visibleFrame` only knows the menu bar and Apple's Dock, so a
/// panel anchored to it (the Dashboard below the menu bar, say) dropped
/// straight over a top bar. The bar manager (`Sidebar`) works out every
/// screen's bars and hands their reach here after each rebuild; panels ask
/// for
/// - `usableFrame`: `visibleFrame` without the bars - for panels that avoid
///   the menu bar and the Dock (Nexus panel, desktop clock, edit mode);
/// - `barFreeFrame`: the whole screen without the bars - for panels that
///   grow out of a screen edge (Dashboard, Utilities, Launcher, session
///   menu, toasts), which then grow out of the bar's inner edge instead.
///
/// The sidebar is left out on purpose: those panels already reckon with it
/// on their own, and with no edge bar on every answer is exactly what it was
/// before edge bars existed (the arithmetic, and that promise, are tested in
/// `EdgeBarGeometryTests`).
@MainActor
enum ScreenRoom {
    /// Bar reach per display, only screens with an edge bar.
    private static var insets: [CGDirectDisplayID: ReservedInsets] = [:]
    private static var observers: [@MainActor () -> Void] = []

    /// From the bar manager after every rebuild. Tells the observers only
    /// when something moved.
    static func update(_ new: [CGDirectDisplayID: ReservedInsets]) {
        let kept = new.filter { !$0.value.isZero }
        guard kept != insets else { return }
        insets = kept
        for observer in observers { observer() }
    }

    /// Edge bars switched on, off, thicker or thinner: for panels that stand
    /// all the time (desktop clock) and must move along. Lives as long as
    /// the process, like `ShellScreens.onChange`.
    static func onChange(_ handler: @escaping @MainActor () -> Void) {
        observers.append(handler)
    }

    /// How far the edge bars reach in from each edge of the full screen
    /// frame; zero without edge bars.
    static func barInsets(of screen: NSScreen) -> ReservedInsets {
        ShellScreens.displayID(of: screen).flatMap { insets[$0] } ?? .zero
    }

    static func usableFrame(of screen: NSScreen) -> NSRect {
        EdgeBarGeometry.usableFrame(visible: screen.visibleFrame, screen: screen.frame, bars: barInsets(of: screen))
    }

    static func barFreeFrame(of screen: NSScreen) -> NSRect {
        EdgeBarGeometry.barFreeFrame(screen: screen.frame, bars: barInsets(of: screen))
    }
}

@MainActor
extension ShellScreen {
    /// `visibleFrame` without the edge bars (`ScreenRoom`).
    var usableFrame: NSRect { ScreenRoom.usableFrame(of: screen) }
    /// The whole frame without the edge bars (`ScreenRoom`).
    var barFreeFrame: NSRect { ScreenRoom.barFreeFrame(of: screen) }
}
