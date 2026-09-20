import AppKit
import ApolloShellCore
import SwiftUI

/// The window for the stack of toasts, at the bottom right 12 from the edge
/// (Caelestia: Toasts in modules/drawers/Panels.qml, `anchors.margins:
/// padding.medium`). When the utilities panel is open, the stack sits 12
/// above it and glides with it (Caelestia hangs it on `utilities.top`).
///
/// Why a fixed, tall window instead of one that grows with the stack: that
/// way all the motion (fading in, moving up, getting out of the panel's way)
/// runs in SwiftUI on Caelestia's curves. Letting a window grow along would
/// mean moving the window frame and the content in the same frame - that
/// stutters, and toasts fading out would be cut off.
///
/// So that the window blocks nothing all the same, it lets mouse events
/// through (`ignoresMouseEvents`) and only takes them while the pointer lies
/// over a toast. A timer checks that at 30 Hz, and only while there are
/// toasts (a few seconds at most). Never focus: a panel that cannot become
/// the key window and does not activate the app.
@MainActor
final class ToastWindow {
    /// The margin around the stack inside the window: room for the overshoot
    /// of the fade-in curve (worked out: at most 1.4 % of the size, ~3 pt at 406).
    static let overscan: CGFloat = 8
    /// Stays for this long after the last toast, until the fade-out (500 ms)
    /// is done.
    private static let hideDelay: TimeInterval = 0.6
    private static let pollInterval: TimeInterval = 1.0 / 30

    private let toaster: Toaster
    private let panel = ToastPanel()
    private var pollTimer: Timer?
    private var hideTimer: Timer?
    private var utilitiesOpen = false
    /// Which screen the stack stands on. Fixed when the first toast opens - it
    /// does not wander with the pointer afterwards, otherwise it would jump
    /// away while being read.
    private var currentScreen: ShellScreen?

    /// The visible height of the utilities panel - the window has to be that
    /// much taller for the stack to fit above it. Follows the panel when cards
    /// or rows are added or removed in Nexus: while it is open the stack
    /// glides along (`lift`), and a visible window grows upwards - the stack
    /// sticks to the bottom, so it does not jump.
    var utilitiesHeight: CGFloat {
        didSet {
            guard utilitiesHeight != oldValue else { return }
            if utilitiesOpen { toaster.lift = utilitiesHeight }
            if panel.isVisible, let screen = currentScreen {
                panel.setFrame(frame(on: screen), display: true)
            }
        }
    }

    init(toaster: Toaster, utilitiesHeight: CGFloat) {
        self.toaster = toaster
        self.utilitiesHeight = utilitiesHeight
        let hosting = FirstMouseHostingView(
            rootView: ToastStackView(toaster: toaster, overscan: Self.overscan).shellTheme()
        )
        hosting.sizingOptions = []
        panel.contentView = hosting
        toaster.onChange = { [weak self] in self?.update() }
        observeScreenChanges()
    }

    /// Replugged or at a different resolution while toasts are open: measure
    /// again. When the screen of the stack is gone, it moves to the one under
    /// the pointer - otherwise it would stand on a frame that no longer
    /// exists. Lives as long as the process; the observer holds the window
    /// only weakly.
    private func observeScreenChanges() {
        ShellScreens.onChange { [weak self] in self?.screensChanged() }
    }

    private func screensChanged() {
        guard panel.isVisible, let current = currentScreen else { return }
        let all = ShellScreens.current()
        guard let next = all.first(where: { $0.displayID == current.displayID })
            ?? ShellScreens.underPointer(among: all) ?? all.first
        else { return }
        currentScreen = next
        panel.setFrame(frame(on: next), display: true)
    }

    /// The utilities panel opens or closes.
    func utilitiesChanged(open: Bool) {
        utilitiesOpen = open
        toaster.lift = open ? utilitiesHeight : 0
    }

    private func update() {
        if toaster.visible.isEmpty {
            // Only away once the last one has finished fading out.
            guard panel.isVisible, hideTimer == nil else { return }
            hideTimer = .once(after: Self.hideDelay, owner: self) { $0.hide() }
            return
        }
        hideTimer?.invalidate()
        hideTimer = nil
        // When the stack opens anew: where the pointer stands right now.
        if !panel.isVisible, let screen = ShellScreens.underPointer() {
            currentScreen = screen
            panel.setFrame(frame(on: screen), display: false)
            panel.ignoresMouseEvents = true
        }
        // Forward every time: if the utilities panel opened afterwards, it
        // would otherwise lie above it on the same level. Does not activate the app.
        panel.orderFrontRegardless()
        startPolling()
    }

    private func hide() {
        hideTimer = nil
        guard toaster.visible.isEmpty else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        // The next stack looks for its screen anew.
        currentScreen = nil
    }

    // MARK: - Geometry

    /// 12 from the right and the bottom edge of the screen (like the utilities
    /// panel, on the whole screen, not the visible area), tall enough for 4
    /// toasts above the open panel.
    private func frame(on screen: ShellScreen) -> NSRect {
        let s = screen.frame
        let margin = CGFloat(ToastLayout.margin)
        let width = CGFloat(ToastLayout.width)
        let stack = CGFloat(ToastLayout.stackHeight(count: ToastQueue.maxVisible))
        return NSRect(
            x: s.maxX - margin - width - Self.overscan,
            y: s.minY + margin - Self.overscan,
            width: width + 2 * Self.overscan,
            height: utilitiesHeight + stack + 2 * Self.overscan
        )
    }

    /// Where the visible toasts lie, in screen coordinates. The gaps between
    /// them (8 pt) count in - that is bearable.
    private var hitRect: NSRect {
        let count = toaster.visible.count
        guard count > 0 else { return .zero }
        let f = panel.frame
        return NSRect(
            x: f.minX + Self.overscan,
            y: f.minY + Self.overscan + toaster.lift,
            width: CGFloat(ToastLayout.width),
            height: CGFloat(ToastLayout.stackHeight(count: count))
        )
    }

    // MARK: - Mouse

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        poll()
    }

    /// Over a toast: take clicks. Otherwise let them through.
    private func poll() {
        let inside = hitRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
    }
}

/// A borderless panel for the toasts: the same level as the edge windows,
/// never the key window, no window shadow (which would give a second frame
/// around the glass). Without `.fullScreenAuxiliary`: it stays out of
/// full-screen spaces, like Caelestia's default "off".
final class ToastPanel: ShellPanel {
    /// May stick out a few points over the screen edge (the margin for the
    /// overshoot). Takes neither keyboard nor mouse.
    init() {
        super.init(level: .popUpMenu, behavior: [.canJoinAllSpaces, .transient, .ignoresCycle],
                   mayLeaveScreen: true)
        ignoresMouseEvents = true
    }
}
