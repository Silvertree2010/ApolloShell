import SwiftUI

/// Current time for the desktop clock.
@MainActor
@Observable
final class DesktopClockModel {
    var now = Date()
}

/// Desktop clock like Caelestia (modules/background/DesktopClock.qml): on
/// the left hour:minute large and bold, a vertical bar, on the right,
/// stacked, MONTH / DD / weekday. No seconds. Sizes from the source:
/// time 28 x 3 = 84 pt bold, colon thinner at 80%, month 16 bold with
/// tracking 4, day 28 medium (2), weekday 16 (2). Shadow 70%. Font SF
/// Rounded instead of Rubik.
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
        .padding(24) // Room for the shadow, otherwise it gets clipped
    }
}
