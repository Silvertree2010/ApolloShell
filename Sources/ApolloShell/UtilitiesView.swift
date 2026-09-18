import ApolloShellCore
import SwiftUI

/// Inhalt des Utilities-Panels (Caelestia: modules/utilities) in Apple-Optik:
/// die Karten aus Nexus > Schnellaktionen untereinander. Vorgabe ist
/// Caelestias Reihenfolge - oben "Wach halten", in der Mitte die Ton-Karte
/// (dort sitzt bei Caelestia die Aufnahme; die macht bei uns Apples Leiste
/// ueber den Bildschirmfoto-Knopf), unten die Schnellschalter.
///
/// Durchsichtig: das Glas darunter liefert der Kantenfenster-Baustein.
/// Breite fest, Hoehe aus der Anordnung (`UtilitiesLayout.panelHeight`) -
/// jede Karte bekommt genau ihre Hoehe aus `UtilitiesMetrics`. Deshalb hat
/// jede Zeile eine feste Hoehe und jeder Text genau eine Zeile: kein Zustand
/// (langer Geraetename, fehlendes Geraet, Wach halten an) darf die Hoehe
/// aendern, sonst stimmte sie nicht mehr mit dem Fenster ueberein.
struct UtilitiesView: View {
    /// Masse aus Caelestia: 430 breit, 16 Rand, 12 zwischen den Karten.
    /// 430 reicht fuer fuenf Knoepfe pro Reihe (je ~68 breit) und zwei
    /// Geraetemenues nebeneinander; breiter wuerde nur leerer.
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
    /// Caelestias Bewegungskurve fuer Knoepfe und Chips: 200 ms, leicht
    /// nachfedernd auslaufend.
    static let toggle = Animation.timingCurve(0.34, 0.8, 0.34, 1, duration: 0.2)
}

/// Feste Hoehe der Karte, die `UtilitiesView` gerade zeichnet. Klassischer
/// Umgebungsschluessel statt `@Entry`: ohne Xcode fehlt das Makro-Plugin.
private struct UtilitiesCardHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var utilitiesCardHeight: CGFloat? {
        get { self[UtilitiesCardHeightKey.self] }
        set { self[UtilitiesCardHeightKey.self] = newValue }
    }
}

/// Karte: leicht abgesetzte Flaeche auf dem Glas, Radius 16 wie Caelestia.
/// Genau so hoch, wie `UtilitiesMetrics` es fuer sie rechnet - die Flaeche
/// fuellt die Hoehe auch, falls der Inhalt einmal knapper ausfiele.
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

/// Symbol-Chip links, zwei Zeilen Text, Schalter rechts (Caelestia:
/// IdleInhibit). Die Uhrzeit steht in der Unterzeile statt in einem eigenen
/// Chip darunter: so bleibt die Karte gleich hoch und das Panel springt nicht.
private struct KeepAwakeCard: View {
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
                    // Jede Minute neu, damit "gestern" nach Mitternacht stimmt.
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

/// Alles ausgeschaltet: statt eines leeren Glases ein Hinweis, wo man es
/// wieder einschaltet. So hoch wie "Wach halten" (eine Zeile mit Chip).
private struct UtilitiesEmptyCard: View {
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
                    Text("Nichts eingeblendet")
                        .font(style.font(size: 14, weight: .medium))
                    Text("Karten und Knöpfe wählt man in Nexus")
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
                .help("Nexus > Schnellaktionen öffnen")
            }
        }
    }
}

/// Schalter im Aussehen des macOS-26-Schalters, aber "an" immer in
/// Akzentfarbe.
///
/// Warum nicht `.toggleStyle(.switch)`: AppKit zeichnet den eingeschalteten
/// Schalter grau, solange die App nicht aktiv ist - und der Launcher wird nie
/// aktiv. Bildprobe 14.09.: grau sogar in einem Fenster, das sich als
/// Schluesselfenster meldet; `controlActiveState` aendert daran nichts.
/// Masse am echten Schalter abgemessen: Bahn 54 x 24, Knopf 32 x 20, Rand 2,
/// Bahn aus etwa 10 % Vordergrund, Knopf im Dunkeln leicht grau.
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
                        // 18 Weg zwischen den Anschlaegen, also +-9 um die Mitte.
                        .offset(x: on ? 9 : -9)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(UtilitiesMotion.toggle, value: on)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(on ? "an" : "aus")
    }
}

/// Ueberschrift und die Knoepfe aus Nexus in Reihen zu fuenf gleich breiten
/// (Caelestia: Toggles, dort ab sieben Eintraegen ebenfalls zweireihig).
/// Vorgabe: oben die Schalter mit Zustand, unten die Aktionen - wie Apples
/// Kontrollzentrum Schalter und Knoepfe trennt.
///
/// Auch ein Schalter ohne Funktion (Night Shift auf einem Bildschirm ohne)
/// bleibt als ausgegrauter Knopf stehen. So aendert sich das Raster nur,
/// wenn man es in Nexus aendert, und die Panelhoehe stimmt.
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
                            // Kurze letzte Reihe: leere Plaetze, damit jede
                            // Spalte so breit bleibt wie in den vollen Reihen.
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

/// Ein Schnellschalter, 48 hoch, Breite geteilt.
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
        // Nicht `onHover`: das Panel gehoert einer nie aktiven App, siehe
        // HoverTracker.
        .background(HoverTracker { hovering = $0 })
        .help(look.help)
        .accessibilityLabel(look.help)
    }
}

/// Was im Knopf steht: SF Symbol, Bluetooth-Rune oder App-Symbol. Auch
/// Nexus zeichnet damit Raster und Galerie - so sieht man dort genau den
/// Knopf, der im Panel erscheint.
struct UtilitiesToggleGlyph: View {
    let icon: UtilitiesToggleItem.Icon
    var scale: CGFloat = 1

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 17 * scale, weight: .semibold))
        case .bluetooth:
            // Kein SF Symbol fuer Bluetooth, siehe BluetoothRune.
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

/// Caelestias IconButton in Apple-Farben: aus eine runde, dezente Flaeche mit
/// grauem Symbol; an ein Rechteck mit Radius 12 in Akzentfarbe, Symbol
/// weiss (auf Gelb dunkel, siehe `Color.onAccent`); gedrueckt Radius 8. Form und Farbe gleiten in 200 ms.
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
            // Hover-Schimmer: 8 % obendrauf, wie Caelestias StateLayer.
            .overlay(Color.primary.opacity(hovered && isEnabled ? 0.08 : 0), in: .rect(cornerRadius: radius))
            .contentShape(.rect(cornerRadius: radius))
            .opacity(isEnabled ? 1 : 0.4)
            .animation(UtilitiesMotion.toggle, value: radius)
            .animation(UtilitiesMotion.toggle, value: active)
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
