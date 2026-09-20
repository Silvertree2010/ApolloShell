import ApolloShellCore
import SwiftUI

/// Caelestia's curves (Tokens.anim): space 500 ms with a slight overshoot for
/// size and place, effects 200/300 ms for the cross-fade.
enum StatusPopoutMotion {
    static let spatial = Animation.shellSpatial
    static let fadeOut = Animation.timingCurve(0.34, 0.8, 0.34, 1, duration: 0.2)
    static let fadeIn = Animation.timingCurve(0.34, 0.88, 0.34, 1, duration: 0.3)
}

/// Only for image samples: a fixed area instead of glass, because glass draws
/// only white offscreen. A classic key instead of `@Entry`: without Xcode
/// SwiftPM has no SwiftUI macro plugin.
private struct StatusPopoutGlassStandInKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var statusPopoutGlassStandIn: Bool {
        get { self[StatusPopoutGlassStandInKey.self] }
        set { self[StatusPopoutGlassStandInKey.self] = newValue }
    }
}

/// The measurements of the bulge the bar shows the popout with
/// (Caelestia: ClipWrapper + Wrapper + Content).
///
/// The bar and the popout are ONE glass area (`SidebarGlassShape`): two
/// separate pieces of glass side by side take on different colors - each one
/// takes the color of what lies behind it - and show an edge at the seam. So
/// the bar draws its glass as one shape that bulges out on opening.
///
enum StatusPopoutLayout {
    /// The corners of the bulge.
    static let cornerRadius: CGFloat = 25
    /// The height of the bulge when closed: zero, it sits in the bar.
    ///
    static let seedHeight: CGFloat = 30
    /// The radius of the inward-curved corners the bulge goes over into the
    /// bar with.
    static let join: CGFloat = 14
}

/// The content of a detail window, fixed width, the height out of the content.
/// A margin of 16 as in Caelestia (Tokens.padding.large).
struct StatusPopoutContent: View {
    let model: StatusPopoutModel
    let kind: StatusPopoutKind

    /// Caelestia: network 320, Bluetooth 300, battery 250 (without the
    /// margin). A little narrower, so that it does not look bulky next to the
    /// narrow bar; the value lines still fit on one line.
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

// MARK: - Wi-Fi

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
                // macOS 14+: the network name needs the location permission;
                // we do not fetch that for a display.
                subtitle: "Network name needs Location Services"
            )
            StatusPopoutCard {
                StatusPopoutValueRow(
                    label: "Signal",
                    value: "\(wifi.rssi ?? 0) dBm · \(StatusPopoutSignal.quality(rssi: wifi.rssi))"
                )
                if let noise = wifi.noise, noise != 0 {
                    let snr = StatusPopoutSignal.signalToNoise(rssi: wifi.rssi, noise: noise).map { " · SNR \($0) dB" } ?? ""
                    StatusPopoutValueRow(label: "Noise", value: "\(noise) dBm\(snr)")
                }
                if let rate = wifi.transmitRate, rate > 0 {
                    StatusPopoutValueRow(label: "Transmit Rate", value: "\(Int(rate.rounded())) Mbit/s")
                }
                if let phy = StatusPopoutSignal.phyModeName(rawValue: wifi.phyMode) {
                    StatusPopoutValueRow(label: "Standard", value: phy)
                }
                if let channel = wifi.channel {
                    let band = wifi.band.flatMap { StatusPopoutSignal.bandName(rawValue: $0) }.map { " · \($0)" } ?? ""
                    StatusPopoutValueRow(label: "Channel", value: "\(channel)\(band)")
                }
                if let name = wifi.interfaceName {
                    StatusPopoutValueRow(label: "Interface", value: name)
                }
            }
        } else {
            StatusPopoutLeadRow(
                symbol: wifi?.powerOn == true ? "wifi" : "wifi.slash", variableValue: 0, active: false,
                title: wifi == nil ? "No Wi-Fi Interface" : wifi?.powerOn == true ? "Not Connected" : "Wi-Fi Is Off",
                subtitle: wifi?.powerOn == true ? "No Network in Range Connected" : nil
            )
        }
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
            // Display only: switching would only work through private interfaces.
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
        return connected == 0 ? String(localized: "\(pairedText), none connected") : String(localized: "\(pairedText), \(connected) connected")
    }
}

/// A symbol in a circle, the name, below it the battery values (L/R/case with
/// AirPods). Two lines as in the Control Centre: shortened names to the right
/// ("AirPo...") were worse in the image sample than a second line.
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
                // Below 20 % red as in Caelestia (m3error).
                .foregroundStyle(battery.percent < 20 ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
        }
        .font(style.font(size: 11, weight: .medium).monospacedDigit())
        .fixedSize()
    }
}

// MARK: - Battery

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

// MARK: - Building blocks

/// The title line: the name on the left, the switch or the state on the right
/// (Caelestia: a bold heading, below it "Enabled" with a switch - at Apple the
/// switch stands in the title line).
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

/// A big symbol in a circle with two lines - like Apple's network row in the
/// Control Centre. Active: an accent circle.
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

/// A slightly set-off area like the cards of the utilities.
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

/// A button at the bottom across the whole width (Caelestia: "Open settings",
/// IconTextButton in primaryContainer). Slightly tinted instead of full
/// accent: it is a side action.
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
        // Not `onHover`: the window belongs to an app that is never active
        // (see HoverTracker).
        .background(HoverTracker { hovering = $0 })
        .animation(StatusPopoutMotion.fadeOut, value: hovering)
        .help(help ?? title)
        .padding(.top, 2)
    }
}

/// A switch in the macOS 26 look, "on" always in the accent color.
///
/// Why not `.toggleStyle(.switch)`: AppKit draws the switched-on switch grey
/// while the app is not active - and the launcher never becomes active (image
/// sample of the utilities, 14.09.). The measurements as there: track 54 x 24,
/// knob 32 x 20.
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
        .accessibilityValue(on ? "an" : "aus")
    }
}
