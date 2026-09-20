import AppKit
import ApolloShellCore
import SwiftUI

/// The desktop clock: lies behind all windows on the desktop, at the bottom
/// right (Caelestia's default position) with a 32 pt gap, above the Dock.
/// Clicks go straight through it.
///
/// On every screen that has a bar too (Nexus > Bar, “Screens”) - a clock on a
/// screen without a bar would be a single floating piece of shell.
///
///
/// Nexus > Desktop switches it on and off, right away: `Observations` reports
/// every change of the setting. Off means the window goes AND the timer stops
/// - an invisible clock should not work something out every minute. The time
/// itself is a shared model with one timer for all screens.
@MainActor
final class DesktopClock {
    /// Caelestia: Tokens.padding.extraLargeIncreased.
    private static let margin: CGFloat = 32

    private let model = DesktopClockModel()
    private let settings: ShellSettingsStore
    /// One window per screen, by display id.
    private var slots = ScreenSlots<DesktopClockWindow>()
    private var timer: Timer?
    private var enabled = false
    private var observation: Task<Void, Never>?
    private var choiceObservation: Task<Void, Never>?

    init(settings: ShellSettingsStore) {
        self.settings = settings
        setEnabled(settings.settings.background.desktopClock)
        observeSystemChanges()
        // Delivers the current value first, then every change. The loops live
        // as long as the app (AppDelegate holds the clock).
        observation = Task { [weak self, settings] in
            for await on in Observations({ settings.settings.background.desktopClock }) {
                self?.setEnabled(on)
            }
        }
        // The clock follows the screen setting of the bar.
        choiceObservation = Task { [weak self, settings] in
            for await _ in Observations({ settings.settings.bar.screens }) {
                self?.rebuild()
            }
        }
    }

    private func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            rebuild()
            scheduleTick()
        } else {
            timer?.invalidate()
            timer = nil
            slots.removeAll { $0.tearDown() }
        }
    }

    /// Create, measure and clear away the clocks the way the setting and the
    /// connected screens ask for. Without screens everything stays standing (a
    /// cable in the middle of being replugged).
    private func rebuild() {
        guard enabled else { return }
        let model = model
        slots.distribute(
            on: settings.settings.bar.screens,
            make: { _ in DesktopClockWindow(model: model) },
            update: { window, screen in
                window.layout(on: screen, margin: Self.margin, model: model)
                window.show()
            },
            remove: { $0.tearDown() }
        )
    }

    /// Only set the frames anew (the width changes with the text), without
    /// spreading the windows again.
    private func relayout() {
        guard enabled else { return }
        let all = ShellScreens.current()
        guard !all.isEmpty else { return }
        for screen in ShellScreens.targets(for: settings.settings.bar.screens, among: all) {
            slots.items[screen.displayID]?.layout(on: screen, margin: Self.margin, model: model)
        }
    }

    /// Move on to the next full minute, then every minute. One timer for all
    /// screens.
    private func scheduleTick() {
        model.now = Date()
        let seconds = Calendar.current.component(.second, from: model.now)
        let untilNextMinute = TimeInterval(60 - seconds) + 0.05
        timer?.invalidate()
        timer = .once(after: untilNextMinute, owner: self) { clock in
            clock.model.now = Date()
            clock.relayout() // Width can change (e.g. "Monday" -> "Wednesday")
            clock.timer = .repeating(every: 60, owner: clock) { clock in
                clock.model.now = Date()
                clock.relayout()
            }
        }
    }

    /// After a wake-up the minute is no longer right; after a screen change
    /// the spread and the position are not.
    private func observeSystemChanges() {
        ShellScreens.onChange { [weak self] in self?.rebuild() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Switched off: do not start a timer again.
                guard let self, self.enabled else { return }
                self.scheduleTick()
            }
        }
    }
}

/// The clock window of ONE screen.
@MainActor
private final class DesktopClockWindow {
    private let window: ShellPanel
    private let hosting: NSHostingView<ModifiedContent<DesktopClockView, ShellThemeRoot>>

    init(model: DesktopClockModel) {
        hosting = NSHostingView(rootView: DesktopClockView(model: model).shellTheme())
        hosting.sizingOptions = []
        // Just above the desktop icons, far below normal windows.
        window = ShellPanel(level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1),
                            behavior: [.canJoinAllSpaces, .stationary, .ignoresCycle], deferred: false)
        window.ignoresMouseEvents = true
        window.contentView = hosting
    }

    func layout(on screen: ShellScreen, margin: CGFloat, model: DesktopClockModel) {
        // Measure on a fresh view: `hosting` has sizingOptions = [] and
        // therefore reports no size of its own (fittingSize was 0 x 0 and the
        // clock invisible - measured 14.09.).
        let size = NSHostingView(rootView: DesktopClockView(model: model).shellTheme()).fittingSize
        let visible = screen.visibleFrame
        // The view brings a 24 pt shadow margin; the 32 pt hold for the text.
        let inset = margin - 24
        window.setFrame(NSRect(
            x: visible.maxX - size.width - inset,
            y: visible.minY + inset,
            width: size.width,
            height: size.height
        ), display: true)
    }

    func show() {
        guard !window.isVisible else { return }
        window.orderFrontRegardless()
    }

    func tearDown() {
        window.orderOut(nil)
    }
}
