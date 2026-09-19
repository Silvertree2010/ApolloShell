import AppKit
import ApolloShellCore
import SwiftUI

/// Ton-Karte im Utilities-Panel, gebaut wie Apples Kontrollzentrum "Ton":
/// Ueberschrift mit Pegel, darunter Stumm-Knopf und Regler, darunter
/// Ausgabe und Eingang als zwei kompakte Menue-Knoepfe nebeneinander.
///
/// Warum Menues statt Listen wie bei Apple: die Hoehe der Karte steht fest
/// (`UtilitiesMetrics.audioHeight`), das Panel rechnet damit. Eine Liste
/// waechst mit jedem AirPods-Paar; ein Menue ist immer eine Zeile hoch. Warum NSMenu statt SwiftUI-`Menu`: auf macOS
/// zeichnet `Menu` seine Beschriftung selbst (nur Text und Symbol) - die
/// zweizeilige Kachel ginge damit nicht.
///
/// Lautstaerke wie VolumeMonitor: virtuelle Hauptlautstaerke des
/// Standardausgangs, damit auch Geraete ohne Hauptregler gehen.
struct UtilitiesAudioCard: View {
    let model: UtilitiesModel
    @Environment(\.shellStyle) private var style

    var body: some View {
        UtilitiesCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(UtilitiesAudioText.title)
                        .font(style.font(size: 14, weight: .medium))
                    Spacer(minLength: 8)
                    Text(UtilitiesAudioText.level(volume: model.volume, muted: model.outputMuted))
                        .font(style.font(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .lineLimit(1)

                HStack(spacing: 10) {
                    UtilitiesMuteButton(model: model)
                    UtilitiesVolumeSlider(model: model)
                }

                HStack(spacing: 8) {
                    UtilitiesDeviceButton(
                        symbol: "speaker.wave.2.fill", caption: UtilitiesAudioText.output, name: model.outputLabel,
                        devices: model.outputs, current: model.defaultOutput
                    ) { model.selectDevice($0, scope: .output) }
                    UtilitiesDeviceButton(
                        symbol: "mic.fill", caption: UtilitiesAudioText.input, name: model.inputLabel,
                        devices: model.inputs, current: model.defaultInput
                    ) { model.selectDevice($0, scope: .input) }
                }
            }
        }
    }
}

/// Runder Knopf links vom Regler: Symbol zeigt Stufe bzw. Stumm (dieselben
/// Symbole wie das OSD). Bleibt neutral grau - der Regler daneben leuchtet
/// schon in Akzentfarbe, zwei orange Flaechen nebeneinander waeren zu laut.
private struct UtilitiesMuteButton: View {
    static let size: CGFloat = 32

    let model: UtilitiesModel
    @State private var hovering = false
    @Environment(\.shellStyle) private var style

    var body: some View {
        Button(action: model.toggleOutputMute) {
            ThemedIcon(model.outputMuted ? "status-volume-muted" : "status-volume",
                       fallback: VolumeGlyphs.symbol(volume: model.volume, muted: model.outputMuted))
                .frame(width: 16, height: 16)
                .font(style.font(size: 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                // Fest, sonst verschoebe ein Symbol mit mehr Wellen den Regler.
                .frame(width: Self.size, height: Self.size)
        }
        .buttonStyle(UtilitiesTileStyle(shape: .circle, hovered: hovering))
        .disabled(!model.muteSettable)
        .background(HoverTracker { hovering = $0 })
        .help(UtilitiesAudioText.muteHelp(muted: model.outputMuted))
        .accessibilityLabel(UtilitiesAudioText.muteHelp(muted: model.outputMuted))
    }
}

/// Waagrechter Regler wie das OSD, nur quer: Bahn 10 % Vordergrund, Fuellung
/// in Akzentfarbe, weisser Knopf am Ende der Fuellung. Der Knopf laeuft
/// innerhalb der Bahn (nie halb draussen), deshalb die Rechnung mit `w - h`.
private struct UtilitiesVolumeSlider: View {
    static let height: CGFloat = 24
    /// Schritt fuer VoiceOver und Pfeiltasten: 1/16 wie die Lautstaerketasten.
    private static let step: Float = 1.0 / 16

    let model: UtilitiesModel
    @Environment(\.shellStyle) private var style

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let value = model.outputMuted ? 0 : CGFloat(min(max(model.volume, 0), 1))
            let fill = h + value * (w - h)

            ZStack(alignment: .leading) {
                // Bahn: mit Theme die Flaeche einer Karte, sonst wie bisher.
                Capsule().fill(style.paintsCard ? AnyShapeStyle(style.card) : AnyShapeStyle(Color.primary.opacity(0.10)))
                // Bei 0 (oder stumm) keine Fuellung: sonst bliebe ein oranger
                // Ring um den Knopf stehen (Bildprobe 14.09.), und Apple zeigt
                // bei 0 auch nur die leere Bahn.
                Capsule()
                    .fill(style.accentFill)
                    .frame(width: fill)
                    .opacity(value > 0 ? 1 : 0)
                Circle()
                    .fill(style.themeOnAccent ?? Color.white)
                    .shadow(color: .black.opacity(style.shadowOpacity(0.25)), radius: 1.5, y: 0.5)
                    .frame(width: h - 4, height: h - 4)
                    .offset(x: fill - h + 2)
            }
            .contentShape(.capsule)
            // Ziehen und Tippen setzen die Lautstaerke; die Mitte des Knopfs
            // folgt dem Zeiger.
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let position = (drag.location.x - h / 2) / max(w - h, 1)
                model.setVolume(Float(min(max(position, 0), 1)))
            })
        }
        .frame(height: Self.height)
        .opacity(model.volumeSettable ? 1 : 0.4)
        .allowsHitTesting(model.volumeSettable)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue(UtilitiesAudioText.level(volume: model.volume, muted: model.outputMuted))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.setVolume(model.volume + Self.step)
            case .decrement: model.setVolume(model.volume - Self.step)
            @unknown default: break
            }
        }
    }
}

/// Kachel fuer ein Geraetemenue: Symbol, darueber klein "Ausgabe", darunter
/// der Geraetename (eine Zeile, abgeschnitten), rechts der Pfeil wie bei
/// Apples Aufklappmenues. Klick oeffnet das Menue mit der aktuellen Wahl
/// unter dem Zeiger.
private struct UtilitiesDeviceButton: View {
    static let height: CGFloat = 44

    let symbol: String
    let caption: String
    let name: String
    let devices: [UtilitiesAudioDevice]
    let current: UInt32?
    let select: (UInt32) -> Void
    @State private var hovering = false
    @Environment(\.shellStyle) private var style

    var body: some View {
        Button {
            UtilitiesDeviceMenu.show(devices: devices, current: current, select: select)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(style.font(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(caption)
                        .font(style.font(size: 11))
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(style.font(size: 12, weight: .medium))
                        .truncationMode(.tail)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(style.font(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.height)
        }
        .buttonStyle(UtilitiesTileStyle(shape: .rect(cornerRadius: style.controlRadius(12)), hovered: hovering))
        .background(HoverTracker { hovering = $0 })
        .help("\(caption): \(name)")
        .accessibilityLabel("\(caption): \(name)")
    }
}

/// Neutrale Flaeche wie ein ausgeschalteter Schnellschalter (10 %
/// Vordergrund), Hover 8 % obendrauf, gedrueckt noch etwas mehr.
private struct UtilitiesTileStyle<S: Shape>: ButtonStyle {
    let shape: S
    let hovered: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let layer = configuration.isPressed ? 0.14 : (hovered && isEnabled ? 0.08 : 0)
        configuration.label
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(0.10), in: shape)
            .overlay(Color.primary.opacity(layer), in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: layer)
    }
}

/// Das Aufklappmenue der Geraete. Beim Oeffnen gebaut, damit die Liste
/// stimmt (AirPods verbunden, iPhone in der Naehe).
@MainActor
enum UtilitiesDeviceMenu {
    static func show(devices: [UtilitiesAudioDevice], current: UInt32?, select: @escaping (UInt32) -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        var selected: NSMenuItem?
        for device in devices {
            let id = device.id
            let item = ClosureMenuItem(UtilitiesAudioDevices.displayName(device.name)) { select(id) }
            if id == current {
                item.state = .on
                selected = item
            }
            menu.addItem(item)
        }
        if devices.isEmpty {
            let empty = NSMenuItem(title: UtilitiesAudioText.noDevicesInMenu, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        // Ohne Ansicht in Bildschirmkoordinaten: die aktuelle Wahl liegt
        // unter dem Zeiger, wie bei einem Aufklappmenue von Apple.
        menu.popUp(positioning: selected, at: NSEvent.mouseLocation, in: nil)
    }
}
