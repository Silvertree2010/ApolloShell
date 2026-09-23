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
///
/// Along a horizontal bar the places run from left to right and the pill
/// glides sideways; sizes and colors stay the same.
///
/// Two more faces (`BarWorkspacesOptions.Style`) for the edge bars, in the
/// same capsule and with the same click per place: `pills` stretches the
/// active dot into a capsule along the bar, `bars` draws a thin line across
/// the bar per desktop, the active one longer. Both mark the active desktop
/// in `--apollo-spaces-active-color` (which follows the accent).
struct SidebarSpaces: View {
    let model: SpacesModel
    var style: BarWorkspacesOptions.Style = .dots
    var onSelect: (Int) -> Void = { _ in }
    @Environment(\.shellStyle) private var shellStyle
    @Environment(\.barAxis) private var axis
    @Environment(\.barControlSize) private var size
    /// Its group draws the capsule already (islands, distinct groups).
    @Environment(\.barGroupCapsule) private var inCapsule

    /// One place: 26 in the 32 pt sidebar, 3 pt of the capsule around it on
    /// each side - and the same margin in a thinner edge bar.
    private var slot: CGFloat { size - 6 }
    private static let gap: CGFloat = 3

    var body: some View {
        if let snapshot = model.snapshot {
            switch style {
            case .dots, .numbers: marker(snapshot)
            case .pills, .bars: face(snapshot)
            }
        }
    }

    /// Dots or numbers under the gliding marker.
    @ViewBuilder
    private func marker(_ snapshot: SpaceSnapshot) -> some View {
        let active = snapshot.activeIndex
        // Where the first place sits: the top, or the left along a
        // horizontal bar - the pill glides from there.
        let start: Alignment = axis == .horizontal ? .leading : .top
        ZStack(alignment: start) {
            dots(count: snapshot.desktops.count, active: active, tint: nil)
            if let active {
                Capsule()
                    .fill(shellStyle.spacesActive)
                    .frame(width: slot, height: slot)
                    .offset(pill(active))
                // Like Caelestia's Colouriser: whatever lies under the
                // pill, in the text color for accent areas. As a mask, so
                // that a dot half covered during the glide is half
                // recolored.
                dots(count: snapshot.desktops.count, active: active, tint: shellStyle.onSpacesActive)
                    .mask(alignment: start) {
                        Capsule()
                            .frame(width: slot, height: slot)
                            .offset(pill(active))
                    }
            }
        }
        // A click area per place, above the dots, the pill and the mask.
        .overlay(alignment: start) {
            axis.stack(spacing: Self.gap) {
                ForEach(0..<snapshot.desktops.count, id: \.self) { index in
                    Color.clear
                        .frame(width: slot, height: slot)
                        .contentShape(.rect)
                        .onTapGesture { onSelect(index) }
                        .help("To Desktop \(index + 1)")
                }
            }
        }
        .padding(axis == .horizontal ? .horizontal : .vertical, Self.gap)
        .frame(width: axis == .horizontal ? nil : size, height: axis == .horizontal ? size : nil)
        .background(Color.primary.opacity(inCapsule ? 0 : 0.08), in: .capsule)
        .animation(SidebarMotion.spatial, value: snapshot)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.help(snapshot))
        .help(Self.help(snapshot))
    }

    /// Pills or bars: every place draws its own mark, so the active one can
    /// take more room along the bar (the pill) - a gliding marker of fixed
    /// size, as for dots, could not.
    private func face(_ snapshot: SpaceSnapshot) -> some View {
        let horizontal = axis == .horizontal
        let pills = style == .pills
        // Pills: a dot a quarter of a place thick, the active one stretched
        // to nearly a place. Bars: 3 points thick, 40 % and 75 % of a place
        // long, across the bar.
        let thin: CGFloat = pills ? max(slot / 4, 5) : 3
        return axis.stack(spacing: Self.gap) {
            ForEach(0..<snapshot.desktops.count, id: \.self) { index in
                let isActive = index == snapshot.activeIndex
                let along: CGFloat = pills ? (isActive ? slot * 0.9 : thin) : thin
                let across: CGFloat = pills ? thin : slot * (isActive ? 0.75 : 0.4)
                Capsule()
                    // The others in the bar's glyph colour, muted like the
                    // dots - plain `.primary` would vanish on a dark themed
                    // bar in the light appearance.
                    .fill(isActive ? AnyShapeStyle(shellStyle.spacesActive) : AnyShapeStyle(shellStyle.barIcon.opacity(0.45)))
                    .frame(width: horizontal ? along : across, height: horizontal ? across : along)
                    // The place: at least a dot's room plus air, and the
                    // full slot across, so a click anywhere near counts.
                    .frame(width: horizontal ? max(along, slot / 2) : slot,
                           height: horizontal ? slot : max(along, slot / 2))
                    .contentShape(.rect)
                    .onTapGesture { onSelect(index) }
                    .help("To Desktop \(index + 1)")
            }
        }
        .padding(horizontal ? .horizontal : .vertical, Self.gap * 2)
        .frame(width: horizontal ? nil : size, height: horizontal ? size : nil)
        .background(inCapsule ? Color.clear : shellStyle.edgeBarGroup, in: .capsule)
        .animation(SidebarMotion.spatial, value: snapshot)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.help(snapshot))
        .help(Self.help(snapshot))
    }

    private func dots(count: Int, active: Int?, tint: Color?) -> some View {
        axis.stack(spacing: Self.gap) {
            ForEach(0..<count, id: \.self) { index in
                let isActive = index == active
                SidebarSpaceDot(active: isActive, slot: slot, number: style == .numbers ? index + 1 : nil)
                    // The inactive ones muted like Caelestia's outlineVariant;
                    // the active one full (visible only while the pill
                    // glides). The digits a little stronger: thin strokes fade
                    // more at 0.4 than a full dot.
                    .foregroundStyle(tint ?? Color.primary.opacity(isActive ? 1 : style == .numbers ? 0.6 : 0.4))
            }
        }
    }

    private func offset(_ index: Int) -> CGFloat {
        CGFloat(index) * (slot + Self.gap)
    }

    /// The pill's shift to place `index`, along the bar.
    private func pill(_ index: Int) -> CGSize {
        axis == .horizontal ? CGSize(width: offset(index), height: 0) : CGSize(width: 0, height: offset(index))
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
///
/// Along a horizontal bar one line "14:05" - hour and minute stacked would
/// only waste the width that bar has plenty of - with the symbol before it
/// and the date after it, smaller, in the same fonts and colors.
///
/// Faces (`BarClockOptions.Style`, resolved for the axis by the caller):
/// `line` and `stacked` as above, whatever the bar - stacked along a
/// horizontal bar puts the symbol beside the two lines, which would not fit
/// above them; `badge` is that layout on a filled shape in the clock colour.
struct SidebarClock: View {
    let model: SidebarClockModel
    var showIcon = true
    var showDate = false
    var style: BarClockOptions.Style = .stacked

    static let tint = Color(nsColor: .systemPurple)

    @Environment(\.shellStyle) private var shellStyle
    @Environment(\.barAxis) private var axis
    @Environment(\.barControlSize) private var size

    /// With a theme, `--apollo-clock-color` or else `--apollo-bar-text-color`
    /// colors the clock (the token follows the other): the fixed purple reads
    /// well on glass, but next to a theme with a bar color of its own it is a
    /// foreign body.
    private var color: Color { shellStyle.color(.clock) ?? Self.tint }

    /// Digits on the badge. White reads on the built-in purple (4:1). On a
    /// theme's clock colour the bar's own backing, cut out of the badge -
    /// a theme's clock colour is chosen to stand out from that backing, so
    /// the pair already contrasts; `readable` covers the rest.
    private var badgeText: Color {
        guard let clock = shellStyle.value(ThemeColorToken.clock) else { return .white }
        let backing = shellStyle.value(ThemeColorToken.bar) ?? ThemeColorToken.bar.defaultValue(dark: shellStyle.dark)
        return Color(ThemeGuards.readable(backing.withAlpha(1), on: clock, minimum: 4.5))
    }

    var body: some View {
        switch style {
        case .line:
            line
        case .stacked:
            if axis == .horizontal { besideStack } else { column }
        case .badge:
            badge
        }
    }

    /// The time on a filled shape in the clock colour: a capsule along a
    /// horizontal bar, a rounded column across a vertical one.
    @ViewBuilder
    private var badge: some View {
        if axis == .horizontal {
            lineText(badgeText)
                .padding(.horizontal, 8)
                .frame(height: size - 8)
                .background(color, in: .capsule)
                .frame(height: size)
                .modifier(ClockDescription(now: model.now))
        } else {
            columnText(badgeText)
                .padding(.vertical, 5)
                .frame(width: size - 4)
                .background(color, in: .rect(cornerRadius: 9, style: .continuous))
                .frame(width: size)
                .modifier(ClockDescription(now: model.now))
        }
    }

    /// Stacked along a horizontal bar: the symbol beside hour over minute,
    /// in a smaller size so both lines fit a 34 pt bar.
    private var besideStack: some View {
        let calendar = Calendar.current
        return HStack(spacing: 5) {
            if showIcon {
                ThemedIcon("bar-clock")
                    .font(shellStyle.font(size: 14, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            VStack(spacing: -3) {
                Text(BarClock.hour(model.now, calendar: calendar))
                Text(BarClock.minute(model.now, calendar: calendar))
            }
            .font(shellStyle.font(size: 11, weight: .semibold))
            if showDate {
                VStack(spacing: -3) {
                    Text(BarClock.weekday(model.now, calendar: calendar))
                    Text(BarClock.day(model.now, calendar: calendar))
                }
                .font(shellStyle.font(size: 10, weight: .semibold))
                .opacity(0.8)
            }
        }
        .monospacedDigit()
        .fixedSize()
        .foregroundStyle(color)
        .frame(height: size)
        .modifier(ClockDescription(now: model.now))
    }

    private var line: some View {
        lineText(color)
            .frame(height: size)
            .modifier(ClockDescription(now: model.now))
    }

    private func lineText(_ tint: Color) -> some View {
        let calendar = Calendar.current
        return HStack(spacing: 5) {
            if showIcon {
                ThemedIcon("bar-clock")
                    .font(shellStyle.font(size: 14, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            Text("\(BarClock.hour(model.now, calendar: calendar)):\(BarClock.minute(model.now, calendar: calendar))")
            if showDate {
                Text("\(BarClock.weekday(model.now, calendar: calendar)) \(BarClock.day(model.now, calendar: calendar))")
                    .font(shellStyle.font(size: 11, weight: .semibold))
                    .opacity(0.8)
            }
        }
        .font(shellStyle.font(size: 13, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(tint)
    }

    private var column: some View {
        columnText(color)
            .frame(width: size)
            .modifier(ClockDescription(now: model.now))
    }

    private func columnText(_ tint: Color) -> some View {
        let calendar = Calendar.current
        return VStack(spacing: 0) {
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
        .foregroundStyle(tint)
    }
}

/// What VoiceOver reads and the tooltip shows, the same for every face.
private struct ClockDescription: ViewModifier {
    let now: Date
    private static let locale = Locale(identifier: "de_CH")

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(now.formatted(.dateTime.hour().minute().locale(Self.locale)))
            .help(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Self.locale)))
    }
}
