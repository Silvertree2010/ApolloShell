import AppKit
import ApolloShellCore
import Observation
import os
import SwiftUI

// What the building blocks of the bar need (models, actions) and the blocks
// that came with the kit: app, battery, CPU, weather. The seven of the
// earlier bar still stand in SidebarContent.swift, SidebarModules.swift and
// SidebarDock.swift; which kind is drawn how is decided by
// `BarModuleView`.

/// A classic environment key instead of `@Entry`: the macro needs the SwiftUI
/// macro plugin, and the Command Line Tools do not ship it.
private struct BarPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// In the preview of Nexus: no mouse views (hover, Dock clicks,
    /// dragging). The preview is scaled down, and AppKit views do not go
    /// along with that - their areas would lie next to the symbols and react
    /// over the form. And a click should start no real app there.
    var barPreview: Bool {
        get { self[BarPreviewKey.self] }
        set { self[BarPreviewKey.self] = newValue }
    }
}

/// Models and actions for all building blocks. The bar hands over the real
/// ones, the preview in Nexus fixed preview models without actions.
@MainActor
struct BarModuleContext {
    var status: StatusModel
    var spaces: SpacesModel
    var dock: SidebarDockModel
    var clock: SidebarClockModel
    var cpu: BarCPUModel
    var weather: BarWeatherFeed
    var onDashboard: @MainActor () -> Void = {}
    /// Media, weather, CPU, battery: straight to the matching tab.
    var onDashboardTab: @MainActor (DashboardTab) -> Void = { _ in }
    var onUtilities: @MainActor () -> Void = {}
    var onPower: @MainActor () -> Void = {}
    var onSelectSpace: @MainActor (Int) -> Void = { _ in }
    var onOpenApp: @MainActor (String) -> Void = { _ in }
}

// MARK: - Demand

/// How many visible building blocks need a model right now. Measuring or
/// fetching only happens while at least one of them stands in the bar AND the
/// bar can be seen (`paused` = stepped aside in full screen). Without a CPU
/// or weather block the models cost nothing.
struct BarDemand {
    private(set) var users = 0
    var paused = false

    var isActive: Bool { users > 0 && !paused }

    mutating func acquire() { users += 1 }

    /// Never below 0: should an onDisappear arrive without an onAppear, the
    /// next block should measure again all the same.
    mutating func release() { users = max(users - 1, 0) }
}

/// CPU load for the CPU block. Every 2 s (the rings of the dashboard measure
/// every second, but only while it is open - the bar is always there, so half
/// as often) and only on demand, see `BarDemand`. One measurement is two Mach
/// calls, microseconds.
@MainActor
@Observable
final class BarCPUModel {
    /// 0...1, rounded to whole percent: that way the bar only redraws when
    /// the shown number changes. `nil` until the second measurement.
    private(set) var usage: Double?

    static let interval: TimeInterval = 2

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var demand = BarDemand()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: CPUTicks?

    init() {
        live = true
    }

    /// For the preview and the image sample: a fixed value, never measures.
    init(preview usage: Double?) {
        live = false
        self.usage = usage
    }

    var isSampling: Bool { timer != nil }

    var paused: Bool {
        get { demand.paused }
        set { demand.paused = newValue; sync() }
    }

    func acquire() { demand.acquire(); sync() }
    func release() { demand.release(); sync() }

    private func sync() {
        guard live else { return }
        if demand.isActive, timer == nil {
            lastTicks = SystemSampler.cpuTicks()
            let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            // May come a little later: macOS then puts timers together.
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !demand.isActive, let timer {
            timer.invalidate()
            self.timer = nil
            // Start over after the pause: averaging across it would be wrong.
            lastTicks = nil
        }
    }

    private func sample() {
        guard let ticks = SystemSampler.cpuTicks() else { return }
        defer { lastTicks = ticks }
        guard let old = lastTicks, let value = ResourceMath.cpuUsage(from: old, to: ticks) else { return }
        let rounded = (value * 100).rounded() / 100
        if rounded != usage { usage = rounded }
    }
}

/// Weather for the weather block: a `WeatherModel` of its own that only
/// fetches while the block can be seen (when it appears, when the data is
/// older than 15 min, then every 30 min - the rules of the model).
///
/// Its own instead of the dashboard's: that one starts and stops its model on
/// opening and closing; a shared one would stop the bar when the dashboard
/// closes. The price: with both visible, at most one extra fetch every half
/// hour.
@MainActor
final class BarWeatherFeed {
    let model: WeatherModel
    private let live: Bool
    private var demand = BarDemand()
    private var running = false

    /// `settings`: which weather provider (Nexus > Providers), as in the dashboard.
    init(settings: ShellSettingsStore) {
        model = WeatherModel(settings: settings)
        live = true
    }

    /// For the preview and the image sample: a fixed model, never fetches.
    init(preview model: WeatherModel) {
        self.model = model
        live = false
    }

    var paused: Bool {
        get { demand.paused }
        set { demand.paused = newValue; sync() }
    }

    func acquire() { demand.acquire(); sync() }
    func release() { demand.release(); sync() }

    private func sync() {
        guard live, demand.isActive != running else { return }
        running = demand.isActive
        if running {
            model.start()
        } else {
            model.stop()
        }
    }
}

/// Name and symbol of an app for the app block and Nexus, read once. Apps
/// that are not installed are not remembered: if the app turns up later, it
/// appears on the next drawing.
@MainActor
enum BarApps {
    struct Info {
        let name: String
        let icon: NSImage
    }

    private static var cache: [String: Info] = [:]
    private static let log = Logger(category: "bar")

    static func info(for bundleID: String) -> Info? {
        guard !bundleID.isEmpty else { return nil }
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let info = Info(name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                        icon: NSWorkspace.shared.icon(forFile: url.path))
        cache[bundleID] = info
        return info
    }

    /// Like a click in the Dock: if it runs, to the front, otherwise start it.
    static func open(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [log] _, error in
            if let error {
                log.error("App-Knopf: Start fehlgeschlagen: \((error as NSError).code, privacy: .public)")
            }
        }
    }
}

// MARK: - Views

/// Button of the bar for blocks with text (battery, CPU, weather): 32 wide,
/// at least 32 high, otherwise like `SidebarIcon` (hover, tooltip).
struct BarTile<Content: View>: View {
    let help: String
    var action: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @State private var hovering = false
    @Environment(\.barPreview) private var preview

    init(help: String, action: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.help = help
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: { action?() }) {
            content()
                .padding(.vertical, 5)
                .frame(width: 32)
                .frame(minHeight: 32)
                .background(Color.primary.opacity(hovering ? 0.14 : 0), in: .rect(cornerRadius: 9))
                .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background {
            if !preview { HoverTracker { hovering = $0 } }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Starts a chosen app. Without an app (freshly added) or when it is no
/// longer installed: a dashed placeholder that does nothing.
struct BarAppButton: View {
    let bundleID: String
    let onOpen: @MainActor (String) -> Void

    var body: some View {
        let info = BarApps.info(for: bundleID)
        SidebarIcon(help: info.map { String(localized: "Open \($0.name)") } ?? String(localized: "No app chosen (Nexus > Bar)"),
                    action: { if info != nil { onOpen(bundleID) } }) {
            if let info {
                Image(nsImage: info.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The charge as a number, above it the symbol on request. Without a battery
/// (a desktop Mac): nothing - like the battery in the status capsule. A click
/// opens the "Performance" tab with the battery gauge and the time left.
struct BarBatteryModule: View {
    let status: StatusModel
    let options: BarBatteryOptions
    let onOpen: () -> Void

    var body: some View {
        if let battery = status.battery, let symbol = StatusGlyphs.batterySymbol(battery) {
            // Red like Apple's battery symbol as soon as the last warning level is reached.
            let low = battery.level <= 10 && !battery.charging && !battery.onAC
            BarTile(help: StatusGlyphs.batteryText(battery), action: onOpen) {
                VStack(spacing: 3) {
                    if options.showIcon {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("\(battery.level)%")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(low ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
            }
        }
    }
}

/// CPU as a ring with a number (like the rings in the dashboard) or as a
/// symbol with percent. Registers with the model and signs off again - that
/// way it only measures while the block stands in the bar.
struct BarCPUModule: View {
    let model: BarCPUModel
    let options: BarCPUOptions
    let onOpen: () -> Void

    var body: some View {
        let percent = model.usage.map { Int(($0 * 100).rounded()) }
        BarTile(help: percent.map { String(localized: "CPU \($0)%") } ?? "CPU", action: onOpen) {
            switch options.style {
            case .ring:
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.15), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: model.usage ?? 0)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(percent.map(String.init) ?? "–")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 24, height: 24)
                .animation(.easeOut(duration: 0.3), value: model.usage)
            case .percent:
                VStack(spacing: 3) {
                    Image(systemName: "cpu")
                        .font(.system(size: 13, weight: .semibold))
                    Text(percent.map { "\($0)%" } ?? "–")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .onAppear { model.acquire() }
        .onDisappear { model.release() }
    }
}

/// The weather symbol in multicolor (as in the dashboard), below it the
/// temperature on request. Place and data as in the dashboard (Open-Meteo).
struct BarWeatherModule: View {
    let feed: BarWeatherFeed
    let options: BarWeatherOptions
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let model = feed.model
        let current = model.report?.current
        BarTile(help: model.location.map { location in
                    current.map { String(localized: "\(WeatherCondition.description(code: $0.code)) in \(location.name)") }
                        ?? String(localized: "Weather in \(location.name)")
                } ?? String(localized: "Set Location in Nexus"),
                action: onOpen) {
            VStack(spacing: 2) {
                if let current {
                    Image(systemName: WeatherCondition.symbol(code: current.code, isDay: current.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 15))
                        // White clouds would otherwise vanish in the light glass
                        // (the same finding as in the dashboard, WeatherView.swift).
                        .shadow(color: .black.opacity(colorScheme == .light ? 0.35 : 0), radius: 0.6)
                    if options.showTemperature {
                        Text(WeatherText.temperature(current.temperature))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                } else {
                    Image(systemName: "cloud.sun")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if options.showTemperature {
                        Text("--°")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { feed.acquire() }
        .onDisappear { feed.release() }
    }
}

// MARK: - Colors

extension BarModuleKind {
    /// Tile color in Nexus, like the page symbols of System Settings. The
    /// helpers for the arrangement (gaps, rule) stay grey.
    var tint: Color {
        switch self {
        case .dashboardButton: .indigo
        case .workspaces: .teal
        case .dock: .blue
        case .clock: .purple
        case .utilitiesButton: .gray
        case .statusIcons: .blue
        case .power: .red
        case .spacer, .gap, .divider: .gray
        case .appButton: .blue
        case .battery: .green
        case .cpu: .orange
        case .weather: .cyan
        case .mediaButton: .pink
        }
    }
}
