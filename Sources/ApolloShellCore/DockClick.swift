import Foundation

/// The descriptive state of an app at the moment of the click - everything
/// the decision needs, without doing or reading anything itself.
public struct DockClickState: Equatable, Sendable {
    /// Whether a process of the app runs at all.
    public let running: Bool
    /// Just started, the process is not there yet (the icon bounces).
    public let launching: Bool
    /// Whether it is the frontmost app.
    public let frontmost: Bool
    /// Hidden (⌘H).
    public let hidden: Bool
    /// Visible (not minimised) windows on the space that can be seen right
    /// now.
    public let windowsOnActiveSpace: Int
    /// Visible (not minimised) windows on another space.
    public let windowsElsewhere: Int
    /// Minimised windows (put away in the Dock) - the space does not count
    /// here, they lie nowhere visible anyway.
    public let minimizedWindows: Int
    /// If it is at the front already and has a window here: does at least one
    /// of them lie under another app's window (`DockWindowCover`)? Only then
    /// does the click page through; several windows that are merely open side
    /// by side are left in peace.
    public let hasCoveredWindow: Bool
    /// ⌘ held down.
    public let command: Bool
    /// ⌥ held down.
    public let option: Bool

    public init(
        running: Bool, launching: Bool = false, frontmost: Bool, hidden: Bool,
        windowsOnActiveSpace: Int, windowsElsewhere: Int, minimizedWindows: Int, hasCoveredWindow: Bool = false,
        command: Bool, option: Bool
    ) {
        self.running = running
        self.launching = launching
        self.frontmost = frontmost
        self.hidden = hidden
        self.windowsOnActiveSpace = windowsOnActiveSpace
        self.windowsElsewhere = windowsElsewhere
        self.minimizedWindows = minimizedWindows
        self.hasCoveredWindow = hasCoveredWindow
        self.command = command
        self.option = option
    }
}

/// A single action a click in the Dock of the bar can set off. Several of
/// them together give the order `DockClick.actions` hands back.
public enum DockClickAction: Equatable, Sendable {
    /// Not there: start it.
    case launch
    /// If it was hidden, unhide it.
    case unhide
    /// To the front. Only when there is no window to raise at all -
    /// `activate()` fetches none (see `raiseWindowElsewhere`).
    case activate
    /// No window on the current space, but one on another: bring exactly that
    /// one forward, and macOS switches to its desktop with it. Measured
    /// 20.09.: `activate()` does make the app the frontmost one (the menu bar
    /// changes) but fetches no window and switches no space - not even as
    /// `activate(from:options: .activateAllWindows)`, which returns `true`
    /// and still moves nothing. Only the way through the window works.
    case raiseWindowElsewhere
    /// A window of the app lies on the current space already: bring that one
    /// to the front (which activates the app along with it) instead of
    /// switching to the space of another window.
    case raiseWindowOnActiveSpace
    /// At the front already, but one of its windows here lies under another
    /// app's: bring the frontmost covered one forward (`DockWindowCover`
    /// decides which - only that it happens stands here).
    case raiseCoveredWindow
    /// Bring the window put away last back out of the Dock.
    case unminimizeLast
    /// No window open: a new one (like Apple's "reopen").
    case newWindow
    /// ⌥ click: hide the app that was active before afterwards.
    case hidePrevious
    /// ⌘ click: show it in the file manager instead of switching.
    case reveal
}

/// What a click on a symbol in the Dock of the bar does - as in Apple's Dock:
/// when the app does not run, it is started; when it runs and is not at the
/// front, one of its windows comes forward (and the app with it); when one of
/// them lies on the current space already, the space stays (no jump to
/// another one), otherwise macOS switches to the window; when it is at the
/// front already and has a window here, nothing happens; when all windows are
/// put away, the one put away last comes back; when it has none at all, it
/// opens one ("reopen"). No more paging through windows on a click - only
/// scrolling still does that (`DockWindowCycle`).
public enum DockClick {
    /// A plain decision without a side effect: out of the state, an order of
    /// actions the app layer then carries out.
    public static func actions(for state: DockClickState) -> [DockClickAction] {
        // ⌘ only shows it in the file manager, as with Apple regardless of
        // everything else (not running or just starting included).
        if state.command { return [.reveal] }
        // While it is starting: do not double up, the next click takes hold
        // once it is there.
        if state.launching { return [] }

        var actions: [DockClickAction] = []
        if !state.running {
            actions.append(.launch)
        } else if state.frontmost, state.windowsOnActiveSpace > 0 {
            // At the front already and a window here: normally nothing (point
            // 3) - unless one of them is covered, then the click at least
            // brings that one to light instead of doing nothing.
            if state.hasCoveredWindow { actions.append(.raiseCoveredWindow) }
        } else {
            actions.append(contentsOf: raiseActions(state))
        }
        if state.option { actions.append(.hidePrevious) }
        return actions
    }

    /// Not at the front, or at the front without a window on the current space
    /// (switched to another space by hand while it stayed active, say):
    /// depending on where the windows lie, bring the one here forward, bring
    /// the one on another desktop forward (switching space with it), fetch a
    /// put-away one back or open a new one.
    private static func raiseActions(_ state: DockClickState) -> [DockClickAction] {
        var actions: [DockClickAction] = []
        // Only unhide when it really is hidden. Measured 16.09.: `unhide()`
        // on a visible app brings its last used window to the front - when
        // that lies on another desktop, macOS jumps there although one lies
        // here.
        if state.hidden { actions.append(.unhide) }
        if state.windowsOnActiveSpace > 0 {
            actions.append(.raiseWindowOnActiveSpace)
        } else if state.windowsElsewhere > 0 {
            actions.append(.raiseWindowElsewhere)
        } else if state.minimizedWindows > 0 {
            // Das Zurueckholen hebt das Fenster gleich mit und bringt die App
            // nach vorne - ein zusaetzliches `activate` wuerde nur dieselbe
            // Aufgabe schlechter erledigen (siehe `raiseWindowElsewhere`).
            actions.append(.unminimizeLast)
        } else {
            actions.append(.activate)
            actions.append(.newWindow)
        }
        return actions
    }
}
