import AppKit
import ApolloShellCore
import SwiftUI

// MARK: - Page

/// Nexus > Bar (Caelestia: Panels > Taskbar): the bar as a building-block
/// kit. On the left the blocks from top to bottom - drag to reorder, an
/// options disclosure, "Add" with a gallery, presets -, on the right the
/// real bar (`SidebarContent`) with preview models, scaled down. Every
/// change applies to the bar right away and lands in settings.json.
struct NexusBarPage: View {
    @Bindable var store: ShellSettingsStore
    /// Locations for the bar's weather block (weather.json) - here since
    /// the global edit mode instead of on its own Dashboard page; they are
    /// also the default for new weather widgets.
    var weather: NexusWeatherModel?

    init(store: ShellSettingsStore, weather: NexusWeatherModel? = nil) {
        _store = Bindable(store)
        self.weather = weather
    }

    var body: some View {
        HStack(spacing: 0) {
            NexusPageForm(page: .bar) {
                arrangeHint
                NexusBarScreensSection(store: store)
                NexusBarBackgroundSection(store: store)
                if let weather {
                    NexusDashboardWeatherSection(model: weather)
                    NexusSaveWarning(failed: weather.saveFailed, file: "weather.json")
                }
                NexusSaveWarning(failed: store.saveFailed)
            }
            Divider()
            NexusBarPreview(store: store)
                .frame(width: 124)
        }
    }

    /// The blocks themselves are arranged in the bar (edit mode); this page
    /// keeps what is a setting rather than an arrangement.
    private var arrangeHint: some View {
        Section {
            Text("The blocks of the bar are arranged in the bar itself: “Edit Interface” below, then drag, remove with −, or add from the gallery behind +.")
                .foregroundStyle(.secondary)
        } header: {
            Text("Building Blocks")
        }
    }
}

// MARK: - Screens

/// Nexus > Bar > Screens: which screens the bar stands on.
///
/// A single screen is remembered via a stable key (name plus resolution,
/// see `ScreenInfo.key`) - macOS reassigns a display identifier on every
/// connect, so it would be a different screen the next time. If the
/// remembered one is not connected, the bar stands on the main display; it
/// still stays in the list, otherwise the selection would point at nothing
/// and would be gone the next time it gets connected.
private struct NexusBarScreensSection: View {
    @Bindable var store: ShellSettingsStore
    /// Connected screens, read when the page appears.
    @State private var screens: [ScreenInfo] = []

    var body: some View {
        Section {
            Picker("Screens", selection: $store.settings.bar.screens) {
                Text("All").tag(ScreenChoice.all)
                Text("Main Display Only").tag(ScreenChoice.primary)
                if !screens.isEmpty {
                    Divider()
                    ForEach(screens) { screen in
                        Text(screen.name).tag(ScreenChoice.single(screen.key))
                    }
                }
                if let missing {
                    Divider()
                    Text("\(missing) (not connected)").tag(ScreenChoice.single(missing))
                }
            }
        } header: {
            Text("Screens")
        } footer: {
            Text("Which screens the bar stands on – and with it the desktop clock and the strip the window guard keeps clear. A single screen is remembered by name and resolution; when it is not connected, the bar stands on the main display.")
        }
        .task { reload() }
    }

    /// Merge identical keys: two identical screens cannot be told apart for
    /// this setting (the first one then applies), and two rows with the
    /// same identifier would confuse the list.
    private func reload() {
        var seen: Set<String> = []
        screens = ShellScreens.current().map(\.info).filter { seen.insert($0.key).inserted }
    }

    /// The remembered screen, if it is currently not connected.
    private var missing: String? {
        guard case .single(let key) = store.settings.bar.screens,
              !screens.contains(where: { $0.key == key })
        else { return nil }
        return key
    }
}

// MARK: - Background

/// Nexus > Bar > Background: what the bar and its notch are backed with.
///
/// Offered as a choice because Liquid Glass follows whatever lies behind it
/// and cannot be talked out of that - the reasons and the evidence are in
/// `BarBackground`. The entries differ visibly so they can be compared on a
/// live desktop; the default stays Material.
private struct NexusBarBackgroundSection: View {
    @Bindable var store: ShellSettingsStore

    var body: some View {
        Section {
            ForEach(BarBackground.allCases) { background in
                NexusChoiceRow(selected: store.settings.bar.background == background) {
                    store.settings.bar.background = background
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        title(background)
                        subtitle(background)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Background")
        } footer: {
            Text("Liquid Glass follows the brightness of whatever is behind it, and it also flips between a light and a dark appearance – so the bar changes color as soon as a window moves underneath it. That cannot be switched off; for a fixed color, pick Material or glass on a solid fill.")
        }
    }

    private func title(_ background: BarBackground) -> Text {
        switch background {
        case .material: Text("Material")
        case .glass: Text("Liquid Glass")
        case .tintedGlass: Text("Liquid Glass, Tinted")
        case .fixedGlass: Text("Liquid Glass on a Solid Fill")
        }
    }

    private func subtitle(_ background: BarBackground) -> Text {
        switch background {
        case .material: Text("System material with a fixed color that follows light and dark – how it looks today")
        case .glass: Text("Real glass; it takes on the color and brightness of whatever is behind it")
        case .tintedGlass: Text("Glass tinted with the window color; it shifts less, but it still shifts")
        case .fixedGlass: Text("Clear glass over an opaque fill in the window color: the sheen stays, the color holds still")
        }
    }
}

// MARK: - Preview

/// The real bar with preview models, as tall as the bar on the main
/// display and scaled down to the page's height. Without mouse input
/// (`barPreview`): a click here should not trigger anything.
struct NexusBarPreview: View {
    let store: ShellSettingsStore
    var context = NexusBarPreviewModels.context
    var barHeight = NexusBarPreviewModels.barHeight

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, max(geometry.size.height - 62, 80) / barHeight)
            VStack(spacing: 8) {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                NexusScaledPreview(scale: scale, frameSize: CGSize(width: Sidebar.width * scale, height: barHeight * scale),
                                   cornerRadius: 9 / scale, accessibilityLabel: String(localized: "Preview of the Bar")) {
                    SidebarContent(settings: store, context: context)
                        .environment(\.barPreview, true)
                        .frame(width: Sidebar.width, height: barHeight)
                }
                Text("Sample Data")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 14)
        }
    }
}

/// Fixed models for the preview: they measure, call, and launch nothing.
/// The apps in the Dock are bundled Apple apps (only the ones present),
/// the battery is the real one (read once), so a Mac without a battery
/// does not show one in the preview either.
@MainActor
enum NexusBarPreviewModels {
    /// Main display down to below the menu bar, like `Sidebar.layout`.
    static var barHeight: CGFloat {
        guard let screen = NSScreen.screens.first else { return 900 }
        return max(screen.visibleFrame.maxY - screen.frame.minY, 400)
    }

    static let context: BarModuleContext = {
        let now = Date()
        let report = WeatherReport(
            current: CurrentWeather(time: now, temperature: 18, apparentTemperature: nil, humidity: nil,
                                    code: 2, windSpeed: nil, isDay: true),
            hours: [], days: [], timeZone: .current
        )
        return BarModuleContext(
            status: StatusModel(previewWifiRSSI: -55, battery: StatusModel.readBattery(), bluetoothOn: true),
            spaces: SpacesModel(preview: SpaceSnapshot(desktops: [1, 2, 3], activeIndex: 0)),
            dock: SidebarDockModel(preview: dockEntries(), frontmost: "com.apple.Safari"),
            clock: SidebarClockModel(preview: now),
            cpu: BarCPUModel(preview: 0.18),
            weather: BarWeatherFeed(preview: WeatherModel.preview(report: report, fetchedAt: now, now: now))
        )
    }()

    private static func dockEntries() -> [SidebarDockModel.Entry] {
        let ids = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Notes", "com.apple.iCal",
                   "com.apple.Music", "com.apple.systempreferences"]
        let running: Set<String> = ["com.apple.finder", "com.apple.Safari"]
        return ids.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return SidebarDockModel.Entry(bundleID: id, name: FileManager.default.displayName(atPath: url.path),
                                          icon: NSWorkspace.shared.icon(forFile: url.path), pinned: true,
                                          running: running.contains(id))
        }
    }
}
