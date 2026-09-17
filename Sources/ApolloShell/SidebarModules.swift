import AppKit
import ApolloShellCore
import SwiftUI

/// Kurven und Zeiten von Caelestia (plugin/src/Caelestia/Config/tokens.hpp).
enum SidebarMotion {
    /// expressiveDefaultSpatial: 500 ms, schiesst leicht ueber (y1 = 1,21) -
    /// das "Einrasten" des Space-Anzeigers.
    static let spatial = Animation.timingCurve(0.38, 1.21, 0.22, 1, duration: 0.5)
    /// expressiveDefaultEffects: 200 ms, fuer Ueberblenden.
    static let effects = Animation.timingCurve(0.34, 0.8, 0.34, 1, duration: 0.2)
}

// MARK: - Spaces

/// Ein Punkt je Schreibtisch, darueber eine Akzent-Pille, die zum aktiven
/// gleitet (Caelestia: Workspaces, Workspace, ActiveIndicator).
///
/// Masse: Caelestias Leiste ist innen 40 breit, ein Platz 32 (40 - 8), der
/// Abstand 4. Unsere Kapsel ist 32 breit, also alles mal 0,8: Platz 26,
/// Abstand und Rand 3. Punktgroessen wie dort: leer 1/4 des Platzes, aktiv
/// 2/3. Caelestia wuerfelt fuer den aktiven eine Material-Form; hier ein
/// abgerundetes Quadrat, das aus dem Kreis heraus waechst.
///
/// Klick auf einen Punkt wechselt zu diesem Schreibtisch, per ⌃←/⌃→, siehe
/// `SpaceSwitcher`.
///
/// Nexus > Leiste > Spaces: statt Punkten die Nummern der Schreibtische
/// (gleiche Pille, gleiches Umfaerben darunter).
struct SidebarSpaces: View {
    let model: SpacesModel
    var style: BarWorkspacesOptions.Style = .dots
    var onSelect: (Int) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme
    private var shellStyle: ShellStyle { ShellTheme.style(colorScheme) }

    private static let slot: CGFloat = 26
    private static let gap: CGFloat = 3

    var body: some View {
        if let snapshot = model.snapshot {
            let active = snapshot.activeIndex
            ZStack(alignment: .top) {
                dots(count: snapshot.desktops.count, active: active, tint: nil)
                if let active {
                    Capsule()
                        .fill(shellStyle.accent)
                        .frame(width: Self.slot, height: Self.slot)
                        .offset(y: Self.offset(active))
                    // Wie Caelestias Colouriser: was unter der Pille liegt,
                    // in der Schriftfarbe fuer Akzentflaechen. Als Maske,
                    // damit ein halb ueberfahrener Punkt waehrend des
                    // Gleitens halb umgefaerbt ist.
                    dots(count: snapshot.desktops.count, active: active, tint: shellStyle.onAccent)
                        .mask(alignment: .top) {
                            Capsule()
                                .frame(width: Self.slot, height: Self.slot)
                                .offset(y: Self.offset(active))
                        }
                }
            }
            // Klickflaeche je Platz, ueber Punkten, Pille und Maske.
            .overlay(alignment: .top) {
                VStack(spacing: Self.gap) {
                    ForEach(0..<snapshot.desktops.count, id: \.self) { index in
                        Color.clear
                            .frame(width: Self.slot, height: Self.slot)
                            .contentShape(.rect)
                            .onTapGesture { onSelect(index) }
                            .help("Zu Schreibtisch \(index + 1)")
                    }
                }
            }
            .padding(.vertical, Self.gap)
            .frame(width: 32)
            .background(Color.primary.opacity(0.08), in: .capsule)
            .animation(SidebarMotion.spatial, value: snapshot)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.help(snapshot))
            .help(Self.help(snapshot))
        }
    }

    private func dots(count: Int, active: Int?, tint: Color?) -> some View {
        VStack(spacing: Self.gap) {
            ForEach(0..<count, id: \.self) { index in
                let isActive = index == active
                SidebarSpaceDot(active: isActive, slot: Self.slot, number: style == .numbers ? index + 1 : nil)
                    // Inaktive gedaempft wie Caelestias outlineVariant; der
                    // aktive voll (sichtbar nur, solange die Pille gleitet).
                    // Ziffern etwas kraeftiger: duenne Striche verblassen
                    // bei 0,4 staerker als ein voller Punkt.
                    .foregroundStyle(tint ?? Color.primary.opacity(isActive ? 1 : style == .numbers ? 0.6 : 0.4))
            }
        }
    }

    private static func offset(_ index: Int) -> CGFloat {
        CGFloat(index) * (slot + gap)
    }

    private static func help(_ snapshot: SpaceSnapshot) -> String {
        guard let active = snapshot.activeIndex else { return "\(snapshot.desktops.count) Schreibtische" }
        return "Schreibtisch \(active + 1) von \(snapshot.desktops.count)"
    }
}

private struct SidebarSpaceDot: View {
    let active: Bool
    let slot: CGFloat
    /// Gesetzt: Ziffer statt Punkt.
    var number: Int?

    var body: some View {
        if let number {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: slot, height: slot)
        } else {
            let size = active ? slot * 2 / 3 : slot / 4
            // Radius halb so gross wie die Seite = Kreis; so geht die Form beim
            // Wechsel stufenlos vom Punkt ins abgerundete Quadrat ueber.
            RoundedRectangle(cornerRadius: active ? size * 0.3 : size / 2, style: .continuous)
                .frame(width: size, height: size)
                .frame(width: slot, height: slot)
        }
    }
}

// MARK: - Uhr

/// Kalendersymbol, darunter Stunde und Minute eng untereinander, 24 Stunden
/// - Caelestia: Clock mit den Vorgaben (Symbol an, ohne Datum, ohne
/// Sekunden, ohne Hintergrund). Schrift "body small x 1,1" = 13 pt, Ziffern
/// gleich breit, damit die Uhr beim Umspringen nicht wackelt. Die Minute
/// sitzt 4 pt hoeher als ueblich (Caelestia: topMargin -spacing - 4).
///
/// Farbe: Caelestia nimmt die dritte Akzentfarbe (tertiary). Apple kennt
/// keine; systemPurple ist in hellem und dunklem Glas gut lesbar und
/// setzt sich von der Akzentfarbe (Pille, Titel) ab - siehe Bildprobe.
///
/// Nexus > Leiste > Uhr: Symbol weglassen, Datum zeigen (Caelestia: showIcon,
/// showDate - Wochentag kurz und Tag ueber der Uhrzeit, etwas kleiner). Das
/// Datum braucht keinen eigenen Takt: es wechselt zur vollen Minute mit.
struct SidebarClock: View {
    let model: SidebarClockModel
    var showIcon = true
    var showDate = false

    static let tint = Color(nsColor: .systemPurple)
    private static let locale = Locale(identifier: "de_CH")

    @Environment(\.colorScheme) private var colorScheme
    private var shellStyle: ShellStyle { ShellTheme.style(colorScheme) }

    /// Mit Theme faerbt `--apollo-bar-text-color` die Uhr: Das feste Violett
    /// ist auf Glas gut lesbar, neben einem Theme mit eigener Leistenfarbe
    /// aber ein Fremdkoerper.
    private var color: Color { shellStyle.isThemed ? shellStyle.barText : Self.tint }

    var body: some View {
        let calendar = Calendar.current
        VStack(spacing: 0) {
            if showIcon {
                Image(systemName: "calendar")
                    .font(shellStyle.font(size: 14, weight: .semibold))
                    .padding(.bottom, 3)
            }
            if showDate {
                VStack(spacing: -1) {
                    Text(BarClock.weekday(model.now, calendar: calendar))
                    Text(BarClock.day(model.now, calendar: calendar))
                }
                .font(shellStyle.font(size: 11, weight: .semibold))
                .opacity(0.8)
                .padding(.bottom, 4)
            }
            Text(BarClock.hour(model.now, calendar: calendar))
            Text(BarClock.minute(model.now, calendar: calendar))
                .padding(.top, -4)
        }
        .font(shellStyle.font(size: 13, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(color)
        .frame(width: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.now.formatted(.dateTime.hour().minute().locale(Self.locale)))
        .help(model.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Self.locale)))
    }
}
