import AppKit
import ApolloShellCore
import SwiftUI

/// `ApolloShell --render-bars <folder>`: the bars as PNG with fixed sample
/// data, light and dark - the sidebar with every template, so a rebuild of
/// the bar kit can be checked pixel for pixel (scripts/compare-renders.py),
/// and the bars along the other edges in every template and style.
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
        try renderEdge(into: folder.appendingPathComponent("edge", isDirectory: true), context: context)
        try renderThemes(into: folder.appendingPathComponent("themes", isDirectory: true), context: context)
    }

    /// The example themes of docs/THEMES.md ("Teal Strip", "Ember Islands"),
    /// read straight out of the docs so the picture shows the text a reader
    /// copies, on the Serpantinum top bar as strip and as islands - with the
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
                for look in edgeLooks where look.name != "fill-distinct" {
                    for face in faces {
                        var bar = EdgeBarPreset.serpantinum.bar(edge: .top)
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
                        let height = CGFloat(bar.thickness) + (look.style == .islands ? EdgeBarGeometry.islandMargin : 0)
                        let view = edgeBar(bar, edge: .top, notch: nil, context: context)
                            .environment(\.shellStyle, ShellStyle(theme: theme, dark: scheme == .dark))
                            .frame(width: 1728, height: height)
                        try RenderMode.write(view, scheme: scheme, to: folder.appendingPathComponent(
                            RenderMode.name("\(slug)-\(look.name)-\(face.name)", scheme)))
                    }
                }
            }
        }
    }

    /// The three looks every edge bar template is drawn in.
    private static let edgeLooks: [(name: String, style: BarStyle, distinct: Bool)] = [
        ("fill", .fill, false), ("fill-distinct", .fill, true), ("islands", .islands, false),
    ]

    /// Edge bars as their panels would show them: every template x look as a
    /// top bar across a MacBook screen (1728 wide), with and without the
    /// camera housing measured there (left area to 771, right from 956),
    /// and the Serpantinum template as a 44 pt bar at the right edge. The
    /// housing is painted in black, so a block running under it shows up.
    /// Behind the bar a mid-tone "wallpaper", so the strip and the islands
    /// stand out from it; glass is replaced by its fixed stand-in.
    private static func renderEdge(into folder: URL, context: BarModuleContext) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let notch = BarNotch(leftEnd: 771, rightStart: 956)
        for scheme in [ColorScheme.light, .dark] {
            for preset in EdgeBarPreset.allCases {
                for look in edgeLooks {
                    var bar = preset.bar(edge: .top)
                    bar.style = look.style
                    bar.distinctGroups = look.distinct
                    let height = CGFloat(bar.thickness) + (look.style == .islands ? EdgeBarGeometry.islandMargin : 0)
                    for withNotch in [false, true] {
                        let view = edgeBar(bar, edge: .top, notch: withNotch ? notch : nil, context: context)
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
                for look in edgeLooks {
                    var bar = EdgeBarPreset.serpantinum.bar(edge: .top)
                    bar.style = look.style
                    bar.distinctGroups = look.distinct
                    bar.thickness = thickness
                    let height = CGFloat(thickness) + (look.style == .islands ? EdgeBarGeometry.islandMargin : 0)
                    let view = edgeBar(bar, edge: .top, notch: nil, context: context).frame(width: 1728, height: height)
                    try RenderMode.write(view, scheme: scheme, to: folder.appendingPathComponent(
                        RenderMode.name("top-serpantinum-\(Int(thickness))-\(look.name)", scheme)))
                }
            }
            // The Dock in a zone takes the room the others leave: alone in
            // the centre it stays centred; with a spacer on the left, start
            // and centre share.
            let dockBars: [(name: String, bar: EdgeBar)] = [
                ("dock-center", EdgeBar(enabled: true,
                                        start: BarLayout([BarEntry(.dashboardButton), BarEntry(.workspaces)]),
                                        center: BarLayout([BarEntry(.dock)]),
                                        end: BarLayout([BarEntry(.statusIcons), BarEntry(.clock), BarEntry(.power)]))),
                ("dock-start", EdgeBar(enabled: true,
                                       start: BarLayout([BarEntry(.dashboardButton), BarEntry(.dock)]),
                                       center: BarLayout([BarEntry(.clock)]),
                                       end: BarLayout([BarEntry(.statusIcons), BarEntry(.power)]))),
            ]
            for (name, template) in dockBars {
                for look in edgeLooks {
                    var bar = template
                    bar.style = look.style
                    bar.distinctGroups = look.distinct
                    let height = CGFloat(bar.thickness) + (look.style == .islands ? EdgeBarGeometry.islandMargin : 0)
                    let view = edgeBar(bar, edge: .bottom, notch: nil, context: context).frame(width: 1728, height: height)
                    try RenderMode.write(view, scheme: scheme, to: folder.appendingPathComponent(
                        RenderMode.name("bottom-\(name)-\(look.name)", scheme)))
                }
            }
            // The status popout of an edge bar: the sidebar's content on a
            // plain card (the glass stand-in here).
            let popout = StatusPopoutModel.preview(
                shown: .wifi,
                wifi: StatusPopoutWifiInfo(powerOn: true, interfaceName: "en0", rssi: -55, noise: -92,
                                           transmitRate: 866, phyMode: 6, channel: 44, band: 2),
                bluetooth: nil,
                battery: nil
            )
            let card = EdgeBarPopoutView(model: popout) { _ in }
                .padding(12)
                .background(Color(red: 0.45, green: 0.52, blue: 0.62))
                .environment(\.statusPopoutGlassStandIn, true)
                .fixedSize()
            try RenderMode.write(card, scheme: scheme, to: folder.appendingPathComponent(
                RenderMode.name("popout-wifi", scheme)))
            for look in edgeLooks {
                var bar = EdgeBarPreset.serpantinum.bar(edge: .right)
                bar.style = look.style
                bar.distinctGroups = look.distinct
                bar.thickness = 44
                let width = 44 + (look.style == .islands ? EdgeBarGeometry.islandMargin : 0)
                let view = edgeBar(bar, edge: .right, notch: nil, context: context).frame(width: width, height: 900)
                try RenderMode.write(view, scheme: scheme, to: folder.appendingPathComponent(
                    RenderMode.name("right-serpantinum-\(look.name)", scheme)))
            }
        }
    }

    private static func edgeBar(_ bar: EdgeBar, edge: BarEdge, notch: BarNotch?,
                                context: BarModuleContext) -> some View {
        EdgeBarView(bar: bar, edge: edge, notch: notch, features: ShellSettings.Features(), context: context)
            .background(Color(red: 0.45, green: 0.52, blue: 0.62))
            .environment(\.barPreview, true)
            .environment(\.statusPopoutGlassStandIn, true)
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
