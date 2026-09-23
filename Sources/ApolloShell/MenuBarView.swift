import AppKit
import ApolloShellCore
import SwiftUI

/// The menu bar across the top of the screen: its three zones (start,
/// centre, end) of groups, each group a row of ordinary bar blocks
/// (`BarModuleView`). The same blocks as in the sidebar; only the axis turns
/// (`\.barAxis`), so a block needs no second implementation.
///
/// Two looks (`BarStyle`):
/// - `.fill`: one strip along the whole panel with the sidebar's background
///   (`BarGlass`), the groups plain on it - or as lighter capsules with
///   `distinctGroups`, so they still read as groups.
/// - `.islands`: no strip; every group is its own piece of that background,
///   `MenuBarGeometry.islandMargin` below the top edge of the screen.
///
/// Theme: the blocks inside read the `--apollo-menubar-*` tokens through
/// `ShellStyle.menuBarScope`; the strip, islands and capsules here read the
/// menu bar's shape tokens directly. Every default is the look the bar had
/// before those tokens existed.
///
/// A click on a status icon opens its details when the bar's panel puts a
/// popout model into the environment (`MenuBarRoot`); without one (image
/// samples) the icons are display only - the model is an optional
/// environment value.
///
/// While the global edit mode runs (`editor`), the blocks are the sidebar's
/// edit blocks (`EditableBarBlock`: wobble, minus badge, selection, options
/// popover), every zone takes drops, and an empty zone shows a target -
/// otherwise it would measure 0 and nothing could be dropped into it.
struct MenuBarView: View {
    let bar: ApolloMenuBar
    /// The camera housing in panel coordinates. Only a bar that lies over
    /// Apple's menu bar meets it; below it the bar passes `nil`.
    var notch: BarNotch?
    /// A panel switched off in Nexus takes its button along, as in the
    /// sidebar (`SidebarContent.calmBar`).
    let features: ShellSettings.Features
    let context: BarModuleContext
    /// The global edit mode; `nil` in image samples of the calm bar.
    var editor: ShellEditor?

    @Environment(\.shellStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dashboardReducesMotionOverride) private var reduceMotionOverride
    @Environment(\.dashboardRendersForScreenshot) private var rendersForScreenshot

    /// The editor while it edits; the calm bar otherwise.
    private var editing: ShellEditor? {
        guard let editor, editor.isEditing, editor.bar != nil else { return nil }
        return editor
    }

    /// Least distance between two zones.
    static let zoneGap: CGFloat = 8
    /// How far a lighter capsule on the strip stays off the strip's edges.
    static let distinctInset: CGFloat = 3

    /// Distance between the blocks inside one group - tighter than between
    /// groups, so a group reads as one even without a capsule.
    private var moduleSpacing: CGFloat { style.length(.menuBarItemSpacing) ?? 4 }
    /// Room inside a capsule before its first and after its last block.
    private var capsuleInset: CGFloat { style.length(.menuBarPadding) ?? 6 }
    /// The island's gap to the screen edge. Capped at the 6 points the
    /// panel and the window guard reserve (`MenuBarGeometry.islandMargin`),
    /// so a theme can move an island closer but never out of its panel.
    private var islandMargin: CGFloat {
        min(style.length(.menuBarIslandMargin) ?? MenuBarGeometry.islandMargin, MenuBarGeometry.islandMargin)
    }

    private var islands: Bool { bar.style == .islands }

    var body: some View {
        // Along the bar: the sidebar's margin at its ends for the strip, the
        // island gap for islands, so they keep the same distance to the
        // screen corners as to the edge.
        let along = islands ? islandMargin : style.barPadding(10)
        let margin = islands ? islandMargin : 0
        let thickness = CGFloat(bar.thickness)
        ZStack {
            if !islands {
                Color.clear.modifier(BarGlass(shape: RoundedRectangle(cornerRadius: style.length(.menuBarRadius) ?? 0,
                                                                     style: .continuous)))
            }
            MenuBarZones(gap: Self.zoneGap, notch: notch?.shifted(by: along)) {
                zone(.start)
                zone(.center)
                zone(.end)
            }
            .padding(.horizontal, along)
            // A strip fills the whole panel's height (it may be taller than
            // `thickness` where it covers a thicker Apple menu bar); islands
            // keep their thickness and hug the top edge.
            .frame(height: islands ? thickness : nil)
            .padding(.top, margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .environment(\.barAxis, .horizontal)
        .environment(\.barControlSize, Self.controlSize(thickness: thickness, capsules: islands || bar.distinctGroups))
        .environment(\.barStatusStyle, bar.statusStyle)
        // Last, so `style` above is still the unscoped one: the redirects
        // are for the blocks, this view reads the menu bar tokens by name.
        .environment(\.shellStyle, style.menuBarScope)
    }

    /// The buttons' edge length across the bar: the sidebar's 32 where it
    /// fits, less in a thinner bar so nothing sticks out of it. The margin
    /// keeps a hover highlight inside the strip (2 pt) or inside a group's
    /// capsule, which stands `distinctInset` off the strip's edges.
    static func controlSize(thickness: CGFloat, capsules: Bool) -> CGFloat {
        min(32, thickness - 2 * (capsules ? distinctInset : 2))
    }

    // MARK: Zones and groups

    /// A zone at its natural length. The zones layout may give it less (a
    /// start zone cut by the notch): then it is clipped at the side away
    /// from its anchor instead of squeezing its blocks.
    ///
    /// A zone with a Dock or a spacer is not pinned to its natural length:
    /// it takes what `MenuBarZoneLayout` hands it, and `MenuBarGroupStack`
    /// passes that on to its flexible groups.
    private func zone(_ zone: BarZone) -> some View {
        let groups = groups(zone)
        let flexible = groups.reduce(0) { $0 + $1.flexible }
        // Capsules need less room between them than plain groups, which
        // only the gap tells apart.
        let spacing = style.length(.menuBarGroupSpacing) ?? (islands || bar.distinctGroups ? 6 : style.barItemSpacing(8))
        return MenuBarGroupStack(spacing: spacing) {
            ForEach(groups) { group in
                self.group(group, zone: zone)
                    .layoutValue(key: MenuBarFlexCount.self, value: group.flexible)
            }
            if let editing, groups.isEmpty {
                MenuBarEmptyZone(editor: editing, place: .menuBar(zone),
                                 thickness: Self.controlSize(thickness: CGFloat(bar.thickness), capsules: false))
            }
        }
        .fixedSize(horizontal: flexible == 0, vertical: false)
        .frame(maxWidth: .infinity, alignment: Self.alignment(zone))
        .modifier(MenuBarZoneDrop(editor: editing, place: .menuBar(zone), active: !rendersForScreenshot))
        .clipped()
        .layoutValue(key: MenuBarFlexCount.self, value: flexible)
    }

    private static func alignment(_ zone: BarZone) -> Alignment {
        switch zone {
        case .start: .leading
        case .center: .center
        case .end: .trailing
        }
    }

    private struct BlockGroup: Identifiable {
        let entries: [BarEntry]
        var id: BarEntry.ID { entries[0].id }
        /// Dock, spacers and the app menu in it: they share the zone's
        /// spare room.
        var flexible: Int { entries.filter(\.kind.growsAlongMenuBar).count }
    }

    /// Grouped first, filtered second: a hidden button at the head of a
    /// group must not hand its followers to the group before it. While
    /// editing nothing is hidden - a block one cannot see cannot be removed.
    private func groups(_ zone: BarZone) -> [BlockGroup] {
        ApolloMenuBar.groups(of: bar[zone]).compactMap { group in
            let shown = editing != nil ? group : group.filter { entry in
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
    private func group(_ group: BlockGroup, zone: BarZone) -> some View {
        let capsule = islands || bar.distinctGroups
        // An island never rounds past a capsule: more than half the
        // thickness would pinch its ends.
        let radius = islands ? min(CGFloat(bar.thickness) / 2, style.length(.menuBarIslandRadius) ?? 12)
                             : style.length(.menuBarGroupRadius) ?? 9
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        BarStack(spacing: moduleSpacing, axis: .horizontal) {
            ForEach(group.entries) { entry in
                if let editing {
                    EditableBarBlock(editor: editing, entry: entry, ref: BarEntryRef(place: .menuBar(zone), id: entry.id),
                                     context: context, reduceMotion: reduceMotionOverride ?? systemReduceMotion,
                                     dragging: !rendersForScreenshot, inMenuBar: true)
                        .layoutValue(key: BarFlexible.self, value: entry.kind.growsAlongMenuBar)
                } else {
                    BarModuleView(entry: entry, context: context)
                }
            }
        }
        // Status icons and spaces drop their own capsule inside this one.
        .environment(\.barGroupCapsule, capsule)
        .padding(.horizontal, capsule ? capsuleInset : 0)
        .frame(maxHeight: .infinity)
        .background {
            if islands {
                Color.clear.modifier(BarGlass(shape: shape))
            } else if bar.distinctGroups {
                shape
                    .fill(style.menuBarGroup)
                    .padding(.vertical, Self.distinctInset)
            }
        }
    }
}

/// Start, centre and end of the menu bar from left to right; the arithmetic
/// lives in `MenuBarZoneLayout` (ApolloShellCore) and is tested there.
/// Expects exactly three subviews in that order. Every zone is measured at
/// its natural width and handed the width it got; it gets the bar's full
/// height.
struct MenuBarZones: Layout {
    var gap: CGFloat
    /// In this layout's coordinates.
    var notch: BarNotch?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Always the room it is offered: the bar spans its panel.
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let natural = subviews.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: bounds.height)).width }
        let flexible = MenuBarZoneLayout.Flexible(start: subviews[0][MenuBarFlexCount.self],
                                                  center: subviews[1][MenuBarFlexCount.self],
                                                  end: subviews[2][MenuBarFlexCount.self])
        let placement = MenuBarZoneLayout.place(
            length: bounds.width, start: natural[0], center: natural[1], end: natural[2], gap: gap, notch: notch,
            flexible: flexible
        )
        for (subview, span) in zip(subviews, [placement.start, placement.center, placement.end]) {
            subview.place(at: CGPoint(x: bounds.minX + span.origin, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: span.length, height: bounds.height))
        }
    }
}

/// How many flexible modules (Dock, spacer) a zone or a group holds - read
/// by `MenuBarZones` and `MenuBarGroupStack` to hand out the spare room.
struct MenuBarFlexCount: LayoutValueKey {
    static let defaultValue = 0
}

/// The groups of one zone in a row. Unlike a plain HStack, which splits
/// spare room between every child that accepts it - and a group's `BarStack`
/// accepts any width - only the groups holding a Dock or a spacer grow, by
/// an equal share per flexible module (`MenuBarZoneLayout.stack`). Measured
/// without a width it is the groups' natural widths, flexible modules
/// counted as 0.
struct MenuBarGroupStack: Layout {
    var spacing: CGFloat

    private func naturals(_ subviews: Subviews, height: CGFloat?) -> [CGSize] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: height)) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = naturals(subviews, height: proposal.height)
        let natural = sizes.map(\.width).reduce(0, +) + CGFloat(max(subviews.count - 1, 0)) * spacing
        let tallest = sizes.map(\.height).max() ?? 0
        let flexible = subviews.contains { $0[MenuBarFlexCount.self] > 0 }
        let width = flexible ? (proposal.width ?? natural) : natural
        return CGSize(width: width, height: proposal.height ?? tallest)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = naturals(subviews, height: bounds.height)
        let spans = MenuBarZoneLayout.stack(
            naturals: sizes.map(\.width), weights: subviews.map { $0[MenuBarFlexCount.self] },
            length: bounds.width, spacing: spacing
        )
        for (subview, span) in zip(subviews, spans) {
            subview.place(at: CGPoint(x: bounds.minX + span.origin, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: span.length, height: bounds.height))
        }
    }
}

/// The live bar in its panel: reads the bar and the feature switches from the
/// settings (so a change in Nexus redraws right away) and the notch from its
/// panel.
struct MenuBarRoot: View {
    let settings: ShellSettingsStore
    let state: MenuBarPanelState
    let context: BarModuleContext
    /// The status icons open their details through it (`MenuBarPopout`).
    let popout: StatusPopoutModel
    /// The global edit mode; handed over once when the panel is built, like
    /// the sidebar's (`Sidebar.editor`).
    var editor: ShellEditor?

    var body: some View {
        MenuBarView(bar: Self.shown(settings.settings.apolloMenuBar, editor: editor), notch: state.notch,
                    features: settings.settings.features, context: context, editor: editor)
            .environment(popout)
    }

    /// The bar as the panel would show it, without a panel - for the
    /// edit mode's image samples.
    static func shownView(settings: ShellSettingsStore, editor: ShellEditor?,
                          context: BarModuleContext) -> some View {
        MenuBarView(bar: shown(settings.settings.apolloMenuBar, editor: editor), notch: nil,
                    features: settings.settings.features, context: context, editor: editor)
    }

    /// While editing, the zones come from the working copy; style,
    /// thickness and the rest stay the settings' (the session only edits
    /// zones, and the panel's frame was measured from the settings).
    static func shown(_ bar: ApolloMenuBar, editor: ShellEditor?) -> ApolloMenuBar {
        guard let editor, editor.isEditing, let session = editor.bar else { return bar }
        var bar = bar
        for zone in BarZone.allCases { bar[zone] = session.menuBar[zone] }
        return bar
    }
}

/// The drop net of one zone while editing, with its marking: a kind from the
/// gallery or a block from elsewhere dropped next to the zone's blocks goes to
/// its end (`BarAppendDropModifier`), and the zone outlines itself while a
/// drag hovers over it, so it is clear which zone takes the drop.
private struct MenuBarZoneDrop: ViewModifier {
    let editor: ShellEditor?
    let place: BarPlace
    let active: Bool
    @State private var targeted = false
    @Environment(\.shellStyle) private var style

    func body(content: Content) -> some View {
        if let editor {
            content
                .overlay {
                    if targeted {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(style.accent.opacity(0.6), lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
                .modifier(BarAppendDropModifier(editor: editor, place: place, active: active, targeted: $targeted))
        } else {
            content
        }
    }
}

/// The target an empty zone shows while editing: a dashed slot with a plus,
/// so it can be seen and hit. The zone's drop net (`MenuBarZoneDrop`) takes
/// the drops; a click makes the zone the gallery's target
/// (`ShellEditor.barTargetPlace`), as a selected block would - an empty zone
/// has no block to select.
private struct MenuBarEmptyZone: View {
    let editor: ShellEditor
    let place: BarPlace
    let thickness: CGFloat
    @Environment(\.shellStyle) private var style

    var body: some View {
        let chosen = editor.galleryBarPlace == place
        Button {
            editor.barTargetPlace = chosen ? nil : place
        } label: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(chosen ? AnyShapeStyle(style.accent) : AnyShapeStyle(.secondary),
                              style: StrokeStyle(lineWidth: chosen ? 2 : 1.5, dash: [4, 3]))
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(chosen ? AnyShapeStyle(style.accent) : AnyShapeStyle(.secondary))
                }
                .frame(width: 56, height: thickness)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Drop a block here, or click and pick one in the gallery")
        .accessibilityLabel("Empty zone")
    }
}

/// What the panel knows and the view needs: the notch changes with the
/// screen (and with "Cover Apple's menu bar" on or off).
@MainActor
@Observable
final class MenuBarPanelState {
    var notch: BarNotch?
}
