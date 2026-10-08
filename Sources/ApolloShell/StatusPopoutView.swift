import ApolloShellCore
import SwiftUI

/// Caelestias Kurven (Tokens.anim): Raum 500 ms mit leichtem Ueberschiessen
/// fuer Groesse und Lage, Effekte 200/300 ms fuer das Ueberblenden.
enum StatusPopoutMotion {
    static var spatial: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeOut(duration: 0.2) : .shellSpatial
    }
    static let fadeOut = Animation.timingCurve(0.34, 0.8, 0.34, 1, duration: 0.2)
    static let fadeIn = Animation.timingCurve(0.34, 0.88, 0.34, 1, duration: 0.3)
}

/// Nur fuer Bildproben: statt Glas eine feste Flaeche, denn Glas zeichnet
/// ausserhalb des Bildschirms nur weiss. Klassischer Schluessel statt
/// `@Entry`: ohne Xcode fehlt SwiftPM das SwiftUI-Makro-Plugin.
private struct StatusPopoutGlassStandInKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var statusPopoutGlassStandIn: Bool {
        get { self[StatusPopoutGlassStandInKey.self] }
        set { self[StatusPopoutGlassStandInKey.self] = newValue }
    }
}

/// Masse der Ausbeulung, mit der die Leiste das Popout zeigt
/// (Caelestia: ClipWrapper + Wrapper + Content).
///
/// Leiste und Popout sind EINE Glasflaeche (`SidebarGlassShape`): zwei
/// getrennte Glaeser nebeneinander faerben sich verschieden ein - jedes
/// nimmt die Farbe dessen an, was hinter ihm liegt - und zeigen an der
/// Naht eine Kante. Deshalb zeichnet die Leiste ihr Glas als eine Form,
/// die sich beim Oeffnen auswoelbt.
enum StatusPopoutLayout {
    /// Ecken der Ausbeulung.
    static let cornerRadius: CGFloat = 25
    /// Hoehe der Beule im geschlossenen Zustand: null, sie sitzt in der
    /// Leiste.
    static let seedHeight: CGFloat = 30
    /// Radius der einwaertsgekruemmten Ecken, mit denen die Beule in die
    /// Leiste uebergeht.
    static let join: CGFloat = 14
}

/// Inhalt eines Detailfensters, fest breit, Hoehe aus dem Inhalt.
/// Rand 16 wie Caelestia (Tokens.padding.large).
struct StatusPopoutContent: View {
    let model: StatusPopoutModel
    let kind: StatusPopoutKind

    /// Caelestia: Netzwerk 320, Bluetooth 300, Akku 250 (ohne Rand). Etwas
    /// schmaler, damit es neben der schmalen Leiste nicht wuchtig wirkt;
    /// die Werte-Zeilen passen trotzdem einzeilig.
    static func width(_ kind: StatusPopoutKind) -> CGFloat {
        switch kind {
        case .wifi: 300
        case .bluetooth: 300
        case .battery: 270
        case .stack: 300
        case .sound: 300
        }
    }

    var body: some View {
        if kind == .stack {
            DockStackView(model: model)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                switch kind {
                case .wifi: StatusPopoutWifiView(model: model)
                case .bluetooth: StatusPopoutBluetoothView(model: model)
                case .battery: StatusPopoutBatteryView(model: model)
                case .stack: EmptyView()
                case .sound: StatusPopoutSoundView(model: model)
                }
            }
            .padding(16)
            .frame(width: Self.width(kind), alignment: .leading)
        }
    }
}

// MARK: - WLAN

private struct StatusPopoutWifiView: View {
    let model: StatusPopoutModel

    var body: some View {
        let wifi = model.wifi
        StatusPopoutHeader(title: "Wi-Fi") {
            if let wifi {
                Toggle("Wi-Fi", isOn: Binding(get: { wifi.powerOn }, set: { model.setWifiPower($0) }))
                    .toggleStyle(StatusPopoutSwitchStyle())
            }
        }
        if let wifi, wifi.connected {
            let glyph = StatusGlyphs.wifi(powerOn: true, rssi: wifi.rssi)
            StatusPopoutLeadRow(
                symbol: glyph.symbol, variableValue: glyph.strength, active: true,
                title: "Connected",
                subtitle: "\(StatusPopoutSignal.quality(rssi: wifi.rssi))"
            )
        } else {
            StatusPopoutLeadRow(
                symbol: wifi?.powerOn == true ? "wifi" : "wifi.slash", variableValue: 0, active: false,
                title: wifi == nil ? "No Wi-Fi Interface" : wifi?.powerOn == true ? "Not Connected" : "Wi-Fi Is Off",
                subtitle: wifi?.powerOn == true ? "No Network in Range Connected" : nil
            )
        }
        if wifi?.powerOn == true, model.live {
            StatusPopoutNetworkList(nets: model.nets)
        }
        StatusPopoutSpeedCard(model: model)
        StatusPopoutSettingsButton(title: "Wi-Fi Settings…") { model.openSettings(for: .wifi) }
    }
}

// MARK: - Bluetooth

private struct StatusPopoutBluetoothView: View {
    let model: StatusPopoutModel
    @Environment(\.shellStyle) private var style

    var body: some View {
        let snapshot = model.bluetooth
        StatusPopoutHeader(title: "Bluetooth") {
            // Nur Anzeige: Schalten ginge nur ueber private Schnittstellen.
            Text(snapshot?.powerOn == true ? String(localized: "On") : snapshot?.powerOn == false ? String(localized: "Off") : "–")
                .font(style.font(size: 12, weight: .semibold))
                .foregroundStyle(snapshot?.powerOn == true ? AnyShapeStyle(style.onAccent) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    snapshot?.powerOn == true ? AnyShapeStyle(style.accent) : AnyShapeStyle(Color.primary.opacity(0.10)),
                    in: .capsule
                )
                .help("Turning it on or off only works in System Settings")
        }
        if !model.bluetoothRead {
            StatusPopoutNote(text: String(localized: "Reading devices…"))
        } else if let snapshot {
            let connected = snapshot.connected
            StatusPopoutNote(text: Self.countText(connected: connected.count, paired: snapshot.pairedCount))
            if !connected.isEmpty {
                VStack(spacing: 6) {
                    ForEach(connected) { device in
                        StatusPopoutDeviceRow(device: device)
                    }
                }
            }
        } else {
            StatusPopoutNote(text: String(localized: "Bluetooth state unavailable"))
        }
        StatusPopoutSettingsButton(title: "Bluetooth Settings…",
                                   help: "Turning it on or off only works there") {
            model.openSettings(for: .bluetooth)
        }
    }

    /// Caelestia: "%n devices available (%1 connected)".
    private static func countText(connected: Int, paired: Int) -> String {
        let pairedText = paired == 1 ? String(localized: "1 paired device") : String(localized: "\(paired) paired devices")
        guard paired > 0 else { return String(localized: "No paired devices") }
        return connected == 0 ? String(localized: "\(pairedText), none connected") : String(localized: "\(pairedText), \(connected) verbunden")
    }
}

/// Symbol im Kreis, Name, darunter die Akkuwerte (L/R/Case bei AirPods).
/// Zweizeilig wie im Kontrollzentrum: rechts daneben gekuerzte Namen
/// ("AirPo...") waren in der Bildprobe schlechter als eine zweite Zeile.
private struct StatusPopoutDeviceRow: View {
    let device: StatusPopoutBluetoothDevice
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbol)
                .font(style.font(size: 13, weight: .medium))
                .foregroundStyle(style.onAccent)
                .frame(width: 30, height: 30)
                .background(style.accent, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(style.font(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if device.batteries.isEmpty {
                    Text("Connected")
                        .font(style.font(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ForEach(device.batteries, id: \.part) { battery in
                            StatusPopoutBatteryChip(battery: battery)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct StatusPopoutBatteryChip: View {
    let battery: StatusPopoutBluetoothBattery
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 3) {
            if let label = battery.label {
                Text(label).foregroundStyle(.secondary)
            }
            Text("\(battery.percent) %")
                // Unter 20 % rot wie Caelestia (m3error).
                .foregroundStyle(battery.percent < 20 ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
        }
        .font(style.font(size: 11, weight: .medium).monospacedDigit())
        .fixedSize()
    }
}

// MARK: - Akku

private struct StatusPopoutBatteryView: View {
    let model: StatusPopoutModel
    @Environment(\.shellStyle) private var style

    var body: some View {
        if let info = model.battery {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                let number = Text("\(info.state.level)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                let unit = Text("%")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("\(number) \(unit)")
                Spacer(minLength: 0)
                if let symbol = StatusGlyphs.batterySymbol(info.state) {
                    Image(systemName: symbol)
                        .font(style.font(size: 22, weight: .regular))
                        .foregroundStyle(info.state.charging ? AnyShapeStyle(style.accent) : AnyShapeStyle(.secondary))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(StatusPopoutBatteryText.state(info.state))
                    .font(style.font(size: 13, weight: .semibold))
                Text(StatusPopoutBatteryText.time(
                    info.state, minutesToEmpty: info.minutesToEmpty, minutesToFull: info.minutesToFull
                ))
                .font(style.font(size: 12))
                .foregroundStyle(.secondary)
            }
            StatusPopoutCard {
                StatusPopoutValueRow(label: "Low Power Mode", value: info.lowPowerMode ? String(localized: "On") : String(localized: "Off"))
                if let health = info.healthPercent {
                    StatusPopoutValueRow(label: "Maximum Capacity", value: "\(health) %")
                }
                if let cycles = info.cycleCount {
                    StatusPopoutValueRow(label: "Charge Cycles", value: "\(cycles)")
                }
            }
            StatusPopoutSettingsButton(title: "Battery Settings…") { model.openSettings(for: .battery) }
        }
    }
}

// MARK: - Bausteine

/// Titelzeile: Name links, Schalter oder Zustand rechts (Caelestia:
/// fette Ueberschrift, darunter "Enabled" mit Schalter - bei Apple steht
/// der Schalter in der Titelzeile).
private struct StatusPopoutHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let trailing: Trailing
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack {
            Text(title).font(style.font(size: 15, weight: .semibold))
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 24)
    }
}

/// Grosses Symbol im Kreis mit zwei Zeilen - wie Apples Netzzeile im
/// Kontrollzentrum. Aktiv: Akzentkreis.
private struct StatusPopoutLeadRow: View {
    let symbol: String
    let variableValue: Double
    let active: Bool
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol, variableValue: variableValue)
                .font(style.font(size: 14, weight: .semibold))
                .foregroundStyle(active ? AnyShapeStyle(style.onAccent) : AnyShapeStyle(.secondary))
                .frame(width: 30, height: 30)
                .background(active ? AnyShapeStyle(style.accent) : AnyShapeStyle(Color.primary.opacity(0.10)), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(style.font(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle).font(style.font(size: 11)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
        }
    }
}

/// Leicht abgesetzte Flaeche wie die Karten der Utilities.
private struct StatusPopoutCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 7) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .cardSurface(radius: 12)
    }
}

private struct StatusPopoutValueRow: View {
    let label: LocalizedStringKey
    let value: String
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(style.font(size: 12))
        .lineLimit(1)
    }
}

private struct StatusPopoutNote: View {
    let text: String
    @Environment(\.shellStyle) private var style

    var body: some View {
        Text(text)
            .font(style.font(size: 12))
            .foregroundStyle(.secondary)
    }
}

/// Knopf unten ueber die ganze Breite (Caelestia: "Open settings",
/// IconTextButton in primaryContainer). Leicht getoent statt voll Akzent:
/// es ist eine Nebenaktion.
private struct StatusPopoutSettingsButton: View {
    let title: LocalizedStringKey
    var help: LocalizedStringKey?
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.shellStyle) private var style

    init(title: LocalizedStringKey, help: LocalizedStringKey? = nil, action: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                Text(title)
            }
            .font(style.font(size: 12, weight: .medium))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(Color.primary.opacity(hovering ? 0.14 : 0.08), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        // Nicht `onHover`: das Fenster gehoert einer nie aktiven App (siehe
        // HoverTracker).
        .background(HoverTracker { hovering = $0 })
        .animation(StatusPopoutMotion.fadeOut, value: hovering)
        .help(help ?? title)
        .padding(.top, 2)
    }
}

/// Schalter im macOS-26-Aussehen, "an" immer in Akzentfarbe.
///
/// Warum nicht `.toggleStyle(.switch)`: AppKit zeichnet den eingeschalteten
/// Schalter grau, solange die App nicht aktiv ist - und der Launcher wird nie
/// aktiv (Bildprobe der Utilities 14.09.). Masse wie dort: Bahn 54 x 24,
/// Knopf 32 x 20.
private struct StatusPopoutSwitchStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(on ? AnyShapeStyle(style.accent) : AnyShapeStyle(Color.primary.opacity(0.10)))
                .frame(width: 54, height: 24)
                .overlay {
                    Capsule()
                        .fill(colorScheme == .dark ? Color(white: 0.91) : Color.white)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                        .frame(width: 32, height: 20)
                        .offset(x: on ? 9 : -9)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(StatusPopoutMotion.fadeOut, value: on)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(on ? "On" : "Off")
    }
}

@MainActor
@Observable
final class StatusPopoutSoundBox {
    var model: UtilitiesModel?
}

@MainActor
enum StatusPopoutSound {
    static let box = StatusPopoutSoundBox()
    static var model: UtilitiesModel? {
        get { box.model }
        set { box.model = newValue }
    }
    private static var on = false

    static func use(_ v: Bool) {
        guard v != on, let model else { return }
        on = v
        if v { model.acquire() } else { model.release() }
    }
}

private struct StatusPopoutSoundView: View {
    let model: StatusPopoutModel

    var body: some View {
        if let m = StatusPopoutSound.box.model {
            UtilitiesAudioCard(model: m)
                .frame(width: StatusPopoutContent.width(.sound) - 32, height: UtilitiesMetrics.audioHeight)
            Button("Sound Settings…") { model.openSettings(for: .sound) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusPopoutSpeedCard: View {
    let model: StatusPopoutModel

    var body: some View {
        StatusPopoutCard {
            switch model.speed {
            case .idle, .failed:
                HStack {
                    Text(model.speed == .failed ? "Speed test failed" : "Speed Test")
                        .foregroundStyle(model.speed == .failed ? .secondary : .primary)
                    Spacer()
                    Button(model.speed == .failed ? "Try Again" : "Run") { model.runSpeedTest() }
                        .controlSize(.small)
                }
            case .running(let r, let start):
                StatusPopoutValueRow(label: "Download", value: r.map { SpeedResult.mbit($0.down) } ?? "…")
                StatusPopoutValueRow(label: "Upload", value: r.map { SpeedResult.mbit($0.up) } ?? "…")
                TimelineView(.periodic(from: start, by: 0.25)) { ctx in
                    ProgressView(value: min(1, ctx.date.timeIntervalSince(start) / StatusPopoutModel.speedLimit))
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            case .done(let r):
                StatusPopoutValueRow(label: "Download", value: SpeedResult.mbit(r.down))
                StatusPopoutValueRow(label: "Upload", value: SpeedResult.mbit(r.up))
                if let resp = r.responsiveness {
                    StatusPopoutValueRow(label: "Responsiveness", value: resp)
                }
                HStack {
                    Spacer()
                    Button("Run Again") { model.runSpeedTest() }
                        .controlSize(.small)
                }
            }
        }
        .help("Measured with Apple's networkQuality against Apple's servers.")
    }
}

private struct StatusPopoutNetworkList: View {
    static let shown = 5
    let nets: WifiNetworks

    @MainActor static func menu(_ nets: WifiNetworks) {
        let m = NSMenu()
        for n in nets.nets {
            let i = DockSmartMenu.Item(n.ssid) { nets.join(n) }
            i.image = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)
            m.addItem(i)
        }
        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @Environment(\.shellStyle) private var style

    var body: some View {
        if !nets.nets.isEmpty || nets.loading {
            StatusPopoutCard {
                HStack {
                    Text("Saved Networks").font(style.font(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    if nets.loading { ProgressView().controlSize(.mini) }
                }
                ForEach(nets.nets.prefix(Self.shown)) { n in
                    StatusPopoutNetworkRow(net: n, joining: nets.joining == n.ssid, failed: nets.failed == n.ssid) { nets.join(n) }
                }
                if nets.nets.count > Self.shown {
                    Button {
                        Self.menu(nets)
                    } label: {
                        HStack {
                            Text("All Saved Networks (\(nets.nets.count))…")
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                        .font(style.font(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct StatusPopoutNetworkRow: View {
    let net: WifiNet
    let joining: Bool
    let failed: Bool
    let action: () -> Void
    @State private var hov = false
    @Environment(\.shellStyle) private var style

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                Text(verbatim: net.ssid).lineLimit(1)
                Spacer(minLength: 6)
                if joining {
                    ProgressView().controlSize(.mini)
                } else if failed {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .font(style.font(size: 12))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(hov ? 0.1 : 0), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(joining)
        .background { HoverTracker { hov = $0 } }
        .help(failed ? String(localized: "Not in range or could not join") : String(localized: "Join"))
    }
}
