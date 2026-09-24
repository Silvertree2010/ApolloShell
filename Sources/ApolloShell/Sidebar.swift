import AppKit
import ApolloShellCore
import os
import SwiftUI

/// Manager of the bars: one sidebar per screen, and the bars along the top,
/// the bottom and the right edge (`ShellSettings.edgeBars`) where they are
/// switched on. One manager for all of them because they share the models
/// and have to agree on the room: a top or bottom bar shortens the sidebar's
/// column, and the window guard keeps free what all of them cover together
/// (`EdgeBarGeometry`).
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
    /// After every rebuild: the room the bars keep free per screen, by
    /// `ScreenInfo.key`. The window guard keeps windows out of it.
    var onReservedChange: ([String: ReservedInsets]) -> Void = { _ in }

    /// Shared models - once for all bars.
    /// CPU and weather only measure or fetch as long as at least one bar
    /// is visible.
    private let cpu = BarCPUModel()
    private let network = BarNetworkModel()
    private let weather: BarWeatherFeed
    /// Wi-Fi, Bluetooth, battery for the status capsule.
    private let status = StatusModel()
    /// Spaces, Dock, and clock for the middle of the bar.
    private let spaces = SpacesModel()
    private let dock: SidebarDockModel
    private let clock = SidebarClockModel()
    /// The stage-3 blocks: shared like the rest, each one only listening
    /// while a block that shows it stands in a visible bar.
    private let media: MediaModel
    private let frontApp = BarFrontAppModel()
    private let keyboard = BarKeyboardModel()
    private let volume = BarVolumeModel()

    /// One bar per screen, by display identifier.
    private var slots = ScreenSlots<SidebarScreen>()
    private var bars: [CGDirectDisplayID: SidebarScreen] { slots.items }
    /// The bars along the other edges, per edge by display identifier.
    private var edgeSlots: [BarEdge: ScreenSlots<EdgeBarScreen>] = [:]
    private var edgeScreens: [EdgeBarScreen] { edgeSlots.values.flatMap { $0.items.values } }
    /// The edge bars as they were laid out last, to skip the rebuild when a
    /// settings change touched something else.
    private var laidOutEdgeBars: EdgeBars?
    /// The room kept free from the last rebuild.
    private(set) var reserved: [String: ReservedInsets] = [:]
    /// Screens on which a full-screen app currently stands.
    private var fullscreenScreens: Set<CGDirectDisplayID> = []
    private var context: BarModuleContext!
    private var choiceObservation: Task<Void, Never>?
    private var edgeBarsObservation: Task<Void, Never>?
    private var widthObservation: Task<Void, Never>?
    private var appearanceObservation: NSKeyValueObservation?
    /// Width from the last time the windows were measured.
    private var laidOutWidth: CGFloat = 0

    /// `settings`: which building blocks in which order and on which
    /// screens (Nexus > Bar). SwiftUI observes it and rebuilds the bars
    /// right away on every change.
    /// The global edit mode, so the bars can show their edit surface.
    /// `nil` in previews and image samples: then they only ever draw the
    /// calm bar. Handed over in `init`, not set afterwards: the bars are
    /// built right there, and each one hands its editor to the view it
    /// hosts once - a bar built without one never shows an edit surface,
    /// however late the editor arrives (20.09.: that was why the blocks
    /// stayed calm while the rest of the shell was being edited).
    private(set) weak var editor: ShellEditor?

    /// `media`: the shell's one Now Playing model, shared with the dashboard.
    init(settings: ShellSettingsStore, editor: ShellEditor? = nil, media: MediaModel = MediaModel()) {
        self.settings = settings
        self.editor = editor
        self.media = media
        // The file manager above comes from the settings (Nexus > Providers).
        dock = SidebarDockModel(settings: settings)
        // Weather provider likewise from the settings, as in the Dashboard.
        weather = BarWeatherFeed(settings: settings)
        context = BarModuleContext(
            status: status, spaces: spaces, dock: dock, clock: clock, cpu: cpu, weather: weather,
            media: media, frontApp: frontApp, keyboard: keyboard, volume: volume, network: network,
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
        // Edge bars on or off, thicker, another style or other screens: the
        // frames, the sidebar's column and the room kept free all follow.
        // What only changes the blocks inside a bar redraws by itself (the
        // view reads the settings), so equal values are skipped.
        edgeBarsObservation = Task { [weak self, settings] in
            for await edgeBars in Observations({ settings.settings.edgeBars }) {
                if let self, edgeBars != self.laidOutEdgeBars { self.rebuild() }
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

    /// The global edit mode began or ended: every bar follows (level, see
    /// `SidebarScreen.setEditing`). Remembered, so a bar built while the
    /// mode runs (a screen reconnected) starts at the right level.
    private var isEditing = false

    #if DEBUG
    /// For the invisible self-test: the levels of the bars that stand now.
    var debugLevels: [Int] { bars.values.map(\.debugLevel) }
    var debugWindows: [NSWindow] { bars.values.map(\.debugWindow) }
    /// For the invisible self-test: every bar that stands knows the editor.
    var debugBarsKnowEditor: Bool { !bars.isEmpty && bars.values.allSatisfy(\.debugHasEditor) }
    #endif

    func setEditing(_ editing: Bool) {
        isEditing = editing
        for bar in bars.values { bar.setEditing(editing) }
        for bar in edgeScreens { bar.setEditing(editing) }
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
        for slots in edgeSlots.values {
            for (id, bar) in slots.items { bar.setHiddenForFullscreen(ids.contains(id)) }
        }
        updateModelDemand()
    }

    /// Nobody needs CPU values or weather while invisible: the shared
    /// models rest as soon as no bar is visible anymore.
    private func updateModelDemand() {
        let anyVisible = bars.values.contains { !$0.isHiddenForFullscreen }
            || edgeScreens.contains { !$0.isHiddenForFullscreen }
        cpu.paused = !anyVisible
        network.paused = !anyVisible
        weather.paused = !anyVisible
        media.barsPaused = !anyVisible
        frontApp.paused = !anyVisible
        keyboard.paused = !anyVisible
        volume.paused = !anyVisible
        dock.badgesPaused = !anyVisible
    }

    // MARK: - Distributing Bars

    /// Create, measure, and tear down bars again, as the settings and the
    /// connected screens currently require.
    ///
    /// First the geometry of every screen (which bars stand there decides
    /// the sidebar's column and the room kept free), then the sidebars, then
    /// the edge bars. With no edge bar on, every screen's geometry is the
    /// sidebar from the screen's bottom edge up to the menu bar - exactly the
    /// frame it had before edge bars existed.
    ///
    /// Without screens (a cable mid-reconnect, `NSScreen.screens` empty),
    /// everything stays put instead of tearing everything down and
    /// building it right back up. When screens come back,
    /// didChangeScreenParametersNotification fires and it continues here.
    private func rebuild() {
        let settings = settings
        let context = context!
        let all = ShellScreens.current()
        guard !all.isEmpty else {
            log.notice("no screen, the bars stay put")
            return
        }
        let edgeBars = settings.settings.edgeBars
        laidOutEdgeBars = edgeBars
        let layouts = Self.layouts(for: all, sidebar: settings.settings.bar.screens, edgeBars: edgeBars)
        let fallback = { (screen: ShellScreen) in
            EdgeBarGeometry.layout(screen: screen.frame, visibleTop: screen.visibleFrame.maxY,
                                   sidebarWidth: Sidebar.width, bars: [:])
        }

        let placed = slots.distribute(
            on: settings.settings.bar.screens,
            make: { screen in
                let bar = SidebarScreen(screen: screen, column: layouts[screen.displayID] ?? fallback(screen),
                                        settings: settings, context: context, editor: editor)
                bar.setEditing(isEditing)
                bar.onPopoutOpen = { [weak self] id in self?.closePopouts(except: id) }
                return bar
            },
            update: { bar, screen in
                bar.update(screen: screen, column: layouts[screen.displayID] ?? fallback(screen))
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

        let active = Set(edgeBars.active)
        for edge in BarEdge.allCases {
            var edgeSlot = edgeSlots[edge] ?? ScreenSlots()
            if active.contains(edge) {
                let bar = edgeBars[edge]
                edgeSlot.distribute(
                    on: bar.screens,
                    make: { screen in
                        let bar = EdgeBarScreen(edge: edge, screen: screen, settings: settings, context: context,
                                                editor: editor)
                        bar.setEditing(isEditing)
                        bar.onPopoutOpen = { [weak self] id in self?.closePopouts(except: id) }
                        return bar
                    },
                    update: { item, screen in
                        guard let frame = layouts[screen.displayID]?.frames[edge] else { return }
                        item.update(screen: screen, frame: frame, coversMenuBar: bar.coversMenuBar)
                        item.setHiddenForFullscreen(fullscreenScreens.contains(screen.displayID))
                    },
                    remove: { $0.tearDown() }
                )
            } else {
                edgeSlot.removeAll { $0.tearDown() }
            }
            edgeSlots[edge] = edgeSlot
        }

        updateModelDemand()
        laidOutWidth = Sidebar.width
        reserved = Self.reserved(layouts, screens: all)
        // Panels placed against a screen edge keep clear of the edge bars.
        ScreenRoom.update(layouts.mapValues(\.barInsets))
        log.notice("sidebar on \(placed.count, privacy: .public) screen(s), edge bars: \(edgeBars.active.map(\.rawValue).joined(separator: ","), privacy: .public)")
        onReservedChange(reserved)
    }

    /// The geometry of every connected screen: which bars stand on it
    /// (each bar by its own screen choice) and where.
    private static func layouts(for all: [ShellScreen], sidebar: ScreenChoice,
                                edgeBars: EdgeBars) -> [CGDirectDisplayID: EdgeBarGeometry.Result] {
        let sidebarIDs = Set(ShellScreens.targets(for: sidebar, among: all).map(\.displayID))
        var edgeIDs: [BarEdge: Set<CGDirectDisplayID>] = [:]
        for edge in edgeBars.active {
            edgeIDs[edge] = Set(ShellScreens.targets(for: edgeBars[edge].screens, among: all).map(\.displayID))
        }
        var result: [CGDirectDisplayID: EdgeBarGeometry.Result] = [:]
        for screen in all {
            var bars: [BarEdge: EdgeBarGeometry.Bar] = [:]
            for (edge, ids) in edgeIDs where ids.contains(screen.displayID) {
                bars[edge] = EdgeBarGeometry.Bar(edgeBars[edge])
            }
            result[screen.displayID] = EdgeBarGeometry.layout(
                screen: screen.frame, visibleTop: screen.visibleFrame.maxY,
                sidebarWidth: sidebarIDs.contains(screen.displayID) ? Sidebar.width : nil, bars: bars
            )
        }
        return result
    }

    /// The room kept free per screen key. Screens where nothing is reserved
    /// are left out, so the window guard leaves their windows alone.
    private static func reserved(_ layouts: [CGDirectDisplayID: EdgeBarGeometry.Result],
                                 screens: [ShellScreen]) -> [String: ReservedInsets] {
        var result: [String: ReservedInsets] = [:]
        for screen in screens {
            guard let insets = layouts[screen.displayID]?.reserved, !insets.isZero else { continue }
            result[screen.info.key] = (result[screen.info.key] ?? .zero).union(insets)
        }
        return result
    }

    /// Only ever one status popout is open: when one opens, it closes
    /// that of another bar - sidebar or edge bar.
    private func closePopouts(except id: ObjectIdentifier) {
        for bar in bars.values where ObjectIdentifier(bar) != id {
            bar.closePopout()
        }
        for bar in edgeScreens where ObjectIdentifier(bar) != id {
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
            for bar in self.edgeScreens { bar.closePopout() }
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
