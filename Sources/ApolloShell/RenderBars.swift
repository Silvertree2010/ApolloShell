import AppKit
import ApolloShellCore
import SwiftUI

/// `ApolloShell --render-bars <folder>`: the bars as PNG with fixed sample
/// data, light and dark - the sidebar with every template, so a rebuild of
/// the bar kit can be checked pixel for pixel (scripts/compare-renders.py),
/// and the menu bar in every template and style.
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
        try renderVertical(into: folder.appendingPathComponent("vertical", isDirectory: true), context: context)
        try renderMenuBar(into: folder.appendingPathComponent("menubar", isDirectory: true), context: context)
        try renderThemes(into: folder.appendingPathComponent("themes", isDirectory: true), context: context)
    }

    /// The example themes of docs/THEMES.md ("Teal Strip", "Ember Islands"),
    /// read straight out of the docs so the picture shows the text a reader
    /// copies, on the Serpantinum menu bar as strip and as islands - with the
    /// status as pills (all three, the battery module dropped for it) and
    /// Spaces as pills; one more with the bars face and the badge clock.
    private static func renderThemes(into folder: URL, context: BarModuleContext) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let docs = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/THEMES.md")
        let markdown = String(decoding: try Data(contentsOf: docs), as: UTF8.self)
        for (name, slug) in [("Teal Strip", "teal-strip"), ("Ember Islands", "ember-islands")] {
            guard let css = ThemeDocumentation.cssBlock(after: "### \(name)", in: markdown) else {
                throw RenderMode.RenderError.noImage("\(name) is missing from docs/THEMES.md")
            }
            let theme = Theme.make(identifier: slug, styleSheet: ThemeStyleSheetParser.parse(css))
            let faces: [(name: String, spaces: BarWorkspacesOptions.Style, clock: BarClockOptions.Style?)] = [
                ("pills", .pills, nil), ("bars-badge", .bars, .badge),
            ]
            for scheme in [ColorScheme.light, .dark] {
                for look in looks where look.name != "fill-distinct" {
                    for face in faces {
                        var bar = MenuBarPreset.serpantinum.bar()
                        bar.style = look.style
                        bar.statusStyle = .pills
                        for zone in BarZone.allCases {
                            bar[zone] = BarLayout(bar[zone].entries.compactMap { entry in
                                var entry = entry
                                switch entry.module {
                                case .battery: return nil
                                case .statusIcons: entry.module = .statusIcons(.init())
                                case .workspaces: entry.module = .workspaces(.init(style: face.spaces))
                                case let .clock(options):
                                    entry.module = .clock(.init(showIcon: options.showIcon, showDate: options.showDate,
                                                                style: face.clock))
                                default: break
                                }
                                return entry
                            })
                        }
                        let height = CGFloat(bar.thickness) + (look.style == .islands ? MenuBarGeometry.islandMargin : 0)
                        let view = menuBar(bar, notch: nil, context: context)
                            .environment(\.shellStyle, ShellStyle(theme: theme, dark: scheme == .dark))
                            .frame(width: 1728, height: height)
                        try RenderMode.write(view, scheme: scheme, to: folder.appendingPathComponent(
                            RenderMode.name("\(slug)-\(look.name)-\(face.name)", scheme)))
                    }
                }
            }
        }
    }

    /// The three looks every menu bar template is drawn in.
    private static let looks: [(name: String, style: BarStyle, distinct: Bool)] = [
        ("fill", .fill, false), ("fill-distinct", .fill, true), ("islands", .islands, false),
    ]

    /// The menu bar as its panel would show it: every template x look across
    /// a MacBook screen (1728 wide), with and without the camera housing
    /// measured there (left area to 771, right from 956). The housing is
    /// painted in black, so a block running under it shows up.
    /// Behind the bar a mid-tone "wallpaper", so the strip and the islands
    /// stand out from it; glass is replaced by its fixed stand-in.
    private static func renderMenuBar(into folder: URL, context: BarModuleContext) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let notch = BarNotch(leftEnd: 771, rightStart: 956)
        for scheme in [ColorScheme.light, .dark] {
            for preset in MenuBarPreset.allCases {
                for look in looks {
                    var bar = preset.bar()
                    bar.style = look.style
                    bar.distinctGroups = look.distinct
                    let height = CGFloat(bar.thickness) + (look.style == .islands ? MenuBarGeometry.islandMargin : 0)
                    for withNotch in [false, true] {
                        let view = menuBar(bar, notch: withNotch ? notch : nil, context: context)
                            .frame(width: 1728, height: height)
                            .overlay(alignment: .topLeading) {
                                if withNotch {
                                    UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                                        .fill(Color.black)
                                        .frame(width: notch.rightStart - notch.leftEnd, height: 32)
                                        .offset(x: notch.leftEnd)
                                }
                            }
                        let name = "top-\(preset.rawValue)-\(look.name)\(withNotch ? "-notch" : "")"
                        try RenderMode.write(view, scheme: scheme, to: folder.appendingPathComponent(RenderMode.name(name, scheme)))
                    }
                }
            }
            // Thin and thick: the buttons shrink to fit a 26 pt bar and stop
            // at 32 in a 44 pt one.
            for thickness in [26.0, 44.0] {
                for look in looks {
                    var bar = MenuBarPreset.serpantinum.bar()
                    bar.style = look.style
                    bar.distinctGroups = look.distinct
                    bar.thickness = thickness
                    let height = CGFloat(thickness) + (look.style == .islands ? MenuBarGeometry.islandMargin : 0)
                    let view = menuBar(bar, notch: nil, context: context).frame(width: 1728, height: height)
                    try RenderMode.write(view, scheme: scheme, to: folder.appendingPathComponent(
                        RenderMode.name("top-serpantinum-\(Int(thickness))-\(look.name)", scheme)))
                }
            }
            // The Dock in a zone takes the room the others leave: alone in
            // the centre it stays centred; with a spacer on the left, start
            // and centre share.
            let dockBars: [(name: String, bar: ApolloMenuBar)] = [
                ("dock-center", ApolloMenuBar(enabled: true,
                                              start: BarLayout([BarEntry(.dashboardButton), BarEntry(.workspaces)]),
                                              center: BarLayout([BarEntry(.dock)]),
                                              end: BarLayout([BarEntry(.statusIcons), BarEntry(.clock), BarEntry(.power)]))),
                ("dock-start", ApolloMenuBar(enabled: true,
                                             start: BarLayout([BarEntry(.dashboardButton), BarEntry(.dock)]),
                                             center: BarLayout([BarEntry(.clock)]),
                                             end: BarLayout([BarEntry(.statusIcons), BarEntry(.power)]))),
            ]
            for (name, template) in dockBars {
                for look in looks {
                    var bar = template
                    bar.style = look.style
                    bar.distinctGroups = look.distinct
                    let height = CGFloat(bar.thickness) + (look.style == .islands ? MenuBarGeometry.islandMargin : 0)
                    let view = menuBar(bar, notch: nil, context: context).frame(width: 1728, height: height)
                    try RenderMode.write(view, scheme: scheme, to: folder.appendingPathComponent(
                        RenderMode.name("top-\(name)-\(look.name)", scheme)))
                }
            }
            // The status popout of the menu bar: the sidebar's content on a
            // plain card (the glass stand-in here).
            let popout = StatusPopoutModel.preview(
                shown: .wifi,
                wifi: StatusPopoutWifiInfo(powerOn: true, interfaceName: "en0", rssi: -55, noise: -92,
                                           transmitRate: 866, phyMode: 6, channel: 44, band: 2),
                bluetooth: nil,
                battery: nil
            )
            let card = MenuBarPopoutView(model: popout) { _ in }
                .padding(12)
                .background(Color(red: 0.45, green: 0.52, blue: 0.62))
                .environment(\.statusPopoutGlassStandIn, true)
                .fixedSize()
            try RenderMode.write(card, scheme: scheme, to: folder.appendingPathComponent(
                RenderMode.name("popout-wifi", scheme)))
        }
    }

    private static func menuBar(_ bar: ApolloMenuBar, notch: BarNotch?, context: BarModuleContext) -> some View {
        MenuBarView(bar: bar, notch: notch, features: ShellSettings.Features(), context: context)
            .background(Color(red: 0.45, green: 0.52, blue: 0.62))
            .environment(\.barPreview, true)
            .environment(\.statusPopoutGlassStandIn, true)
    }

    /// The same blocks along a horizontal axis, for the menu bar: every
    /// template as one 34 pt high row, and every kind
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

    /// The stage-3 blocks (spec "Etappe 3") across a vertical bar, each
    /// alone in a sidebar-wide column - kept out of `sidebar/`, whose files
    /// are the pixel baseline - and once more along a horizontal row with
    /// their options switched on, in icons and as pills on the menu bar.
    private static let stageThree: [BarEntry] = [
        BarEntry(module: .nowPlaying(.init())),
        BarEntry(module: .windowTitle(.init())),
        BarEntry(module: .keyboardLayout(.init(showIcon: true))),
        BarEntry(module: .volume(.init(showDevice: true))),
        BarEntry(.wifi), BarEntry(.bluetooth),
        BarEntry(module: .systemStats(.init())),
    ]

    private static func renderVertical(into folder: URL, context: BarModuleContext) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            for entry in stageThree {
                let view = BarModuleView(entry: entry, context: context)
                    .environment(\.barPreview, true)
                    .frame(width: Sidebar.width, height: 110)
                try RenderMode.write(view, scheme: scheme,
                                     to: folder.appendingPathComponent(RenderMode.name(entry.kind.rawValue, scheme)))
            }
            try RenderMode.write(row(stageThree, context: context).frame(width: 1400, height: 34), scheme: scheme,
                                 to: folder.appendingPathComponent(RenderMode.name("stage3-row", scheme)))
            for (name, pills) in [("stage3-top-icons", false), ("stage3-top-pills", true)] {
                let bar = ApolloMenuBar(enabled: true, statusStyle: pills ? .pills : .icons,
                                        start: BarLayout([BarEntry(.dashboardButton), stageThree[0], stageThree[1]]),
                                        center: BarLayout([BarEntry(.clock)]),
                                        end: BarLayout(Array(stageThree[2...]) + [BarEntry(.power)]))
                let view = menuBar(bar, notch: nil, context: context)
                    .frame(width: 1728, height: CGFloat(bar.thickness))
                try RenderMode.write(view, scheme: scheme, to: folder.appendingPathComponent(RenderMode.name(name, scheme)))
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
            cpu: BarCPUModel(preview: 0.23, memory: 0.61),
            weather: BarWeatherFeed(preview: weather),
            media: MediaModel.preview(
                nowPlaying: MediaNowPlaying(title: "Sample Track With a Long Name", artist: "Sample Band",
                                            isPlaying: true, duration: 240, elapsed: 80, timestamp: now, playbackRate: 1),
                now: now),
            frontApp: BarFrontAppModel(preview: frontApp(), title: "Apple – Start Page"),
            keyboard: BarKeyboardModel(preview: "DE", name: "Swiss German"),
            volume: BarVolumeModel(preview: 0.45, muted: false, deviceName: "MacBook Pro Speakers")
        )
    }

    /// Safari as the frontmost app, with its real icon where it is installed.
    private static func frontApp() -> BarFrontAppModel.FrontApp {
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        return BarFrontAppModel.FrontApp(pid: 1, name: "Safari", icon: icon)
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
