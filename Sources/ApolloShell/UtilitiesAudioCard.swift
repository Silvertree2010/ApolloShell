import AppKit
import ApolloShellCore
import SwiftUI

/// The sound card in the utilities panel, built like Apple's Control Centre
/// "Sound": a heading with the level, below it the mute button and the slider,
/// below that output and input as two compact menu buttons side by side.
///
/// Why menus instead of lists as with Apple: the height of the card is fixed
/// (`UtilitiesMetrics.audioHeight`) and the panel works with it. A list grows
/// with every pair of AirPods; a menu is always one line high. Why NSMenu instead of a SwiftUI `Menu`: on macOS
/// `Menu` draws its label itself (text and symbol only) - the two-line tile
/// would not work that way.
///
/// The volume as in VolumeMonitor: the virtual main volume of the default
/// output, so that devices without a main control work too.
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

/// The round button left of the slider: the symbol shows the level or mute
/// (the same symbols as the OSD). It stays a neutral grey - the slider next
/// to it already glows in the accent color, and two orange areas would clash.
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
                // Fixed, otherwise a symbol with more waves would shift the slider.
                .frame(width: Self.size, height: Self.size)
        }
        .buttonStyle(UtilitiesTileStyle(shape: .circle, hovered: hovering))
        .disabled(!model.muteSettable)
        .background(HoverTracker { hovering = $0 })
        .help(UtilitiesAudioText.muteHelp(muted: model.outputMuted))
        .accessibilityLabel(UtilitiesAudioText.muteHelp(muted: model.outputMuted))
    }
}

/// A horizontal slider like the OSD, only sideways: the track 10 % foreground,
/// the fill in the accent color, a white knob at the end of the fill. The knob
/// runs inside the track (never half outside), hence the `w - h` arithmetic.
private struct UtilitiesVolumeSlider: View {
    static let height: CGFloat = 24
    /// The step for VoiceOver and the arrow keys: 1/16, like the volume keys.
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
                // The track: with a theme the area of a card, otherwise as before.
                Capsule().fill(style.paintsCard ? AnyShapeStyle(style.card) : AnyShapeStyle(Color.primary.opacity(0.10)))
                // At 0 (or muted) no fill: otherwise an orange ring would be
                // left around the knob (image sample 14.09.), and Apple shows
                // only the empty track at 0 too.
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
            // Dragging and tapping set the volume; the middle of the knob
            // follows the pointer.
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

/// A tile for a device menu: the symbol, above it "Output" in small, below it
/// the device name (one line, cut off), on the right the arrow as with Apple's
/// pop-up menus. A click opens the menu with the current choice under the
/// pointer.
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

/// A neutral area like a switched-off quick toggle (10 % foreground), hover
/// 8 % on top, pressed a little more.
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

/// The pop-up menu of the devices. Built on opening, so that the list is right
/// (AirPods connected, an iPhone nearby).
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
        // Without a view, in screen coordinates: the current choice lies under
        // the pointer, as with a pop-up menu from Apple.
        menu.popUp(positioning: selected, at: NSEvent.mouseLocation, in: nil)
    }
}
