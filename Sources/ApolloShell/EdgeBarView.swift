import AppKit
import ApolloShellCore
import SwiftUI

/// One bar along the top, the bottom or the right edge: its three zones
/// (start, centre, end) of groups, each group a row of ordinary bar blocks
/// (`BarModuleView`). The same blocks as in the sidebar; only the axis turns
/// (`\.barAxis`), so a block needs no second implementation.
///
/// Two looks (`BarStyle`):
/// - `.fill`: one strip along the whole panel with the sidebar's background
///   (`BarGlass`), the groups plain on it - or as lighter capsules with
///   `distinctGroups`, so they still read as groups.
/// - `.islands`: no strip; every group is its own piece of that background,
///   `EdgeBarGeometry.islandMargin` away from the screen edge.
///
/// Theme: the blocks inside read the `--apollo-edgebar-*` tokens through
/// `ShellStyle.edgeBarScope`; the strip, islands and capsules here read the
/// edge bar's shape tokens directly. Every default is the look the bars had
/// before those tokens existed.
///
/// A click on a status icon opens its details when the bar's panel puts a
/// popout model into the environment (`EdgeBarRoot`); without one (image
/// samples) the icons are display only - the model is an optional
/// environment value. The edit mode comes later.
struct EdgeBarView: View {
    let bar: EdgeBar
    let edge: BarEdge
    /// The camera housing in panel coordinates. Only a top bar that lies
    /// over the menu bar meets it; everyone else passes `nil`.
    var notch: BarNotch?
    /// A panel switched off in Nexus takes its button along, as in the
    /// sidebar (`SidebarContent.calmBar`).
    let features: ShellSettings.Features
    let context: BarModuleContext

    @Environment(\.shellStyle) private var style

    /// Least distance between two zones.
    static let zoneGap: CGFloat = 8
    /// How far a lighter capsule on the strip stays off the strip's edges.
    static let distinctInset: CGFloat = 3

    /// Distance between the blocks inside one group - tighter than between
    /// groups, so a group reads as one even without a capsule.
    private var moduleSpacing: CGFloat { style.length(.edgeBarItemSpacing) ?? 4 }
    /// Room inside a capsule before its first and after its last block.
    private var capsuleInset: CGFloat { style.length(.edgeBarPadding) ?? 6 }
    /// The island's gap to the screen edge. Capped at the 6 points the
    /// panel and the window guard reserve (`EdgeBarGeometry.islandMargin`),
    /// so a theme can move an island closer but never out of its panel.
    private var islandMargin: CGFloat {
        min(style.length(.edgeBarIslandMargin) ?? EdgeBarGeometry.islandMargin, EdgeBarGeometry.islandMargin)
    }

    private var axis: BarAxis { edge.isHorizontal ? .horizontal : .vertical }
    private var islands: Bool { bar.style == .islands }

    var body: some View {
        let horizontal = edge.isHorizontal
        // Along the bar: the sidebar's margin at its ends for the strip, the
        // island gap for islands, so they keep the same distance to the
        // screen corners as to the edge.
        let along = islands ? islandMargin : style.barPadding(10)
        let margin = islands ? islandMargin : 0
        let thickness = CGFloat(bar.thickness)
        ZStack {
            if !islands {
                Color.clear.modifier(BarGlass(shape: RoundedRectangle(cornerRadius: style.length(.edgeBarRadius) ?? 0,
                                                                     style: .continuous)))
            }
            EdgeBarZones(axis: axis, gap: Self.zoneGap, notch: horizontal ? notch?.shifted(by: along) : nil) {
                zone(.start)
                zone(.center)
                zone(.end)
            }
            .padding(horizontal ? .horizontal : .vertical, along)
            // A strip fills the whole panel across (it may be taller than
            // `thickness` where it covers a thicker menu bar); islands keep
            // their thickness and hug the screen edge.
            .frame(width: horizontal || !islands ? nil : thickness,
                   height: horizontal && islands ? thickness : nil)
            .padding(Self.screenSide(edge), margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.screenAlignment(edge))
        }
        .environment(\.barAxis, axis)
        .environment(\.barControlSize, Self.controlSize(thickness: thickness, capsules: islands || bar.distinctGroups))
        .environment(\.barStatusStyle, bar.statusStyle)
        // Last, so `style` above is still the unscoped one: the redirects
        // are for the blocks, this view reads the edge tokens by name.
        .environment(\.shellStyle, style.edgeBarScope)
    }

    /// The buttons' edge length across the bar: the sidebar's 32 where it
    /// fits, less in a thinner bar so nothing sticks out of it. The margin
    /// keeps a hover highlight inside the strip (2 pt) or inside a group's
    /// capsule, which stands `distinctInset` off the strip's edges.
    static func controlSize(thickness: CGFloat, capsules: Bool) -> CGFloat {
        min(32, thickness - 2 * (capsules ? distinctInset : 2))
    }

    /// The side of the panel that touches the screen edge.
    static func screenSide(_ edge: BarEdge) -> Edge.Set {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .right: .trailing
        }
    }

    private static func screenAlignment(_ edge: BarEdge) -> Alignment {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .right: .trailing
        }
    }

    // MARK: Zones and groups

    /// A zone at its natural length. The zones layout may give it less (a
    /// start zone cut by the notch): then it is clipped at the side away
    /// from its anchor instead of squeezing its blocks.
    ///
    /// A zone with a Dock or a spacer is not pinned to its natural length:
    /// it takes what `EdgeBarZoneLayout` hands it, and `EdgeBarGroupStack`
    /// passes that on to its flexible groups.
    private func zone(_ zone: BarZone) -> some View {
        let horizontal = edge.isHorizontal
        let groups = groups(zone)
        let flexible = groups.reduce(0) { $0 + $1.flexible }
        // Capsules need less room between them than plain groups, which
        // only the gap tells apart.
        let spacing = style.length(.edgeBarGroupSpacing) ?? (islands || bar.distinctGroups ? 6 : style.barItemSpacing(8))
        return EdgeBarGroupStack(axis: axis, spacing: spacing) {
            ForEach(groups) { group in
                self.group(group)
                    .layoutValue(key: EdgeBarFlexCount.self, value: group.flexible)
            }
        }
        .fixedSize(horizontal: horizontal && flexible == 0, vertical: !horizontal && flexible == 0)
        .frame(maxWidth: horizontal ? .infinity : nil, maxHeight: horizontal ? nil : .infinity,
               alignment: Self.alignment(zone, horizontal: horizontal))
        .clipped()
        .layoutValue(key: EdgeBarFlexCount.self, value: flexible)
    }

    private static func alignment(_ zone: BarZone, horizontal: Bool) -> Alignment {
        switch zone {
        case .start: horizontal ? .leading : .top
        case .center: .center
        case .end: horizontal ? .trailing : .bottom
        }
    }

    private struct BlockGroup: Identifiable {
        let entries: [BarEntry]
        var id: BarEntry.ID { entries[0].id }
        /// Dock and spacers in it: they share the zone's spare room.
        var flexible: Int { entries.filter(\.kind.isFlexible).count }
    }

    /// Grouped first, filtered second: a hidden button at the head of a
    /// group must not hand its followers to the group before it.
    private func groups(_ zone: BarZone) -> [BlockGroup] {
        EdgeBar.groups(of: bar[zone]).compactMap { group in
            let shown = group.filter { entry in
                switch entry.module {
                case .dashboardButton: features.dashboard
                case .utilitiesButton: features.utilities
                default: true
                }
            }
            return shown.isEmpty ? nil : BlockGroup(entries: shown)
        }
    }

    @ViewBuilder
    private func group(_ group: BlockGroup) -> some View {
        let horizontal = edge.isHorizontal
        let capsule = islands || bar.distinctGroups
        // An island never rounds past a capsule: more than half the
        // thickness would pinch its ends.
        let radius = islands ? min(CGFloat(bar.thickness) / 2, style.length(.edgeBarIslandRadius) ?? 12)
                             : style.length(.edgeBarGroupRadius) ?? 9
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        BarStack(spacing: moduleSpacing, axis: axis) {
            ForEach(group.entries) { entry in
                BarModuleView(entry: entry, context: context)
            }
        }
        // Status icons and spaces drop their own capsule inside this one.
        .environment(\.barGroupCapsule, capsule)
        .padding(horizontal ? .horizontal : .vertical, capsule ? capsuleInset : 0)
        .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
        .background {
            if islands {
                Color.clear.modifier(BarGlass(shape: shape))
            } else if bar.distinctGroups {
                shape
                    .fill(style.edgeBarGroup)
                    .padding(horizontal ? .vertical : .horizontal, Self.distinctInset)
            }
        }
    }
}

/// Start, centre and end of a bar along its axis; the arithmetic lives in
/// `EdgeBarZoneLayout` (ApolloShellCore) and is tested there. Expects exactly
/// three subviews in that order. Every zone is measured at its natural
/// length and handed the length it got; across the bar it gets the full
/// thickness.
struct EdgeBarZones: Layout {
    var axis: BarAxis
    var gap: CGFloat
    /// Along a horizontal bar only, in this layout's coordinates.
    var notch: BarNotch?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Always the room it is offered: a bar spans its panel.
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let horizontal = axis == .horizontal
        let cross = horizontal ? bounds.height : bounds.width
        let natural = subviews.map { subview -> CGFloat in
            let size = subview.sizeThatFits(horizontal ? ProposedViewSize(width: nil, height: cross)
                                                       : ProposedViewSize(width: cross, height: nil))
            return horizontal ? size.width : size.height
        }
        let flexible = EdgeBarZoneLayout.Flexible(start: subviews[0][EdgeBarFlexCount.self],
                                                  center: subviews[1][EdgeBarFlexCount.self],
                                                  end: subviews[2][EdgeBarFlexCount.self])
        let placement = EdgeBarZoneLayout.place(
            length: horizontal ? bounds.width : bounds.height,
            start: natural[0], center: natural[1], end: natural[2], gap: gap, notch: horizontal ? notch : nil,
            flexible: flexible
        )
        for (subview, span) in zip(subviews, [placement.start, placement.center, placement.end]) {
            let origin = horizontal ? CGPoint(x: bounds.minX + span.origin, y: bounds.minY)
                                    : CGPoint(x: bounds.minX, y: bounds.minY + span.origin)
            subview.place(at: origin, anchor: .topLeading,
                          proposal: horizontal ? ProposedViewSize(width: span.length, height: cross)
                                               : ProposedViewSize(width: cross, height: span.length))
        }
    }
}

/// How many flexible modules (Dock, spacer) a zone or a group holds - read
/// by `EdgeBarZones` and `EdgeBarGroupStack` to hand out the spare room.
struct EdgeBarFlexCount: LayoutValueKey {
    static let defaultValue = 0
}

/// The groups of one zone in a row (or a column in the right bar). Unlike a
/// plain HStack, which splits spare room between every child that accepts it
/// - and a group's `BarStack` accepts any length - only the groups holding a
/// Dock or a spacer grow, by an equal share per flexible module
/// (`EdgeBarZoneLayout.stack`). Measured without a length it is the groups'
/// natural lengths, flexible modules counted as 0.
struct EdgeBarGroupStack: Layout {
    var axis: BarAxis
    var spacing: CGFloat

    private func naturals(_ subviews: Subviews, cross: CGFloat?) -> [CGSize] {
        subviews.map { subview in
            subview.sizeThatFits(axis == .horizontal ? ProposedViewSize(width: nil, height: cross)
                                                     : ProposedViewSize(width: cross, height: nil))
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let horizontal = axis == .horizontal
        let sizes = naturals(subviews, cross: horizontal ? proposal.height : proposal.width)
        let along = sizes.map { horizontal ? $0.width : $0.height }.reduce(0, +)
            + CGFloat(max(subviews.count - 1, 0)) * spacing
        let across = sizes.map { horizontal ? $0.height : $0.width }.max() ?? 0
        let flexible = subviews.contains { $0[EdgeBarFlexCount.self] > 0 }
        let offered = horizontal ? proposal.width : proposal.height
        let length = flexible ? (offered ?? along) : along
        let thickness = (horizontal ? proposal.height : proposal.width) ?? across
        return horizontal ? CGSize(width: length, height: thickness) : CGSize(width: thickness, height: length)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let horizontal = axis == .horizontal
        let cross = horizontal ? bounds.height : bounds.width
        let sizes = naturals(subviews, cross: cross)
        let spans = EdgeBarZoneLayout.stack(
            naturals: sizes.map { horizontal ? $0.width : $0.height },
            weights: subviews.map { $0[EdgeBarFlexCount.self] },
            length: horizontal ? bounds.width : bounds.height, spacing: spacing
        )
        for (subview, span) in zip(subviews, spans) {
            if horizontal {
                subview.place(at: CGPoint(x: bounds.minX + span.origin, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(width: span.length, height: cross))
            } else {
                subview.place(at: CGPoint(x: bounds.midX, y: bounds.minY + span.origin), anchor: .top,
                              proposal: ProposedViewSize(width: cross, height: span.length))
            }
        }
    }
}

/// The live bar in its panel: reads the bar and the feature switches from the
/// settings (so a change in Nexus redraws right away) and the notch from its
/// panel.
struct EdgeBarRoot: View {
    let settings: ShellSettingsStore
    let edge: BarEdge
    let state: EdgeBarPanelState
    let context: BarModuleContext
    /// The status icons open their details through it (`EdgeBarPopout`).
    let popout: StatusPopoutModel

    var body: some View {
        EdgeBarView(bar: settings.settings.edgeBars[edge], edge: edge, notch: state.notch,
                    features: settings.settings.features, context: context)
            .environment(popout)
    }
}

/// What the panel knows and the view needs: the notch changes with the
/// screen (and with "over the menu bar" on or off).
@MainActor
@Observable
final class EdgeBarPanelState {
    var notch: BarNotch?
}
