import ApolloShellCore
import SwiftUI

/// The content of the utilities panel (Caelestia: modules/utilities) in an
/// Apple look: the cards of the control centre below each other. The
/// default is Caelestia's order - "Keep Awake" at the top, the sound card in
/// the middle (where Caelestia has the recording; ours is done by Apple's bar
/// through the screenshot button), the quick toggles at the bottom.
///
/// Transparent: the glass below it comes from the edge-window block. The
/// width is fixed, the height comes out of the arrangement
/// (`UtilitiesLayout.panelHeight`) - every card gets exactly its height out of
/// `UtilitiesMetrics`. That is why every row has a fixed height and every text
/// exactly one line: no state (a long device name, a missing device, Keep
/// Awake on) may change the height, otherwise it no longer matches the window.
struct UtilitiesView: View {
    /// The measurements out of Caelestia: 430 wide, 16 margin, 12 between the
    /// cards. 430 is enough for five buttons per row (about 68 wide each) and
    /// two device menus side by side; wider would only be emptier.
    static let width = CGFloat(UtilitiesMetrics.width)
    static let padding = CGFloat(UtilitiesMetrics.padding)
    static let spacing = CGFloat(UtilitiesMetrics.spacing)

    @Bindable var model: UtilitiesModel
    let layout: UtilitiesLayout

    var body: some View {
        let rows = layout.toggleRows
        let cards = layout.visibleCards
        VStack(spacing: Self.spacing) {
            if cards.isEmpty {
                UtilitiesEmptyCard(model: model)
                    .environment(\.utilitiesCardHeight, CGFloat(UtilitiesMetrics.emptyCardHeight))
            }
            ForEach(cards) { kind in
                card(kind, rows: rows)
                    .environment(\.utilitiesCardHeight, CGFloat(UtilitiesMetrics.cardHeight(kind, toggleRows: rows.count)))
            }
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func card(_ kind: UtilitiesCardKind, rows: [[UtilitiesToggleEntry]]) -> some View {
        switch kind {
        case .keepAwake: KeepAwakeCard(model: model)
        case .audio: UtilitiesAudioCard(model: model)
        case .quickToggles: QuickTogglesCard(model: model, rows: rows)
        }
    }
}

enum UtilitiesMotion {
    /// Caelestia's motion curve for buttons and chips: 200 ms, coming to rest
    /// with a slight bounce.
    static let toggle = Animation.timingCurve(0.34, 0.8, 0.34, 1, duration: 0.2)
}

/// The fixed height of the card `UtilitiesView` is drawing right now. A
/// classic environment key instead of `@Entry`: the macro plugin is missing.
private struct UtilitiesCardHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var utilitiesCardHeight: CGFloat? {
        get { self[UtilitiesCardHeightKey.self] }
        set { self[UtilitiesCardHeightKey.self] = newValue }
    }
}

/// A card: a slightly set-off area on the glass, radius 16 as in Caelestia.
/// Exactly as high as `UtilitiesMetrics` works out for it - the area fills
/// the height even if the content turned out shorter one day.
struct UtilitiesCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.utilitiesCardHeight) private var height

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .cardSurface(radius: 16)
    }
}

/// A symbol chip on the left, two lines of text, a switch on the right
/// (Caelestia: IdleInhibit). The time stands in the lower line instead of in a
/// chip of its own below: that way the card stays the same height and the
/// panel does not jump. Not `private`: `UtilitiesEditOverlay.swift` shows the
/// same card while editing, only with the controls switched off.
struct KeepAwakeCard: View {
    @Bindable var model: UtilitiesModel
    @Environment(\.shellStyle) private var style

    var body: some View {
        UtilitiesCard {
            HStack(spacing: 12) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(style.font(size: 16, weight: .medium))
                    .foregroundStyle(model.keepAwake ? AnyShapeStyle(style.onAccent) : AnyShapeStyle(.secondary))
                    .frame(width: 40, height: 40)
                    .background(
                        model.keepAwake ? AnyShapeStyle(style.accent) : AnyShapeStyle(Color.primary.opacity(0.10)),
                        in: .circle
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(KeepAwakeText.title)
                        .font(style.font(size: 14, weight: .medium))
                    // Anew every minute, so that "yesterday" is right after midnight.
                    TimelineView(.everyMinute) { context in
                        Text(KeepAwakeText.subtitle(since: model.keepAwakeSince, now: context.date, lid: model.lid))
                            .font(style.font(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)

                Spacer(minLength: 8)

                Toggle(KeepAwakeText.title, isOn: $model.keepAwake)
                    .toggleStyle(AccentSwitchStyle())
                    .accessibilityLabel(KeepAwakeText.title)
            }
            .animation(UtilitiesMotion.toggle, value: model.keepAwake)
        }
    }
}

/// Everything switched off: instead of empty glass, a note on where to switch
/// it on again. As high as "Keep Awake" (one line with a chip). Not
/// `private`: shown while editing without cards as well
/// (`UtilitiesEditOverlay.swift`).
struct UtilitiesEmptyCard: View {
    let model: UtilitiesModel
    @State private var hovering = false
    @Environment(\.shellStyle) private var style

    var body: some View {
        UtilitiesCard {
            HStack(spacing: 12) {
                Image(systemName: "square.dashed")
                    .font(style.font(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color.primary.opacity(0.10), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing Shown")
                        .font(style.font(size: 14, weight: .medium))
                    Text("Cards and buttons are chosen under Edit Interface")
                        .font(style.font(size: 12))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: model.openSettings) {
                    Text("Nexus")
                        .font(style.font(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Color.primary.opacity(hovering ? 0.18 : 0.10), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .background(HoverTracker { hovering = $0 })
                .help("Open the Nexus Menu")
            }
        }
    }
}

/// A switch in the look of the macOS 26 switch, but "on" always in the accent
/// color.
///
/// Why not `.toggleStyle(.switch)`: AppKit draws the switched-on switch grey
/// while the app is not active - and the launcher never becomes active. Image
/// sample 14.09.: grey even in a window that reports itself as the key window;
/// `controlActiveState` changes nothing about it. The measurements were taken
/// off the real switch: track 54 x 24, knob 32 x 20, margin 2, the track out
/// of about 10 % foreground, the knob slightly grey in the dark.
private struct AccentSwitchStyle: ToggleStyle {
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
                        // 18 of travel between the stops, so +-9 around the middle.
                        .offset(x: on ? 9 : -9)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(UtilitiesMotion.toggle, value: on)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(on ? "on" : "off")
    }
}

/// A heading and the buttons out of Nexus in rows of five equally wide ones
/// (Caelestia: Toggles, which also goes to two rows from seven entries on).
/// The default: the switches with a state at the top, the actions at the
/// bottom - the way Apple's Control Centre separates switches and buttons.
///
/// A switch without a function (Night Shift on a screen without it) stays
/// standing as a greyed-out button too. That way the grid only changes when
/// one changes it in Nexus, and the panel height is right.
private struct QuickTogglesCard: View {
    let model: UtilitiesModel
    let rows: [[UtilitiesToggleEntry]]
    @Environment(\.shellStyle) private var style

    var body: some View {
        UtilitiesCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(UtilitiesToggleText.cardTitle)
                    .font(style.font(size: 14, weight: .medium))
                    .lineLimit(1)
                VStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 8) {
                            ForEach(row) { entry in
                                let item = UtilitiesToggleItem(entry: entry, model: model)
                                QuickToggleButton(icon: item.icon, look: item.look, action: item.action)
                            }
                            // A short last row: empty places, so that every
                            // column stays as wide as in the full rows.
                            ForEach(row.count..<QuickToggles.columns, id: \.self) { _ in
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: QuickToggleButton.height)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One quick toggle, 48 high, the width shared.
struct QuickToggleButton: View {
    static let height: CGFloat = 48

    let icon: UtilitiesToggleItem.Icon
    let look: QuickToggleLook
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            UtilitiesToggleGlyph(icon: icon)
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
        }
        .buttonStyle(QuickToggleStyle(active: look.active, hovered: hovering))
        .disabled(!look.enabled)
        // Not `onHover`: the panel belongs to an app that is never active, see
        // HoverTracker.
        .background(HoverTracker { hovering = $0 })
        .help(look.help)
        .accessibilityLabel(look.help)
    }
}

/// What stands in the button: an SF Symbol, the Bluetooth rune or an app
/// symbol. Nexus draws the grid and the gallery with it too - so one sees
/// exactly the button that appears in the panel.
struct UtilitiesToggleGlyph: View {
    let icon: UtilitiesToggleItem.Icon
    var scale: CGFloat = 1

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 17 * scale, weight: .semibold))
        case .bluetooth:
            // No SF Symbol for Bluetooth, see BluetoothRune.
            BluetoothRune()
                .stroke(style: StrokeStyle(lineWidth: 1.9 * scale, lineCap: .round, lineJoin: .round))
                .frame(width: 11 * scale, height: 17 * scale)
        case .app(let bundleID):
            if let info = BarApps.info(for: bundleID) {
                Image(nsImage: info.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 28 * scale, height: 28 * scale)
            } else {
                Image(systemName: UtilitiesAppOptions.fallbackSymbol)
                    .font(.system(size: 17 * scale, weight: .semibold))
            }
        }
    }
}

/// Caelestia's IconButton in Apple colors: off is a round, quiet area with a
/// grey symbol; on is a rectangle with radius 12 in the accent color, the
/// symbol white (dark on yellow, see `Color.onAccent`); pressed radius 8. Shape and color glide in 200 ms.
private struct QuickToggleStyle: ButtonStyle {
    let active: Bool
    let hovered: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.shellStyle) private var style

    func makeBody(configuration: Configuration) -> some View {
        let radius = QuickToggles.cornerRadius(
            active: active, pressed: configuration.isPressed, height: QuickToggleButton.height
        )
        configuration.label
            .foregroundStyle(active ? AnyShapeStyle(style.onAccent) : AnyShapeStyle(.secondary))
            .background(
                active ? AnyShapeStyle(style.accent) : AnyShapeStyle(Color.primary.opacity(0.10)),
                in: .rect(cornerRadius: radius)
            )
            // The hover shimmer: 8 % on top, like Caelestia's StateLayer.
            .overlay(Color.primary.opacity(hovered && isEnabled ? 0.08 : 0), in: .rect(cornerRadius: radius))
            .contentShape(.rect(cornerRadius: radius))
            .opacity(isEnabled ? 1 : 0.4)
            .animation(UtilitiesMotion.toggle, value: radius)
            .animation(UtilitiesMotion.toggle, value: active)
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
