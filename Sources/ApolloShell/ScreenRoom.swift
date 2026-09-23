import AppKit
import ApolloShellCore

/// The room the menu bar leaves on each screen - the one place panels ask
/// before they place themselves against the screen.
///
/// macOS's `visibleFrame` only knows the menu bar and Apple's Dock, so a
/// panel anchored to it (the Dashboard below the menu bar, say) dropped
/// straight over the menu bar. The bar manager (`Sidebar`) works out every
/// screen's bars and hands the menu bar's reach here after each rebuild;
/// panels ask for
/// - `usableFrame`: `visibleFrame` without the menu bar - for panels that
///   avoid Apple's menu bar and the Dock (Nexus panel, desktop clock, edit
///   mode);
/// - `barFreeFrame`: the whole screen without the menu bar - for panels that
///   grow out of a screen edge (Dashboard, Utilities, Launcher, session
///   menu, toasts), which then grow out of the bar's lower edge instead.
///
/// The sidebar is left out on purpose: those panels already reckon with it
/// on their own, and with the menu bar off every answer is exactly what it
/// was before the menu bar existed (the arithmetic, and that promise, are
/// tested in `MenuBarGeometryTests`).
@MainActor
enum ScreenRoom {
    /// How far the menu bar reaches down per display, only screens with one.
    private static var insets: [CGDirectDisplayID: CGFloat] = [:]
    private static var observers: [@MainActor () -> Void] = []

    /// From the bar manager after every rebuild. Tells the observers only
    /// when something moved.
    static func update(_ new: [CGDirectDisplayID: CGFloat]) {
        let kept = new.filter { $0.value > 0 }
        guard kept != insets else { return }
        insets = kept
        for observer in observers { observer() }
    }

    /// The menu bar switched on, off, thicker or thinner: for panels that stand
    /// all the time (desktop clock) and must move along. Lives as long as
    /// the process, like `ShellScreens.onChange`.
    static func onChange(_ handler: @escaping @MainActor () -> Void) {
        observers.append(handler)
    }

    /// How far the menu bar reaches down from the top of the full screen
    /// frame; zero without one.
    static func barInset(of screen: NSScreen) -> CGFloat {
        ShellScreens.displayID(of: screen).flatMap { insets[$0] } ?? 0
    }

    static func usableFrame(of screen: NSScreen) -> NSRect {
        MenuBarGeometry.usableFrame(visible: screen.visibleFrame, screen: screen.frame, barInset: barInset(of: screen))
    }

    static func barFreeFrame(of screen: NSScreen) -> NSRect {
        MenuBarGeometry.barFreeFrame(screen: screen.frame, barInset: barInset(of: screen))
    }
}

@MainActor
extension ShellScreen {
    /// `visibleFrame` without the menu bar (`ScreenRoom`).
    var usableFrame: NSRect { ScreenRoom.usableFrame(of: screen) }
    /// The whole frame without the menu bar (`ScreenRoom`).
    var barFreeFrame: NSRect { ScreenRoom.barFreeFrame(of: screen) }
}
