import ApolloShellCore
import SwiftUI

// Content of the toolbar and gallery of the global edit mode (task 3).
// Pure SwiftUI views, hosted in `FloatingGlassPanel`
// (`EditModeWindows.swift`) and - for the `--render-edit` screenshot -
// directly in `RenderMode.swift`.

/// Which tab the gallery shows. Not `WidgetSurface`: that says where a
/// widget is at home, and no widget is at home in the sidebar.
enum GalleryTab: String, CaseIterable, Identifiable {
    case dashboard, controlCentre, bar

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: String(localized: "Dashboard")
        case .controlCentre: String(localized: "Control Centre")
        case .bar: String(localized: "Sidebar")
        }
    }
}

/// Payload for dragging a sidebar block out of the gallery.
enum BarModuleDragPayload {
    static let prefix = "apolloshell.bar:"
    static func string(for kind: BarModuleKind) -> String { prefix + kind.rawValue }
    static func kind(from string: String) -> BarModuleKind? {
        guard string.hasPrefix(prefix) else { return nil }
        return BarModuleKind(rawValue: String(string.dropFirst(prefix.count)))
    }
}

/// Payload for dragging a quick toggle from the gallery into the control
/// center panel (target follows in task 5).
enum UtilitiesToggleDragPayload {
    static let prefix = "apolloshell.toggle:"
    static func string(for kind: UtilitiesToggleKind) -> String { prefix + kind.rawValue }
    static func kind(from string: String) -> UtilitiesToggleKind? {
        guard string.hasPrefix(prefix) else { return nil }
        return UtilitiesToggleKind(rawValue: String(string.dropFirst(prefix.count)))
    }
}

/// Payload for dragging a control center card out of the gallery.
enum UtilitiesCardDragPayload {
    static let prefix = "apolloshell.card:"
    static func string(for kind: UtilitiesCardKind) -> String { prefix + kind.rawValue }
    static func kind(from string: String) -> UtilitiesCardKind? {
        guard string.hasPrefix(prefix) else { return nil }
        return UtilitiesCardKind(rawValue: String(string.dropFirst(prefix.count)))
    }
}

/// Toolbar bottom center: **+** (open/close the gallery), **Cancel**,
/// **Done**. With unsaved changes and Esc (task 6), a confirmation prompt
/// briefly takes its place.
struct EditToolbarView: View {
    @Bindable var editor: ShellEditor
    @Environment(\.shellStyle) private var style

    var body: some View {
        Group {
            if editor.pendingCancelConfirmation {
                cancelConfirmation
            } else {
                controls
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .fixedSize()
        .animation(.easeOut(duration: 0.15), value: editor.pendingCancelConfirmation)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                editor.galleryVisible.toggle()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    // The whole circle, not just the plus sign.
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: .circle)
            .help("Add Element")
            .accessibilityLabel("Add")

            // Size of the Dashboard (formerly Nexus > Dashboard): the
            // pinned Dashboard grows and shrinks along with it right away,
            // it is only saved with "Done".
            HStack(spacing: 8) {
                Image(systemName: "square.resize")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { editor.dashboard.scale ?? 1 },
                    set: { editor.dashboard.scale = BentoGeometry.clampedUserScale($0) }
                ), in: BentoGeometry.userScaleRange)
                .frame(width: 120)
                Text("\(Int(((editor.dashboard.scale ?? 1) * 100).rounded())) %")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .help("Dashboard size")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Dashboard size")

            Button("Cancel") {
                editor.cancel()
            }
            .buttonStyle(.bordered)

            Button("Done") {
                editor.done()
            }
            .buttonStyle(.borderedProminent)
            .tint(style.accent)
        }
    }

    /// "Discard changes?" - Esc with unsaved changes
    /// (`ShellEditor.handleEscape`) shows this instead of the three
    /// buttons above, until a decision is made.
    private var cancelConfirmation: some View {
        HStack(spacing: 14) {
            Text("Discard changes?")
                .font(.callout.weight(.medium))
            Button("Keep Editing") {
                editor.dismissCancelConfirmation()
            }
            .buttonStyle(.bordered)
            Button("Discard", role: .destructive) {
                editor.confirmCancel()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}

/// Only in `RenderMode --render-edit`: `ImageRenderer` draws `.onDrag`
/// (AppKit-backed for `NSItemProvider` drag sessions) offscreen as a red
/// no-entry sign (same cause as `.onDrop`, see
/// `dashboardRendersForScreenshot`). For the real window, dragging always
/// stays on.
private struct GalleryRendersForScreenshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var galleryRendersForScreenshot: Bool {
        get { self[GalleryRendersForScreenshotKey.self] }
        set { self[GalleryRendersForScreenshotKey.self] = newValue }
    }
}

/// Width of the gallery (`EditGalleryView.body`) and its inner size
/// (16 pt margin on each side) - `GalleryGrid` computes directly with
/// this instead of a width guessed from `proposal` (see there).
// Wide and flat like Apple's widget gallery: it sits below the
// Dashboard, and on a 14-inch screen there is only about 300 pt of
// height free there (previously 560 wide with four columns, a good
// 370 tall - it covered the Dashboard). 760 leaves room on the right
// for the control center.
private let galleryWidth: CGFloat = 760
private let galleryContentWidth: CGFloat = galleryWidth - 2 * 16
/// Number of columns of the tile grid at `galleryContentWidth`: as wide
/// as one tile (108) plus spacing fits.
private let galleryColumns = 8

/// "Dashboard"/"Control Centre" tabs: custom capsules instead of
/// `Picker(.segmented)` - AppKit-backed, `ImageRenderer` draws it
/// offscreen as a yellow bar (same cause as the switch below), and in
/// appearance it was a foreign element next to the rest of the shell
/// anyway (compare the Dashboard's page tabs, `DashboardView.pageButton`).
private struct GallerySurfaceTabs: View {
    @Binding var selection: GalleryTab
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 4) {
            ForEach(GalleryTab.allCases) { one in tab(one) }
        }
        .padding(3)
        .background(.quaternary.opacity(0.4), in: Capsule())
    }

    private func tab(_ tab: GalleryTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            Text(tab.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    if isSelected { Capsule().fill(style.accent) }
                }
                // The whole capsule is clickable, even for the unselected
                // tab (without a background there - previously only the
                // text reacted).
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Custom switch instead of `Toggle(.switch)` - the same AppKit reason as
/// for the tabs above.
private struct GalleryCheckbox: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            // The whole row is clickable, not just the symbol and letters.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Fixed tile grid in `columns` columns, equally wide rows. No
/// `LazyVGrid`: see the comment at `EditGalleryView.body` - for the
/// fixed, manageable number of tiles (widget catalog, cards, quick
/// toggles) this costs nothing, but it makes the gallery
/// `ImageRenderer`-compatible.
private struct GalleryGrid: Layout {
    let columns: Int
    let spacing: CGFloat
    /// Fixed width instead of guessed from `proposal`: in a `ScrollView`
    /// the proposed width comes back as `nil` sometimes, and as a
    /// placeholder value other times - especially offscreen with
    /// `ImageRenderer` (screenshots). The gallery has a fixed width
    /// anyway (`EditGalleryView`), the grid computes directly with its
    /// inner size instead of guessing.
    let width: CGFloat

    private func columnWidth() -> CGFloat {
        (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let columnWidth = columnWidth()
        let rowHeight = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }.max() ?? 0
        let rows = Int((Double(subviews.count) / Double(columns)).rounded(.up))
        let height = CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = columnWidth()
        let rowHeight = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }.max() ?? 0
        for (index, subview) in subviews.enumerated() {
            let row = index / columns
            let col = index % columns
            let x = bounds.minX + CGFloat(col) * (columnWidth + spacing)
            let y = bounds.minY + CGFloat(row) * (rowHeight + spacing)
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: columnWidth, height: rowHeight))
        }
    }
}

/// Gallery: one tab per surface, with tiles to drag or click. "Show All
/// (Advanced)" also shows elements of the other surface (spec: "not
/// optimised" outside their home).
struct EditGalleryView: View {
    @Bindable var editor: ShellEditor
    @Environment(\.galleryRendersForScreenshot) private var rendersForScreenshot

    var body: some View {
        VStack(spacing: 12) {
            GallerySurfaceTabs(selection: $editor.galleryTab)

            // Only on the dashboard tab: it is the one list that hides
            // something (widgets that are at home somewhere else). The
            // control centre and the sidebar show every kind they have, so
            // the box sat there without an effect (20.09.).
            if editor.galleryTab == .dashboard {
                GalleryCheckbox(title: String(localized: "Show All (Advanced)"), isOn: $editor.showsAllInGallery)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // No `LazyVGrid`: a custom, fixed grid counting rows instead
            // of columns reliably includes every tile. `ImageRenderer`
            // draws the `ScrollView` around it as empty offscreen when
            // its content is a custom `Layout` tile (`--render-edit`
            // screenshot, measured 09/19) - it is left out there, the
            // grid stands uncropped. In the real window it stays: more
            // tiles than the fixed height would not fit otherwise.
            if rendersForScreenshot {
                galleryGrid
            } else {
                ScrollView {
                    galleryGrid
                }
                .frame(height: 200)
            }

            if let notice = editor.galleryNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(width: galleryWidth)
    }

    private var galleryGrid: some View {
        GalleryGrid(columns: galleryColumns, spacing: 10, width: galleryContentWidth) {
            switch editor.galleryTab {
            case .dashboard: dashboardTiles
            case .controlCentre: controlCentreTiles
            case .bar: barTiles
            }
        }
        .padding(.vertical, 4)
    }

    private var dashboardTiles: some View {
        ForEach(WidgetKind.allCases.filter { editor.showsAllInGallery || $0.home == .dashboard }) { kind in
            EditGalleryTile(symbol: kind.symbol, title: kind.title, detail: sizesText(kind.sizes.count),
                            tooltip: kind.title, payload: BentoWidgetDragPayload.string(for: kind), isDisabled: false) {
                // The same favorites as when dropping
                // (`BentoDropDelegate.add`) - otherwise a weather widget
                // added by click would start without locations, even
                // though some exist (task 3/5).
                let places = WeatherFavorites.loadLive()
                if editor.dashboard.addAtFirstFreeSpot(kind, places: places) == nil {
                    show(notice: String(localized: "No room on this page"))
                }
            }
        }
    }

    @ViewBuilder
    private var controlCentreTiles: some View {
        ForEach(UtilitiesCardKind.allCases) { kind in
            let already = editor.utilities?.layout.isEnabled(kind) ?? true
            EditGalleryTile(symbol: kind.symbol, title: kind.title, detail: nil, tooltip: kind.summary,
                            payload: UtilitiesCardDragPayload.string(for: kind), isDisabled: already) {
                editor.setCard(kind, enabled: true)
            }
        }
        ForEach(UtilitiesToggleGroup.allCases) { group in
            ForEach(group.kinds) { kind in
                let already = editor.utilities.map { !$0.layout.canAdd(kind) } ?? false
                EditGalleryTile(symbol: kind.symbol ?? "circle", title: kind.title, detail: nil, tooltip: kind.summary,
                                payload: UtilitiesToggleDragPayload.string(for: kind), isDisabled: already) {
                    if editor.addToggle(kind) == nil {
                        show(notice: String(localized: "Already there"))
                    }
                }
            }
        }
    }

    /// Every block of the sidebar. A kind that may exist only once and is
    /// already in the bar stays greyed out, like a card that is on.
    private var barTiles: some View {
        ForEach(BarModuleKind.allCases) { kind in
            let already = editor.bar.map { !$0.layout.canAdd(kind) } ?? false
            EditGalleryTile(symbol: kind.symbol, title: kind.title, detail: nil, tooltip: kind.summary,
                            payload: BarModuleDragPayload.string(for: kind), isDisabled: already) {
                if editor.addBarModule(kind) == nil {
                    show(notice: String(localized: "Already there"))
                }
            }
        }
    }

    private func sizesText(_ count: Int) -> String {
        count == 1 ? String(localized: "1 size") : String(localized: "\(count) sizes")
    }

    private func show(notice text: String) {
        withAnimation { editor.galleryNotice = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { editor.galleryNotice = nil }
        }
    }
}

/// A tile in the gallery: symbol, title, optionally a short figure
/// (Dashboard: number of sizes). The full description (control center:
/// `UtilitiesCardKind.summary`/`UtilitiesToggleKind.summary`, often
/// longer than one line) only appears in the tooltip (`.help`) - as a
/// third line it overflowed every tile (live test 09/19). Dragging sets
/// the text payload (`apolloshell.widget:`/`.toggle:`/`.card:`), a click
/// lands at the first free spot or at the end.
private struct EditGalleryTile: View {
    let symbol: String
    let title: String
    /// Short figure under the title; `nil` leaves the line out.
    let detail: String?
    let tooltip: String
    let payload: String
    let isDisabled: Bool
    let action: () -> Void
    @Environment(\.galleryRendersForScreenshot) private var rendersForScreenshot

    var body: some View {
        // No `Button`: it tracks the mouse itself and often would not let
        // `.onDrag` even start under macOS - dragging out of the gallery
        // then did not work (live test 09/19). A tap without a drag
        // inserts it, a drag drags it; both work fine with
        // `onTapGesture`.
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .frame(height: 24)
            // Two lines instead of truncated: "Hide Apps", "Weather
            // Overview" and the like do not fit on one line in 8 columns
            // (live test 09/19: titles hit the tile edge). Always reserve
            // two lines of space, so all tiles stay the same height.
            Text(title)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, 5)
                // A fixed two-line box instead of `reservesSpace`: with the
                // latter a one-line title still sat higher than a two-line
                // one, so "1 size" under "Weather overview" hung below the
                // rest of its row (his screenshot, 20.09.).
                .frame(height: 30, alignment: .top)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cardSurface(radius: 14)
        .contentShape(.rect(cornerRadius: 14))
        .opacity(isDisabled ? 0.4 : 1)
        .onTapGesture { if !isDisabled { action() } }
        .modifier(GalleryDragModifier(payload: payload, active: !rendersForScreenshot && !isDisabled))
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !isDisabled { action() } }
    }
}

/// Attaches `.onDrag` only outside of screenshots: `ImageRenderer` draws
/// the AppKit-backed drag session offscreen as a red no-entry sign (like
/// `.onDrop`, see `BentoDropTarget`). The real window always leaves
/// dragging on.
private struct GalleryDragModifier: ViewModifier {
    let payload: String
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrag { NSItemProvider(object: payload as NSString) }
        } else {
            content
        }
    }
}
