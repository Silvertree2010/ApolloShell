import AppKit
import ApolloShellCore
import Observation
import os
import SwiftUI

// Was die Bausteine der Leiste brauchen (Modelle, Aktionen) und die
// Bausteine, die mit dem Baukasten dazukamen: App, Akku, CPU, Wetter. Die
// sieben der bisherigen Leiste stehen weiter in SidebarContent.swift,
// SidebarModules.swift und SidebarDock.swift; welche Art wie gezeichnet wird,
// entscheidet `BarModuleView`.

/// Klassischer Umgebungsschluessel statt `@Entry`: das Makro braucht das
/// SwiftUI-Makro-Plugin, und das bringen die Command Line Tools nicht mit.
private struct BarPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// In der Vorschau von Nexus: keine Maus-Ansichten (Hover, Dock-Klicks,
    /// Ziehen). Die Vorschau ist verkleinert, AppKit-Ansichten machen das
    /// nicht mit - ihre Flaechen laegen neben den Symbolen und reagierten
    /// ueber dem Formular. Und ein Klick soll dort keine echte App starten.
    var barPreview: Bool {
        get { self[BarPreviewKey.self] }
        set { self[BarPreviewKey.self] = newValue }
    }
}

/// Modelle und Aktionen fuer alle Bausteine. Die Leiste gibt die echten,
/// die Vorschau in Nexus feste Vorschau-Modelle ohne Aktionen.
@MainActor
struct BarModuleContext {
    var status: StatusModel
    var spaces: SpacesModel
    var dock: SidebarDockModel
    var clock: SidebarClockModel
    var cpu: BarCPUModel
    var weather: BarWeatherFeed
    var onDashboard: @MainActor () -> Void = {}
    /// Medien, Wetter, CPU, Akku: gleich beim passenden Reiter.
    var onDashboardTab: @MainActor (DashboardTab) -> Void = { _ in }
    var onUtilities: @MainActor () -> Void = {}
    var onPower: @MainActor () -> Void = {}
    var onSelectSpace: @MainActor (Int) -> Void = { _ in }
    var onOpenApp: @MainActor (String) -> Void = { _ in }
}

// MARK: - Bedarf

/// Wie viele sichtbare Bausteine ein Modell gerade brauchen. Gemessen oder
/// abgerufen wird nur, solange mindestens einer in der Leiste steht UND die
/// Leiste zu sehen ist (`paused` = im Vollbild abgetreten). Ohne CPU- oder
/// Wetter-Baustein kosten die Modelle also nichts.
struct BarDemand {
    private(set) var users = 0
    var paused = false

    var isActive: Bool { users > 0 && !paused }

    mutating func acquire() { users += 1 }

    /// Nie unter 0: kaeme ein onDisappear ohne onAppear, soll der naechste
    /// Baustein trotzdem wieder messen.
    mutating func release() { users = max(users - 1, 0) }
}

/// CPU-Auslastung fuer den CPU-Baustein. Alle 2 s (die Ringe des Dashboards
/// messen jede Sekunde, aber nur, solange es offen ist - die Leiste ist
/// immer da, also halb so oft) und nur bei Bedarf, siehe `BarDemand`. Eine
/// Messung sind zwei Mach-Aufrufe, Mikrosekunden.
@MainActor
@Observable
final class BarCPUModel {
    /// 0...1, auf ganze Prozent gerundet: so zeichnet die Leiste nur neu,
    /// wenn sich die angezeigte Zahl aendert. `nil` bis zur zweiten Messung.
    private(set) var usage: Double?

    static let interval: TimeInterval = 2

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var demand = BarDemand()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: CPUTicks?

    init() {
        live = true
    }

    /// Fuer Vorschau und Bildprobe: fester Wert, misst nie.
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
            // Darf etwas spaeter kommen: macOS legt Timer dann zusammen.
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !demand.isActive, let timer {
            timer.invalidate()
            self.timer = nil
            // Nach der Pause neu anfangen: ueber die Pause gemittelt waere falsch.
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

/// Wetter fuer den Wetter-Baustein: ein eigenes `WeatherModel`, das nur
/// abruft, solange der Baustein zu sehen ist (beim Erscheinen, wenn die
/// Daten aelter als 15 min sind, dann alle 30 min - die Regeln des Modells).
///
/// Eigenes statt das des Dashboards: das startet und stoppt seines beim
/// Oeffnen und Schliessen; ein geteiltes wuerde die Leiste mit dem Schliessen
/// des Dashboards anhalten. Preis: mit beiden sichtbar hoechstens ein
/// zusaetzlicher Abruf je halbe Stunde.
@MainActor
final class BarWeatherFeed {
    let model: WeatherModel
    private let live: Bool
    private var demand = BarDemand()
    private var running = false

    /// `settings`: welcher Wetteranbieter (Nexus > Anbieter), wie im Dashboard.
    init(settings: ShellSettingsStore) {
        model = WeatherModel(settings: settings)
        live = true
    }

    /// Fuer Vorschau und Bildprobe: festes Modell, ruft nie ab.
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

/// Name und Symbol einer App fuer den App-Baustein und Nexus, einmal
/// gelesen. Nicht installierte werden nicht gemerkt: kommt die App spaeter
/// dazu, erscheint sie beim naechsten Zeichnen.
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

    /// Wie ein Klick im Dock: laeuft sie, nach vorne, sonst starten.
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

// MARK: - Ansichten

/// Knopf der Leiste fuer Bausteine mit Text (Akku, CPU, Wetter): 32 breit,
/// mindestens 32 hoch, sonst wie `SidebarIcon` (Hover, Tooltip).
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

/// Startet eine gewaehlte App. Ohne App (frisch hinzugefuegt) oder nicht
/// mehr installiert: gestrichelter Platzhalter, der nichts tut.
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

/// Ladestand als Zahl, darueber auf Wunsch das Symbol. Ohne Akku
/// (Desktop-Mac): nichts - wie der Akku in der Statuskapsel. Klick oeffnet
/// den Reiter "Performance" mit dem Akku-Tank und der Restzeit.
struct BarBatteryModule: View {
    let status: StatusModel
    let options: BarBatteryOptions
    let onOpen: () -> Void

    var body: some View {
        if let battery = status.battery, let symbol = StatusGlyphs.batterySymbol(battery) {
            // Rot wie Apples Akkusymbol, sobald die letzte Warnstufe erreicht ist.
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

/// CPU als Ring mit Zahl (wie die Ringe im Dashboard) oder als Symbol mit
/// Prozent. Meldet sich beim Modell an und ab - so misst es nur, solange
/// der Baustein in der Leiste steht.
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

/// Wettersymbol in Mehrfarben (wie im Dashboard), darunter auf Wunsch die
/// Temperatur. Ort und Daten wie im Dashboard (weather.json, Open-Meteo).
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
                        // Weisse Wolken verschwinden sonst im hellen Glas
                        // (derselbe Befund wie im Dashboard, WeatherView.swift).
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

// MARK: - Farben

extension BarModuleKind {
    /// Kachelfarbe in Nexus, wie die Seitensymbole der Systemeinstellungen.
    /// Die Helfer fuer die Anordnung (Abstaende, Strich) bleiben grau.
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
