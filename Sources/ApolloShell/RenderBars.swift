import AppKit
import ApolloShellCore
import SwiftUI

/// `ApolloShell --render-bars <folder>`: the bars as PNG with fixed sample
/// data, light and dark - the sidebar with every template, so a rebuild of
/// the bar kit can be checked pixel for pixel (scripts/compare-renders.py).
/// Nothing measures, nothing calls out; the Dock shows bundled Apple apps.
@MainActor
enum RenderBars {
    static func render(into folder: URL) throws {
        let fixtures = RenderFixtures()
        let context = Self.context(now: fixtures.now, weather: fixtures.weather)
        let sidebar = folder.appendingPathComponent("sidebar", isDirectory: true)
        try FileManager.default.createDirectory(at: sidebar, withIntermediateDirectories: true)
        for preset in BarPreset.allCases {
            let settings = ShellSettingsStore.preview(ShellSettings(bar: .init(layout: preset.layout)))
            for scheme in [ColorScheme.light, .dark] {
                let view = SidebarContent(settings: settings, context: context)
                    .environment(\.barPreview, true)
                    .frame(width: Sidebar.width, height: 720)
                try RenderMode.write(view, scheme: scheme,
                                     to: sidebar.appendingPathComponent("\(preset.rawValue)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        try renderHorizontal(into: folder.appendingPathComponent("horizontal", isDirectory: true), context: context)
    }

    /// The same blocks along a horizontal axis, for the bars along the top and
    /// the bottom edge: every template as one 34 pt high row, and every kind
    /// alone - so a block that breaks out of the height shows up on its own.
    private static func renderHorizontal(into folder: URL, context: BarModuleContext) throws {
        let modules = folder.appendingPathComponent("modules", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            for preset in BarPreset.allCases {
                try RenderMode.write(row(preset.layout.entries, context: context).frame(width: 1400, height: 34),
                                     scheme: scheme, to: folder.appendingPathComponent(RenderMode.name(preset.rawValue, scheme)))
            }
            for kind in BarModuleKind.allCases {
                try RenderMode.write(row([BarEntry(kind)], context: context).frame(width: 300, height: 34),
                                     scheme: scheme, to: modules.appendingPathComponent(RenderMode.name(kind.rawValue, scheme)))
            }
        }
    }

    private static func row(_ entries: [BarEntry], context: BarModuleContext) -> some View {
        BarStack(axis: .horizontal) {
            ForEach(entries) { entry in
                BarModuleView(entry: entry, context: context)
            }
        }
        // The sidebar's margin at its ends, here at the left and the right.
        .padding(.horizontal, 10)
        .environment(\.barAxis, .horizontal)
        .environment(\.barPreview, true)
    }

    /// Like `BarPreviewModels.context`, but at the fixtures' point in time
    /// and with a fixed battery, so two runs give the same pixels.
    static func context(now: Date, weather: WeatherModel) -> BarModuleContext {
        BarModuleContext(
            status: StatusModel(previewWifiRSSI: -55, battery: BatteryState(level: 76, charging: false, onAC: false),
                                bluetoothOn: true),
            spaces: SpacesModel(preview: SpaceSnapshot(desktops: [1, 2, 3, 4], activeIndex: 1)),
            dock: SidebarDockModel(preview: dockEntries(), frontmost: "com.apple.Safari"),
            clock: SidebarClockModel(preview: now),
            cpu: BarCPUModel(preview: 0.23),
            weather: BarWeatherFeed(preview: weather)
        )
    }

    private static func dockEntries() -> [SidebarDockModel.Entry] {
        let ids = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Notes", "com.apple.iCal",
                   "com.apple.systempreferences"]
        let running: Set<String> = ["com.apple.finder", "com.apple.Safari"]
        return ids.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return SidebarDockModel.Entry(bundleID: id, name: FileManager.default.displayName(atPath: url.path),
                                          icon: NSWorkspace.shared.icon(forFile: url.path), pinned: true,
                                          running: running.contains(id))
        }
    }
}
