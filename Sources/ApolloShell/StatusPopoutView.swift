import ApolloShellCore
import SwiftUI

/// Caelestias Kurven (Tokens.anim): Raum 500 ms mit leichtem Ueberschiessen
/// fuer Groesse und Lage, Effekte 200/300 ms fuer das Ueberblenden.
enum StatusPopoutMotion {
    static let spatial = Animation.timingCurve(0.38, 1.21, 0.22, 1, duration: 0.5)
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
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch kind {
            case .wifi: StatusPopoutWifiView(model: model)
            case .bluetooth: StatusPopoutBluetoothView(model: model)
            case .battery: StatusPopoutBatteryView(model: model)
            }
        }
        .padding(16)
        .frame(width: Self.width(kind), alignment: .leading)
    }
}

// MARK: - WLAN

private struct StatusPopoutWifiView: View {
    let model: StatusPopoutModel

    var body: some View {
        let wifi = model.wifi
        StatusPopoutHeader(title: "WLAN") {
            if let wifi {
                Toggle("WLAN", isOn: Binding(get: { wifi.powerOn }, set: { model.setWifiPower($0) }))
                    .toggleStyle(StatusPopoutSwitchStyle())
            }
        }
        if let wifi, wifi.connected {
            let glyph = StatusGlyphs.wifi(powerOn: true, rssi: wifi.rssi)
            StatusPopoutLeadRow(
                symbol: glyph.symbol, variableValue: glyph.strength, active: true,
                title: "Verbunden",
                // macOS 14+: der Netzname braucht die Ortungsfreigabe; die
                // holen wir nicht fuer eine Anzeige.
                subtitle: "Netzname nur mit Ortungsfreigabe"
            )
            StatusPopoutCard {
                StatusPopoutValueRow(
                    label: "Signal",
                    value: "\(wifi.rssi ?? 0) dBm · \(StatusPopoutSignal.quality(rssi: wifi.rssi))"
                )
                if let noise = wifi.noise, noise != 0 {
                    let snr = StatusPopoutSignal.signalToNoise(rssi: wifi.rssi, noise: noise).map { " · SNR \($0) dB" } ?? ""
                    StatusPopoutValueRow(label: "Rauschen", value: "\(noise) dBm\(snr)")
                }
                if let rate = wifi.transmitRate, rate > 0 {
                    StatusPopoutValueRow(label: "Senderate", value: "\(Int(rate.rounded())) Mbit/s")
                }
                if let phy = StatusPopoutSignal.phyModeName(rawValue: wifi.phyMode) {
                    StatusPopoutValueRow(label: "Standard", value: phy)
                }
                if let channel = wifi.channel {
                    let band = wifi.band.flatMap { StatusPopoutSignal.bandName(rawValue: $0) }.map { " · \($0)" } ?? ""
                    StatusPopoutValueRow(label: "Kanal", value: "\(channel)\(band)")
                }
                if let name = wifi.interfaceName {
                    StatusPopoutValueRow(label: "Interface", value: name)
                }
            }
        } else {
            StatusPopoutLeadRow(
                symbol: wifi?.powerOn == true ? "wifi" : "wifi.slash", variableValue: 0, active: false,
                title: wifi == nil ? "Kein WLAN-Interface" : wifi?.powerOn == true ? "Nicht verbunden" : "WLAN ist aus",
                subtitle: wifi?.powerOn == true ? "Kein Netz in Reichweite verbunden" : nil
            )
        }
        StatusPopoutSettingsButton(title: "WLAN-Einstellungen …") { model.openSettings(for: .wifi) }
    }
}

// MARK: - Bluetooth

private struct StatusPopoutBluetoothView: View {
    let model: StatusPopoutModel
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        let snapshot = model.bluetooth
        StatusPopoutHeader(title: "Bluetooth") {
            // Nur Anzeige: Schalten ginge nur ueber private Schnittstellen.
            Text(snapshot?.powerOn == true ? String(localized: "An") : snapshot?.powerOn == false ? String(localized: "Aus") : "–")
                .font(style.font(size: 12, weight: .semibold))
                .foregroundStyle(snapshot?.powerOn == true ? AnyShapeStyle(style.onAccent) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    snapshot?.powerOn == true ? AnyShapeStyle(style.accent) : AnyShapeStyle(Color.primary.opacity(0.10)),
                    in: .capsule
                )
                .help("Ein- und ausschalten geht nur in den Systemeinstellungen")
        }
        if !model.bluetoothRead {
            StatusPopoutNote(text: String(localized: "Geräte werden gelesen …"))
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
            StatusPopoutNote(text: String(localized: "Bluetooth-Zustand nicht lesbar"))
        }
        StatusPopoutSettingsButton(title: "Bluetooth-Einstellungen …",
                                   help: "Ein- und ausschalten geht nur dort") {
            model.openSettings(for: .bluetooth)
        }
    }

    /// Caelestia: "%n devices available (%1 connected)".
    private static func countText(connected: Int, paired: Int) -> String {
        let pairedText = paired == 1 ? String(localized: "1 gekoppeltes Gerät") : String(localized: "\(paired) gekoppelte Geräte")
        guard paired > 0 else { return String(localized: "Keine gekoppelten Geräte") }
        return connected == 0 ? String(localized: "\(pairedText), keins verbunden") : String(localized: "\(pairedText), \(connected) verbunden")
    }
}

/// Symbol im Kreis, Name, darunter die Akkuwerte (L/R/Case bei AirPods).
/// Zweizeilig wie im Kontrollzentrum: rechts daneben gekuerzte Namen
/// ("AirPo...") waren in der Bildprobe schlechter als eine zweite Zeile.
private struct StatusPopoutDeviceRow: View {
    let device: StatusPopoutBluetoothDevice
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

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
                    Text("Verbunden")
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
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

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
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

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
                StatusPopoutValueRow(label: "Stromsparmodus", value: info.lowPowerMode ? String(localized: "An") : String(localized: "Aus"))
                if let health = info.healthPercent {
                    StatusPopoutValueRow(label: "Maximale Kapazität", value: "\(health) %")
                }
                if let cycles = info.cycleCount {
                    StatusPopoutValueRow(label: "Ladezyklen", value: "\(cycles)")
                }
            }
            StatusPopoutSettingsButton(title: "Batterie-Einstellungen …") { model.openSettings(for: .battery) }
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
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

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
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

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
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        VStack(spacing: 7) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: style.cardRadius(12)))
    }
}

private struct StatusPopoutValueRow: View {
    let label: LocalizedStringKey
    let value: String
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

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
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

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
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

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
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

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
        .accessibilityValue(on ? "an" : "aus")
    }
}
