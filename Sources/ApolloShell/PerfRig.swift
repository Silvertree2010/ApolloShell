#if DEBUG || PERF_RIG
import AppKit
import ApolloShellCore
import SwiftUI

/// A measuring rig for what the shell costs while it draws.
///
/// `ApolloShell --perf-edit <seconds> [dashboard-page] [no-edit] [no-gallery] [utilities]`
/// builds a shell on settings that live only in memory, opens what the
/// arguments ask for, holds it and quits. Alongside it,
/// `sudo powermetrics --samplers gpu_power` reads what it costs.
///
/// It exists because the cost of the edit mode could otherwise only be
/// guessed: measured on 20.09. at 60 % GPU residency and 1.3 W against
/// 0.5 % and 2 mW with nothing open. In release builds it is compiled in
/// only with `-DPERF_RIG`, so that a measurement of the shipped build is
/// possible without shipping the rig.
@MainActor
enum PerfRig {
    private static var harness: PerfRigHarness?

    static func runIfAsked() -> Bool {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--perf-edit"), index + 1 < args.count,
              let seconds = Double(args[index + 1]) else { return false }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let harness = PerfRigHarness()
        self.harness = harness
        DispatchQueue.main.async { harness.hold(seconds: seconds, arguments: args) }
        app.run()
        return true
    }
}

@MainActor
private final class PerfRigHarness {
    private let store: ShellSettingsStore
    private let dashboardEditor: DashboardEditor
    private let editor: ShellEditor
    private let dashboard: Dashboard
    private let utilities: UtilitiesPanel
    private let windows: EditModeWindows
    private let sidebar: Sidebar

    init() {
        var settings = ShellSettings()
        settings.dashboardPages = DashboardPages(pages: DashboardPages.defaultPages(
            places: .empty, hasBattery: PerformanceSampler.hasInternalBattery))
        store = .preview(settings)
        dashboardEditor = DashboardEditor(store: store)
        editor = ShellEditor(store: store, dashboard: dashboardEditor)
        dashboard = Dashboard(settings: store, editor: dashboardEditor)
        utilities = UtilitiesPanel(settings: store, editor: editor)
        windows = EditModeWindows(editor: editor)
        sidebar = Sidebar(settings: store, editor: editor)
        editor.addBeginHandler { [weak sidebar] _ in sidebar?.setEditing(true) }
        editor.addEndHandler { [weak sidebar] in sidebar?.setEditing(false) }
        editor.dashboardStartPageID = { [weak dashboard] in dashboard?.currentPageID }
        windows.utilitiesFrame = { [weak utilities] in utilities?.openFrame }
        windows.dashboardFrame = { [weak dashboard] in dashboard?.openFrame }
    }

    func hold(seconds: Double, arguments: [String]) {
        Task { @MainActor in
            guard let screen = NSScreen.screens.first else { exit(1) }
            dashboard.show(tab: arguments.contains("dashboard-page") ? .dashboard : .performance)
            if arguments.contains("utilities") { utilities.toggle() }
            try? await Task.sleep(for: .seconds(0.8))
            if !arguments.contains("no-edit") {
                editor.begin(screen: screen)
                editor.galleryVisible = !arguments.contains("no-gallery")
            }
            try? await Task.sleep(for: .seconds(seconds))
            if editor.isEditing { editor.cancel() }
            try? await Task.sleep(for: .seconds(0.5))
            exit(0)
        }
    }
}
#endif
