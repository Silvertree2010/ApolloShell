import AppKit
import ApolloShellCore
import os
import SwiftUI

/// Manager of the bars: one bar per screen.
///
/// Which screens get one is decided by Nexus > Bar (All, main display
/// only, a single one); the computation for that lives in
/// ApolloShellCore/ScreenSelection and is tested there.
///
/// The models (Dock, clock, Spaces, CPU, weather, status) are built ONCE
/// here and passed on to all bars. They read system-wide values - a
/// separate one per screen would be the same measurement multiple times
/// and thus multiple loads. Only what belongs to the window is per bar:
/// the panel and its status popout.
///
/// Keeping space free like the Dock does is the job of the window guard
/// (WindowGuard.swift): macOS has no interface for that, it pushes
/// windows out of the strip via accessibility; without permission,
/// maximized windows run straight through underneath. If a screen shows
/// a full-screen app (`FullscreenMonitor`), that screen's bar steps aside.
@MainActor
final class Sidebar {
    /// Width of the bar. With themes, `--apollo-bar-width` decides.
    ///
    /// The width is not only in the view but also in the window and in
    /// the strip the window guard keeps free - hence a single place for
    /// it here. If it changes (different theme, light/dark),
    /// `widthChanged()` immediately follows through in the window and
    /// the window guard.
    static var width: CGFloat {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return ThemeStore.shared?.style(dark: dark).barWidth(44) ?? 44
    }

    private let settings: ShellSettingsStore
    private let log = Logger(category: "sidebar")

    /// Click on the power symbol at the bottom (opens the session menu).
    var onPower: () -> Void = {}
    /// Click on the Dashboard symbol at the top.
    var onDashboard: () -> Void = {}
    /// Click on the Utilities symbol above the status capsule.
    var onUtilities: () -> Void = {}
    /// Click on media, weather, CPU, or battery: Dashboard on the
    /// matching tab.
    var onDashboardTab: (DashboardTab) -> Void = { _ in }
    /// After every rebuild: a bar now stands on these screens. The
    /// window guard keeps the strip free there.
    var onScreensChange: ([ScreenInfo]) -> Void = { _ in }

    /// Shared models - once for all bars.
    /// CPU and weather only measure or fetch as long as at least one bar
    /// is visible.
    private let cpu = BarCPUModel()
    private let weather: BarWeatherFeed
    /// Wi-Fi, Bluetooth, battery for the status capsule.
    private let status = StatusModel()
    /// Spaces, Dock, and clock for the middle of the bar.
    private let spaces = SpacesModel()
    private let dock: SidebarDockModel
    private let clock = SidebarClockModel()

    /// One bar per screen, by display identifier.
    private var slots = ScreenSlots<SidebarScreen>()
    private var bars: [CGDirectDisplayID: SidebarScreen] { slots.items }
    /// Screens on which a full-screen app currently stands.
    private var fullscreenScreens: Set<CGDirectDisplayID> = []
    private var context: BarModuleContext!
    private var choiceObservation: Task<Void, Never>?
    private var widthObservation: Task<Void, Never>?
    private var appearanceObservation: NSKeyValueObservation?
    /// Width from the last time the windows were measured.
    private var laidOutWidth: CGFloat = 0

    /// `settings`: which building blocks in which order and on which
    /// screens (Nexus > Bar). SwiftUI observes it and rebuilds the bars
    /// right away on every change.
    init(settings: ShellSettingsStore) {
        self.settings = settings
        // The file manager above comes from the settings (Nexus > Providers).
        dock = SidebarDockModel(settings: settings)
        // Weather provider likewise from the settings, as in the Dashboard.
        weather = BarWeatherFeed(settings: settings)
        context = BarModuleContext(
            status: status, spaces: spaces, dock: dock, clock: clock, cpu: cpu, weather: weather,
            onDashboard: { [weak self] in self?.onDashboard() },
            onDashboardTab: { [weak self] in self?.onDashboardTab($0) },
            onUtilities: { [weak self] in self?.onUtilities() },
            onPower: { [weak self] in self?.onPower() },
            onSelectSpace: { [spaces] in spaces.switchTo($0) },
            onOpenApp: { BarApps.open($0) }
        )

        rebuild()
        observeSystemChanges()
        // Delivers the current value first (nothing to do), then every
        // change of the screen setting from Nexus.
        choiceObservation = Task { [weak self, settings] in
            for await _ in Observations({ settings.settings.bar.screens }) {
                self?.rebuild()
            }
        }
        // The width depends on the theme (observable) and on light/dark
        // (not observable, hence via KVO).
        widthObservation = Task { [weak self] in
            for await _ in Observations({ Sidebar.width }) {
                self?.widthChanged()
            }
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.widthChanged() }
        }
    }

    /// New bar width: re-measure the windows and let the window guard
    /// adjust the strip. An open popout closes - its stage depends on the
    /// old width.
    private func widthChanged() {
        guard Sidebar.width != laidOutWidth else { return }
        for bar in bars.values { bar.closePopout() }
        rebuild()
    }

    /// Which screens a bar currently stands on.
    var screens: [ScreenInfo] {
        bars.values.map(\.info)
    }

    /// From `FullscreenMonitor`: a full-screen app is showing on these
    /// screens. Only their bar steps aside, the others stay put. By
    /// display identifier, not by key: two identical screens have the
    /// same key.
    func setFullscreenScreens(_ ids: Set<CGDirectDisplayID>) {
        guard ids != fullscreenScreens else { return }
        fullscreenScreens = ids
        for (id, bar) in bars {
            bar.setHiddenForFullscreen(ids.contains(id))
        }
        updateModelDemand()
    }

    /// Nobody needs CPU values or weather while invisible: the shared
    /// models rest as soon as no bar is visible anymore.
    private func updateModelDemand() {
        let anyVisible = bars.values.contains { !$0.isHiddenForFullscreen }
        cpu.paused = !anyVisible
        weather.paused = !anyVisible
        dock.badgesPaused = !anyVisible
    }

    // MARK: - Distributing Bars

    /// Create, measure, and tear down bars again, as the setting and the
    /// connected screens currently require.
    ///
    /// Without screens (a cable mid-reconnect, `NSScreen.screens` empty),
    /// everything stays put instead of tearing everything down and
    /// building it right back up. When screens come back,
    /// didChangeScreenParametersNotification fires and it continues here.
    private func rebuild() {
        let settings = settings
        let context = context!
        let placed = slots.distribute(
            on: settings.settings.bar.screens,
            make: { screen in
                let bar = SidebarScreen(screen: screen, settings: settings, context: context)
                bar.onPopoutOpen = { [weak self] id in self?.closePopouts(except: id) }
                return bar
            },
            update: { bar, screen in
                bar.update(screen: screen)
                bar.setHiddenForFullscreen(fullscreenScreens.contains(screen.displayID))
            },
            // Screen gone or deselected. This also closes a popout that
            // was still open there.
            remove: { $0.tearDown() }
        )
        guard let placed else {
            log.notice("no screen, the bars stay put")
            return
        }

        updateModelDemand()
        laidOutWidth = Sidebar.width
        log.notice("bars on \(placed.count, privacy: .public) screen(s)")
        onScreensChange(placed.map(\.info))
    }

    /// Only ever one status popout is open: when one opens, it closes
    /// that of another bar.
    private func closePopouts(except id: ObjectIdentifier) {
        for bar in bars.values where ObjectIdentifier(bar) != id {
            bar.closePopout()
        }
    }

    /// Resolution or screens changed, wake-up (whole machine or just the
    /// screens), space switch: redistribute, re-measure, and, if a bar
    /// should be visible but is gone, bring it back to the front.
    ///
    /// Screens going to sleep needs no dedicated observer: as long as
    /// they are dark, there is nothing to do, and waking up is covered
    /// by `screensDidWakeNotification`.
    ///
    /// The observers are never removed: the manager lives as long as the
    /// process (AppDelegate holds it), and the closures only hold it
    /// weakly.
    private func observeSystemChanges() {
        ShellScreens.onChange { [weak self] in
            guard let self else { return }
            // New resolution or arrangement: position and height of an
            // open popout are no longer correct.
            for bar in self.bars.values { bar.closePopout() }
            self.rebuild()
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild() }
            }
        }
    }
}
