import AppKit
import ApolloShellCore
import SwiftUI

/// The curves and times out of Caelestia (plugin/src/Caelestia/Config/tokens.hpp).
enum SidebarMotion {
    /// expressiveDefaultSpatial: 500 ms, overshoots slightly (y1 = 1.21) - the
    /// "snap" of the space indicator.
    static let spatial = Animation.shellSpatial
    /// expressiveDefaultEffects: 200 ms, for cross-fading.
    static let effects = Animation.timingCurve(0.34, 0.8, 0.34, 1, duration: 0.2)
}

// MARK: - Spaces

/// One dot per desktop, above it an accent pill that glides to the active one
/// (Caelestia: Workspaces, Workspace, ActiveIndicator).
///
/// The measurements: Caelestia's bar is 40 wide inside, a place 32 (40 - 8),
/// the gap 4. Our capsule is 32 wide, so everything times 0.8: a place 26, the
/// gap and the margin 3. The dot sizes as there: empty 1/4 of the place,
/// active 2/3. Caelestia rolls a Material shape for the active one; here a
/// rounded square that grows out of the circle.
///
/// A click on a dot switches to that desktop, through ⌃←/⌃→, see
/// `SpaceSwitcher`.
///
/// Nexus > Bar > Spaces: the numbers of the desktops instead of dots (the same
/// pill, the same recoloring below it).
struct SidebarSpaces: View {
    let model: SpacesModel
    var style: BarWorkspacesOptions.Style = .dots
    var onSelect: (Int) -> Void = { _ in }
    @Environment(\.shellStyle) private var shellStyle

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
                    // Like Caelestia's Colouriser: whatever lies under the
                    // pill, in the text color for accent areas. As a mask, so
                    // that a dot half covered during the glide is half
                    // recolored.
                    dots(count: snapshot.desktops.count, active: active, tint: shellStyle.onAccent)
                        .mask(alignment: .top) {
                            Capsule()
                                .frame(width: Self.slot, height: Self.slot)
                                .offset(y: Self.offset(active))
                        }
                }
            }
            // A click area per place, above the dots, the pill and the mask.
            .overlay(alignment: .top) {
                VStack(spacing: Self.gap) {
                    ForEach(0..<snapshot.desktops.count, id: \.self) { index in
                        Color.clear
                            .frame(width: Self.slot, height: Self.slot)
                            .contentShape(.rect)
                            .onTapGesture { onSelect(index) }
                            .help("To Desktop \(index + 1)")
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
                    // The inactive ones muted like Caelestia's outlineVariant;
                    // the active one full (visible only while the pill
                    // glides). The digits a little stronger: thin strokes fade
                    // more at 0.4 than a full dot.
                    .foregroundStyle(tint ?? Color.primary.opacity(isActive ? 1 : style == .numbers ? 0.6 : 0.4))
            }
        }
    }

    private static func offset(_ index: Int) -> CGFloat {
        CGFloat(index) * (slot + gap)
    }

    private static func help(_ snapshot: SpaceSnapshot) -> String {
        guard let active = snapshot.activeIndex else { return "\(snapshot.desktops.count) Desktops" }
        return "Desktop \(active + 1) of \(snapshot.desktops.count)"
    }
}

private struct SidebarSpaceDot: View {
    let active: Bool
    let slot: CGFloat
    /// Set: a digit instead of a dot.
    var number: Int?

    var body: some View {
        if let number {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: slot, height: slot)
        } else {
            let size = active ? slot * 2 / 3 : slot / 4
            // A radius half the side = a circle; that way the shape goes over
            // from the dot into the rounded square smoothly on a change.
            RoundedRectangle(cornerRadius: active ? size * 0.3 : size / 2, style: .continuous)
                .frame(width: size, height: size)
                .frame(width: slot, height: slot)
        }
    }
}

// MARK: - Clock

/// A calendar symbol, below it the hour and the minute close together, 24
/// hours - Caelestia: Clock with the defaults (the symbol on, without the
/// date, without seconds, without a background). The font "body small x 1.1" =
/// 13 pt, with digits of equal width, so that the clock does not wobble when
/// it ticks over. The minute sits 4 pt higher than usual (Caelestia:
/// topMargin -spacing - 4).
///
/// The color: Caelestia takes the third accent color (tertiary). Apple knows
/// none; systemPurple reads well in light and dark glass and sets itself apart
/// from the accent color (the pill, the titles) - see the image sample.
///
/// Nexus > Bar > Clock: leave the symbol out, show the date (Caelestia:
/// showIcon, showDate). It changes with the full minute, so no beat of its own.
struct SidebarClock: View {
    let model: SidebarClockModel
    var showIcon = true
    var showDate = false

    static let tint = Color(nsColor: .systemPurple)
    private static let locale = Locale(identifier: "de_CH")

    @Environment(\.shellStyle) private var shellStyle

    /// With a theme, `--apollo-bar-text-color` colors the clock: the fixed
    /// purple reads well on glass, but next to a theme with a bar color of its
    /// own it is a foreign body.
    private var color: Color { shellStyle.color(.barText) ?? Self.tint }

    var body: some View {
        let calendar = Calendar.current
        VStack(spacing: 0) {
            if showIcon {
                ThemedIcon("bar-clock")
                    .font(shellStyle.font(size: 14, weight: .semibold))
                    .frame(width: 16, height: 16)
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
