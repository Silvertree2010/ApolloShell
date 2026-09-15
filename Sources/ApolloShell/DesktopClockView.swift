import SwiftUI

/// Aktuelle Zeit fuer die Schreibtisch-Uhr.
@MainActor
@Observable
final class DesktopClockModel {
    var now = Date()
}

/// Schreibtisch-Uhr wie Caelestia (modules/background/DesktopClock.qml):
/// links Stunde:Minute gross und fett, ein senkrechter Strich, rechts
/// untereinander MONAT / TT / Wochentag. Keine Sekunden. Groessen aus dem
/// Quellcode: Zeit 28 x 3 = 84 pt fett, Doppelpunkt duenner mit 80 %,
/// Monat 16 fett mit Laufweite 4, Tag 28 mittel (2), Wochentag 16 (2).
/// Schatten 70 %. Schrift SF Rounded statt Rubik.
struct DesktopClockView: View {
    let model: DesktopClockModel

    private static let locale = Locale.current

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            HStack(spacing: 0) {
                Text(model.now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).locale(Self.locale))
                Text(":").fontWeight(.regular).opacity(0.8)
                Text(model.now, format: .dateTime.minute(.twoDigits).locale(Self.locale))
            }
            .font(.system(size: 84, weight: .bold, design: .rounded))
            .monospacedDigit()

            Capsule()
                .fill(Color.white.opacity(0.55))
                .frame(width: 3, height: 86)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.now.formatted(.dateTime.month(.wide).locale(Self.locale)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .tracking(4)
                Text(model.now, format: .dateTime.day(.twoDigits).locale(Self.locale))
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .tracking(2)
                Text(model.now.formatted(.dateTime.weekday(.wide).locale(Self.locale)))
                    .font(.system(size: 16))
                    .tracking(2)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.7), radius: 10)
        .fixedSize()
        .padding(24) // Platz fuer den Schatten, sonst wird er abgeschnitten
    }
}
