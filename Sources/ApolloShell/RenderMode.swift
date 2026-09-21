import AppKit
import ApolloShellCore
import SwiftUI

/// Image samples without a running shell: `ApolloShell --render-dashboard <folder>`
/// draws the dashboard with fixed sample data as a PNG (2x, light and
/// dark) and ends. It touches neither windows, shortcuts nor files of the
/// shell and therefore also runs next to a running ApolloShell. For pixel
/// comparisons before and after rebuilds, see scripts/compare-renders.py.
@MainActor
enum RenderMode {
    /// Ends the process when a switch is set; otherwise it returns.
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--render-dashboard"), index + 1 < args.count {
            run(folder: URL(fileURLWithPath: args[index + 1], isDirectory: true), renderDashboard)
        }
        if let index = args.firstIndex(of: "--render-edit"), index + 1 < args.count {
            run(folder: URL(fileURLWithPath: args[index + 1], isDirectory: true), renderEditMode)
        }
        // `--render-mark <folder>`: the ApolloShell mark through one orbit of
        // its moon, large and at bar size.
        if let index = args.firstIndex(of: "--render-mark"), index + 1 < args.count {
            run(folder: URL(fileURLWithPath: args[index + 1], isDirectory: true), renderMark)
        }
        // `--render-toasts <folder> [<theme folder or .css>]`: the four kinds
        // of toast, light and dark, with that theme's colours (none: the
        // defaults) - for checking a theme's toasts without waiting for a
        // charger or a battery warning.
        if let index = args.firstIndex(of: "--render-toasts"), index + 1 < args.count {
            let theme = index + 2 < args.count && !args[index + 2].hasPrefix("-")
                ? ThemeLoader.load(at: URL(fileURLWithPath: args[index + 2])) : Theme.standard
            run(folder: URL(fileURLWithPath: args[index + 1], isDirectory: true)) { try renderToasts(into: $0, theme: theme) }
        }
    }

    private static func run(folder: URL, _ body: (URL) throws -> Void) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try body(folder)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func renderDashboard(into folder: URL) throws {
        let fixtures = RenderFixtures()
        let place = WeatherLocation(name: "Berlin", latitude: 52.52, longitude: 13.405)
        let places = WeatherFavorites(locations: [place], selectedID: place.id)
        // No battery: the image samples never really measure (`performance.battery`
        // stays `nil`), so the old dashboard showed no gauge either.
        let pages = DashboardPages(pages: DashboardPages.defaultPages(places: places, hasBattery: false))!
        let settings = ShellSettingsStore.preview(ShellSettings(dashboardPages: pages))
        let weatherModels = WeatherModels.preview(fixtures.weather)
        let editor = DashboardEditor(store: settings)
        for page in pages.pages {
            fixtures.dashboard.pageID = page.id
            for scheme in [ColorScheme.light, .dark] {
                fixtures.dashboard.scale = 1
                let view = DashboardView(model: fixtures.dashboard, weatherModels: weatherModels,
                                         media: fixtures.media, settings: settings, editor: editor)
                try write(view, scheme: scheme, to: folder.appendingPathComponent(name(page.template!.tab.rawValue, scheme)))
            }
        }
        // Scale 1.5, light only: for our own check whether the text stays
        // sharp (no comparison with the base sample - that one knows no
        // scale).
        let scaledFolder = folder.appendingPathComponent("scaled", isDirectory: true)
        try FileManager.default.createDirectory(at: scaledFolder, withIntermediateDirectories: true)
        for page in pages.pages {
            fixtures.dashboard.pageID = page.id
            fixtures.dashboard.scale = 1.5
            let view = DashboardView(model: fixtures.dashboard, weatherModels: weatherModels,
                                     media: fixtures.media, settings: settings, editor: editor)
            try write(view, scheme: .light, to: scaledFolder.appendingPathComponent(name(page.template!.tab.rawValue, .light)))
        }
        try renderEdit(into: folder, fixtures: fixtures, settings: settings, weatherModels: weatherModels, pages: pages)
    }

    /// The `edit/` subfolder of `--render-dashboard`: the overview page while
    /// editing, one selected widget, an invalid drop preview, and the same
    /// view with `accessibilityReduceMotion`.
    private static func renderEdit(into folder: URL, fixtures: RenderFixtures, settings: ShellSettingsStore,
                                    weatherModels: WeatherModels, pages: DashboardPages) throws {
        let editFolder = folder.appendingPathComponent("edit", isDirectory: true)
        try FileManager.default.createDirectory(at: editFolder, withIntermediateDirectories: true)
        let overview = pages.pages[0]
        let editor = DashboardEditor(store: settings)
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            editor.begin(pageID: overview.id, screen: screen)
        }
        fixtures.dashboard.pageID = overview.id

        func view(reduceMotion: Bool) -> some View {
            DashboardView(model: fixtures.dashboard, weatherModels: weatherModels, media: fixtures.media,
                          settings: settings, editor: editor)
                .environment(\.dashboardReducesMotionOverride, reduceMotion)
                // `ImageRenderer` does not draw the drop target (`.onDrop`)
                // offscreen (see `BentoDropTarget`) - out for the image sample.
                .environment(\.dashboardRendersForScreenshot, true)
        }
        try write(view(reduceMotion: false), scheme: .light, to: editFolder.appendingPathComponent("overview-light.png"))
        editor.selectedWidgetID = editor.page?.widgets.first?.id
        try write(view(reduceMotion: false), scheme: .light, to: editFolder.appendingPathComponent("selected-widget-light.png"))
        // An invalid drop preview (too close to a widget), as if a second
        // "clock" widget were being dragged over the first card right now.
        editor.dropPreview = editor.previewDrop(.clock, x: 60, y: 60).map { (frame: $0.frame, valid: $0.valid) }
        try write(view(reduceMotion: false), scheme: .light, to: editFolder.appendingPathComponent("invalid-drop-light.png"))
        editor.dropPreview = nil
        try write(view(reduceMotion: true), scheme: .light, to: editFolder.appendingPathComponent("reduce-motion-light.png"))
        // No image of the options popover itself: `.popover` is an AppKit
        // window of its own, and `ImageRenderer` does not draw its content
        // offscreen (a `Form` with `WidgetOptionsView` straight in it stayed
        // empty in the sample, probably for the same reason as `.onDrag`/
        // `.onDrop`). The selection itself (the blue frame) is what
        // `selected-widget-light.png` shows; the sliders in `WidgetOptionsView`
        // (`NexusWidgetOptions.swift`) are the same ones as before 0.2 in the
        // Nexus editor, and were checked in the image there already.
    }

    /// `--render-edit <folder>`: the toolbar and both gallery tabs of the
    /// global edit mode (task 3), in `<folder>/edit/`. Plain SwiftUI views
    /// (no `NSGlassEffectView` panel needed), so `ImageRenderer` can draw
    /// them offscreen.
    private static func renderEditMode(into folder: URL) throws {
        let editFolder = folder.appendingPathComponent("edit", isDirectory: true)
        try FileManager.default.createDirectory(at: editFolder, withIntermediateDirectories: true)
        let place = WeatherLocation(name: "Berlin", latitude: 52.52, longitude: 13.405)
        let places = WeatherFavorites(locations: [place], selectedID: place.id)
        let pages = DashboardPages(pages: DashboardPages.defaultPages(places: places, hasBattery: false))!
        let settings = ShellSettingsStore.preview(ShellSettings(dashboardPages: pages))
        let dashboardEditor = DashboardEditor(store: settings)
        let editor = ShellEditor(store: settings, dashboard: dashboardEditor)
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            editor.begin(screen: screen)
        }
        try write(EditToolbarView(editor: editor), scheme: .light, to: editFolder.appendingPathComponent("toolbar-light.png"))
        // Esc with changes (task 6): the toolbar asks back instead of
        // cancelling right away.
        editor.dashboard.addPage()
        editor.pendingCancelConfirmation = true
        try write(EditToolbarView(editor: editor), scheme: .light, to: editFolder.appendingPathComponent("toolbar-confirm-light.png"))
        editor.pendingCancelConfirmation = false
        editor.galleryTab = .dashboard
        try write(EditGalleryView(editor: editor).environment(\.galleryRendersForScreenshot, true), scheme: .light,
                 to: editFolder.appendingPathComponent("gallery-dashboard-light.png"))
        editor.galleryTab = .controlCentre
        try write(EditGalleryView(editor: editor).environment(\.galleryRendersForScreenshot, true), scheme: .light,
                 to: editFolder.appendingPathComponent("gallery-controlcentre-light.png"))
        editor.galleryTab = .bar
        try write(EditGalleryView(editor: editor).environment(\.galleryRendersForScreenshot, true), scheme: .light,
                 to: editFolder.appendingPathComponent("gallery-bar-light.png"))
        // The sidebar while editing (task 3 of the bar plan): a block
        // selected, the minus badges visible. The wobble itself is not in
        // the sample - `ImageRenderer` draws one fixed moment.
        editor.selectedBarEntryID = editor.bar?.layout.entries.first { $0.kind == .clock }?.id
        let barView = EditableBarContent(editor: editor, layout: editor.bar?.layout ?? BarLayout(),
                                         context: BarPreviewModels.context, spacing: 8)
            .environment(\.barPreview, true)
            .environment(\.dashboardRendersForScreenshot, true)
            .padding(.vertical, 10)
            .frame(width: Sidebar.width, height: 520)
        try write(barView, scheme: .light, to: editFolder.appendingPathComponent("bar-editing-light.png"))
        // The control centre while editing (task 5): one button selected -
        // `ImageRenderer` does not draw the wobble itself (a fixed snapshot
        // in the middle of the endless loop), but the frame, the minus badge
        // and the target highlight are visible without motion. The volume
        // slider and the device buttons of the sound card (`UtilitiesAudioCard`)
        // are backed by AppKit themselves (their own drag area, `NSMenu`) -
        // the same cause as with `.onDrag`/`.onDrop`: offscreen,
        // `ImageRenderer` draws them as a red no-entry sign instead of their
        // real shape. In the real window (not offscreen) they look normal,
        // only without effect (`allowsHitTesting(false)`).
        if let toggleID = editor.utilities?.layout.toggles.first?.id {
            editor.selectedToggleID = toggleID
        }
        let utilitiesView = EditableUtilitiesView(editor: editor, layout: editor.utilities?.layout ?? UtilitiesLayout())
            .environment(\.dashboardRendersForScreenshot, true)
        try write(utilitiesView, scheme: .light, to: editFolder.appendingPathComponent("utilities-selected-light.png"))
    }

    private static func renderMark(into folder: URL) throws {
        let steps = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
        let large = HStack(spacing: 8) {
            ForEach(steps, id: \.self) { step in
                ApolloMark(orbit: step).frame(width: 160, height: 160)
            }
        }
        .padding(12)
        try write(large, scheme: .light, to: folder.appendingPathComponent("mark-orbit-light.png"))
        let small = HStack(spacing: 12) {
            ForEach([16.0, 18, 20, 22, 24], id: \.self) { side in
                ApolloMark().frame(width: side, height: side)
            }
        }
        .padding(8)
        try write(small, scheme: .dark, to: folder.appendingPathComponent("mark-sizes-dark.png"))
    }

    private static func renderToasts(into folder: URL, theme: Theme) throws {
        let deadline = Date.distantFuture
        let entries = [
            ToastEntry(id: 1, title: "Charger Connected", message: "Battery is charging", symbol: "bolt.fill",
                       kind: .info, deadline: deadline),
            ToastEntry(id: 2, title: "Colour Copied", message: "#3A302A", symbol: "checkmark", kind: .success,
                       deadline: deadline),
            ToastEntry(id: 3, title: "Battery Low", message: "20 % left", symbol: "battery.25percent",
                       kind: .warning, deadline: deadline),
            ToastEntry(id: 4, title: "Keep Awake Failed", message: "No administrator rights", symbol: "xmark",
                       kind: .error, deadline: deadline),
        ]
        for scheme in [ColorScheme.light, .dark] {
            let style = ShellStyle(theme: theme, dark: scheme == .dark)
            let view = VStack(spacing: 8) {
                ForEach(entries) { entry in
                    ToastCard(entry: entry).frame(width: 406)
                }
            }
            .padding(24)
            .environment(\.shellStyle, style)
            .environment(\.colorScheme, scheme)
            // A mid grey behind them: whatever the theme does, the edge of
            // each toast stays visible.
            .background(Color(white: 0.45))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { throw RenderError.noImage("toasts") }
            try data.write(to: folder.appendingPathComponent(name("toasts", scheme)))
        }
    }

    static func name(_ base: String, _ scheme: ColorScheme) -> String {
        "\(base)-\(scheme == .dark ? "dark" : "light").png"
    }

    /// Without a theme store (`shellTheme(nil)`): always the defaults, no
    /// matter which theme the user picked. An opaque background, because
    /// glass is not drawn offscreen.
    static func write(_ view: some View, scheme: ColorScheme, to url: URL) throws {
        let content = view
            .shellTheme(nil)
            .environment(\.colorScheme, scheme)
            .background(scheme == .dark ? Color.black : Color.white)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw RenderError.noImage(url.lastPathComponent) }
        try data.write(to: url)
    }

    enum RenderError: Error { case noImage(String) }
}

/// Fixed sample data for image samples: a fixed point in time, fixed values,
/// nothing measures and nothing calls out to the network.
@MainActor
final class RenderFixtures {
    /// Friday, 18.09.2026, 14:05 in the time zone of the machine.
    let now: Date = {
        var components = DateComponents(year: 2026, month: 9, day: 18, hour: 14, minute: 5)
        components.calendar = Calendar(identifier: .gregorian)
        return components.date!
    }()

    lazy var dashboard = DashboardModel.preview(now: now, cpu: 0.23, memory: 0.58, storage: 0.46,
                                                userName: "Alex Example", uptime: 11_520)

    lazy var weather: WeatherModel = {
        let calendar = Calendar(identifier: .gregorian)
        let hours = (0..<24).map { offset in
            HourForecast(time: calendar.date(byAdding: .hour, value: offset, to: now)!,
                         temperature: 18 - Double(offset % 8), code: [0, 1, 2, 3, 61][offset % 5],
                         precipitationProbability: (offset * 7) % 60, isDay: (6..<20).contains((14 + offset) % 24))
        }
        let days = (0..<7).map { offset in
            DayForecast(date: calendar.date(byAdding: .day, value: offset, to: now)!, code: [2, 0, 3, 61, 1, 2, 0][offset],
                        maxTemperature: 21 - Double(offset), minTemperature: 11 - Double(offset % 3),
                        sunrise: nil, sunset: nil, precipitationProbability: (offset * 13) % 80)
        }
        let report = WeatherReport(
            current: CurrentWeather(time: now, temperature: 18, apparentTemperature: 17, humidity: 60,
                                    code: 2, windSpeed: 8, isDay: true),
            hours: hours, days: days, timeZone: .current
        )
        return WeatherModel.preview(report: report, fetchedAt: now, now: now)
    }()

    lazy var media: MediaModel = {
        let playing = MediaNowPlaying(title: "Sample Track", artist: "Sample Band", album: "Sample Album",
                                      isPlaying: false, duration: 240, elapsed: 80, timestamp: now, playbackRate: 0)
        return MediaModel.preview(nowPlaying: playing, source: MediaSource(name: "Music", icon: nil), now: now)
    }()
}
