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
/// Status popout and edit mode come later: without a popout model in the
/// environment the status capsule's symbols are display only (its model is
/// an optional environment value), so a click does nothing.
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
    /// Distance between the blocks inside one group - tighter than between
    /// groups, so a group reads as one even without a capsule.
    static let moduleSpacing: CGFloat = 4
    /// Room inside a capsule before its first and after its last block.
    static let capsuleInset: CGFloat = 6
    /// How far a lighter capsule on the strip stays off the strip's edges.
    static let distinctInset: CGFloat = 3

    private var axis: BarAxis { edge.isHorizontal ? .horizontal : .vertical }
    private var islands: Bool { bar.style == .islands }

    var body: some View {
        let horizontal = edge.isHorizontal
        // Along the bar: the sidebar's margin at its ends for the strip, the
        // island gap for islands, so they keep the same distance to the
        // screen corners as to the edge.
        let along = islands ? EdgeBarGeometry.islandMargin : style.barPadding(10)
        let margin = islands ? EdgeBarGeometry.islandMargin : 0
        let thickness = CGFloat(bar.thickness)
        ZStack {
            if !islands {
                Color.clear.modifier(BarGlass(shape: Rectangle()))
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
    private func zone(_ zone: BarZone) -> some View {
        let horizontal = edge.isHorizontal
        return axis.stack(spacing: islands || bar.distinctGroups ? 6 : style.barItemSpacing(8)) {
            ForEach(groups(zone)) { group in
                self.group(group)
            }
        }
        .fixedSize(horizontal: horizontal, vertical: !horizontal)
        .frame(maxWidth: horizontal ? .infinity : nil, maxHeight: horizontal ? nil : .infinity,
               alignment: Self.alignment(zone, horizontal: horizontal))
        .clipped()
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
        let shape = RoundedRectangle(cornerRadius: islands ? min(CGFloat(bar.thickness) / 2, 12) : 9,
                                     style: .continuous)
        BarStack(spacing: Self.moduleSpacing, axis: axis) {
            ForEach(group.entries) { entry in
                BarModuleView(entry: entry, context: context)
            }
        }
        .padding(horizontal ? .horizontal : .vertical, capsule ? Self.capsuleInset : 0)
        .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
        .background {
            if islands {
                Color.clear.modifier(BarGlass(shape: shape))
            } else if bar.distinctGroups {
                shape
                    .fill(Color.primary.opacity(0.08))
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
        let placement = EdgeBarZoneLayout.place(
            length: horizontal ? bounds.width : bounds.height,
            start: natural[0], center: natural[1], end: natural[2], gap: gap, notch: horizontal ? notch : nil
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

/// The live bar in its panel: reads the bar and the feature switches from the
/// settings (so a change in Nexus redraws right away) and the notch from its
/// panel.
struct EdgeBarRoot: View {
    let settings: ShellSettingsStore
    let edge: BarEdge
    let state: EdgeBarPanelState
    let context: BarModuleContext

    var body: some View {
        EdgeBarView(bar: settings.settings.edgeBars[edge], edge: edge, notch: state.notch,
                    features: settings.settings.features, context: context)
    }
}

/// What the panel knows and the view needs: the notch changes with the
/// screen (and with "over the menu bar" on or off).
@MainActor
@Observable
final class EdgeBarPanelState {
    var notch: BarNotch?
}
