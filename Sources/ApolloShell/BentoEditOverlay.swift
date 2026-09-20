import ApolloShellCore
import SwiftUI
import UniformTypeIdentifiers

// Edit surface for a Bento page (design/2026-09-18-bento-
// dashboard.md, section 5; design/2026-09-18-bento-plan-edit.md task 3):
// wobbling, selectable widgets with a `-` button and a resize handle, and
// the drop target for widgets dragged in from Nexus. `BentoPageView.swift`
// shows these building blocks only while `editor.isEditing` holds - the
// calm view stays unchanged (screenshot comparison).

/// Payload for dragging a widget from Nexus onto the page.
enum BentoWidgetDragPayload {
    static let prefix = "apolloshell.widget:"

    static func string(for kind: WidgetKind) -> String { prefix + kind.rawValue }

    static func kind(from string: String) -> WidgetKind? {
        guard string.hasPrefix(prefix) else { return nil }
        return WidgetKind(rawValue: String(string.dropFirst(prefix.count)))
    }
}

/// Approximate radius of a kind's own card, for the selection outline
/// while editing (`BentoEditOverlay` does not know the cards themselves -
/// `WidgetView.swift` picks them by size). Where a kind has several radii,
/// the most common one; 24 for kinds without their own card (plan: "radius
/// following the card radius (use 24 pt if the widget has none)").
extension WidgetKind {
    var editSelectionRadius: CGFloat {
        switch self {
        case .weather: 28
        case .user: 28
        case .clock: 16
        case .calendar: 28
        case .resources: 16
        case .media: 28
        case .performanceCPU, .performanceGPU, .performanceStorage, .performanceMemory: 24
        case .performanceNetwork: 10
        case .performanceBattery: 41
        case .weatherHero: 42
        case .weatherHourly: 28
        case .weatherDaily: 24
        case .mediaPlayer: 56
        }
    }
}

extension WidgetKind {
    /// Whether the options popover has anything to show - performance
    /// widgets and playback have no options; an empty popover would only
    /// be in the way (live test 09/19).
    var hasEditOptions: Bool {
        switch self {
        case .weather, .weatherHero, .weatherHourly, .weatherDaily, .user, .clock, .calendar, .resources, .media: true
        case .performanceCPU, .performanceGPU, .performanceStorage, .performanceNetwork, .performanceMemory,
             .performanceBattery, .mediaPlayer: false
        }
    }
}

/// Overrides `accessibilityReduceMotion` (system-wide, not settable) for
/// screenshots (`RenderMode --render-dashboard`, folder `edit/`); `nil`
/// leaves the real system value in effect.
private struct DashboardReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var dashboardReducesMotionOverride: Bool? {
        get { self[DashboardReduceMotionKey.self] }
        set { self[DashboardReduceMotionKey.self] = newValue }
    }
}

/// `true` only in `RenderMode --render-dashboard`'s `edit/` screenshots:
/// `ImageRenderer` does not draw AppKit-backed building blocks offscreen
/// (measured 09/18: `.onDrop` produced a red no-entry sign across the
/// whole page instead of the target) - the drop target is therefore left
/// out for the screenshot. The real dashboard never sets this switch;
/// `.onDrop` stays active there as usual.
private struct RendersForScreenshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var dashboardRendersForScreenshot: Bool {
        get { self[RendersForScreenshotKey.self] }
        set { self[RendersForScreenshotKey.self] = newValue }
    }
}

/// A widget during editing: content disabled (no media buttons, no
/// calendar arrows), wobbles, and can be selected, dragged, resized, and
/// removed.
struct EditableWidgetView: View {
    let widget: WidgetInstance
    let context: WidgetContext
    var editor: DashboardEditor
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dashboardReducesMotionOverride) private var reduceMotionOverride
    @Environment(\.shellStyle) private var style
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    @State private var dragFrame: WidgetFrame?
    @State private var dragValid = true
    @State private var resizeFrame: WidgetFrame?
    @State private var resizeValid = true
    @State private var isDeleting = false
    /// Options open: only after a click (not after every drag - that
    /// opened them in the live test after every move), only for kinds
    /// with options, never while dragging or removing.
    private var showsOptions: Bool {
        isSelected && editor.optionsWidgetID == widget.id && widget.kind.hasEditOptions
            && !isTransforming && !isDeleting
    }

    /// Different phases so widgets do not wobble in lockstep.
    private var phase: Double {
        Double(abs(widget.id.hashValue) % 260) / 1000
    }

    private var frame: WidgetFrame { resizeFrame ?? dragFrame ?? widget.frame }
    private var isSelected: Bool { editor.selectedWidgetID == widget.id }
    private var isTransforming: Bool { dragFrame != nil || resizeFrame != nil }
    private var isValid: Bool { dragFrame != nil ? dragValid : resizeValid }

    private var outlineColor: Color? {
        if isTransforming { return isValid ? style.accent : Color.red }
        return isSelected ? style.accent : nil
    }

    var body: some View {
        WidgetView(widget: widget, context: context)
            .allowsHitTesting(false)
            .frame(width: frame.width, height: frame.height)
            .overlay {
                let shape = RoundedRectangle(cornerRadius: widget.kind.editSelectionRadius, style: .continuous)
                if let outlineColor {
                    shape.strokeBorder(outlineColor, lineWidth: 2)
                } else if reduceMotion {
                    shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) { minusBadge }
            .overlay(alignment: .bottomTrailing) { resizeHandle }
            // After the overlays: the minus and handle wobble with the widget.
            .editWobble(phase: phase, active: !reduceMotion)
            .opacity(isDeleting ? 0 : 1)
            .scaleEffect(isDeleting ? 0.6 : 1)
            .gesture(dragGesture)
            // A tap without a drag: `DragGesture` does not even recognize
            // movements below `minimumDistance`, so it never selects - a
            // separate `TapGesture` alongside it selects without moving
            // and opens the options.
            .simultaneousGesture(TapGesture().onEnded {
                guard !isDeleting else { return }
                editor.selectedWidgetID = widget.id
                editor.optionsWidgetID = widget.id
            })
            // Options of the selected widget (task 4): the same controls
            // as in the old Nexus editor (`WidgetOptionsView`), now right
            // next to the widget instead of in a separate column. Closes
            // by itself when the selection drops or the page changes -
            // both clear `editor.selectedWidgetID`, and the popover only
            // depends on `isSelected`.
            .popover(isPresented: Binding(
                get: { showsOptions },
                set: { if !$0 { editor.optionsWidgetID = nil } }
            ), arrowEdge: .trailing) {
                Form {
                    WidgetOptionsView(editor: editor, widget: widget, weatherFile: ShellFiles.live.weather)
                }
                .formStyle(.grouped)
                .frame(width: 280)
                .frame(minHeight: 120, maxHeight: 420)
            }
            // Placed via layout, not with `.offset`: `.offset` only moves
            // the drawing, the layout frame stays at the top left - the
            // options popover therefore always pointed at the corner of
            // the page instead of at the widget (live test 09/19). While
            // editing, pixel-exactness does not count.
            .padding(.leading, frame.x)
            .padding(.top, frame.y)
            .zIndex(isSelected || isTransforming ? 1 : 0)
    }


    private var minusBadge: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isDeleting = true }
            if editor.optionsWidgetID == widget.id { editor.optionsWidgetID = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { editor.remove(widget.id) }
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .background(EditBadge.background, in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: -11, y: -11)
        .help("Remove")
        .accessibilityLabel("Remove \(widget.kind.title)")
    }

    private var resizeHandle: some View {
        ResizeHandleShape()
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .offset(x: -6, y: -6)
            .gesture(resizeGesture)
            .accessibilityLabel("Resize \(widget.kind.title)")
    }

    /// Dragging the widget: `editor.previewMove` live, releasing commits
    /// if valid, or springs back. Selects the widget in every case.
    private var dragGesture: some Gesture {
        // Named coordinate space on the page (`BentoPageView`), not
        // `.local`: the widget's own frame grows along with a drag
        // (preview), so `.local` values would have shifted in the middle
        // of the drag (measured: jitter).
        DragGesture(minimumDistance: 2, coordinateSpace: .named(BentoPageView.coordinateSpaceName))
            .onChanged { value in
                let proposed = WidgetFrame(x: widget.frame.x + value.translation.width,
                                           y: widget.frame.y + value.translation.height,
                                           width: widget.frame.width, height: widget.frame.height)
                guard let preview = editor.previewMove(widget.id, proposed: proposed) else { return }
                dragFrame = preview.frame
                dragValid = preview.valid
            }
            .onEnded { _ in
                editor.selectedWidgetID = widget.id
                editor.optionsWidgetID = nil
                if let dragFrame, dragValid {
                    editor.commit(widget.id, frame: dragFrame)
                }
                withAnimation(DashboardView.motion) { dragFrame = nil }
                dragValid = true
            }
    }

    /// Bottom-right handle: `editor.previewResize` live, releasing
    /// commits if valid, or springs back.
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(BentoPageView.coordinateSpaceName))
            .onChanged { value in
                let proposedWidth = widget.frame.width + value.translation.width
                let proposedHeight = widget.frame.height + value.translation.height
                guard let preview = editor.previewResize(widget.id, proposedWidth: proposedWidth,
                                                         proposedHeight: proposedHeight) else { return }
                resizeFrame = preview.frame
                resizeValid = preview.valid
            }
            .onEnded { _ in
                editor.selectedWidgetID = widget.id
                editor.optionsWidgetID = nil
                if let resizeFrame, resizeValid {
                    editor.commit(widget.id, frame: resizeFrame)
                }
                withAnimation(DashboardView.motion) { resizeFrame = nil }
                resizeValid = true
            }
    }
}

/// Quarter-circle handle like Apple's widget editing: an arc growing out
/// of the bottom-right corner.
private struct ResizeHandleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.maxX, y: rect.maxY), radius: rect.width / 2,
                   startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        return path
    }
}

/// Attaches `.onDrop` only when `active` holds - `RenderMode` leaves it
/// out (see `EnvironmentValues.dashboardRendersForScreenshot`), the real
/// dashboard always passes `true`.
struct BentoDropTarget: ViewModifier {
    let editor: DashboardEditor
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrop(of: [.plainText], delegate: BentoDropDelegate(editor: editor))
        } else {
            content
        }
    }
}

/// Drop target for widgets dragged out of the edit mode's gallery
/// (payload `"apolloshell.widget:<WidgetKind.rawValue>"`,
/// `NSItemProvider(object:)` on `.onDrag` in `EditGalleryView`). Loads the
/// payload once on entry (async, `NSItemProvider`) and then keeps the kind
/// in `editor.draggedKind`, so every further movement can immediately show
/// a preview.
struct BentoDropDelegate: DropDelegate {
    let editor: DashboardEditor

    func dropEntered(info: DropInfo) {
        // Counter recorded now: if the payload only arrives after the drag
        // has already left this target (`dropExited` increments it), the
        // result no longer counts - otherwise the ghost outline would
        // come back to life.
        let generation = editor.dropGeneration
        loadKind(info) { kind in
            guard generation == editor.dropGeneration else { return }
            editor.draggedKind = kind
            if let kind { updatePreview(kind, info: info) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let kind = editor.draggedKind {
            updatePreview(kind, info: info)
        }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        editor.dropGeneration += 1
        editor.dropPreview = nil
        editor.draggedKind = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let location = info.location
        if let kind = editor.draggedKind {
            add(kind, at: location)
            return true
        }
        // Not loaded yet (a very short drag): deliver it afterwards, but
        // only if this target has not been left in the meantime.
        let generation = editor.dropGeneration
        loadKind(info) { [self] kind in
            guard generation == editor.dropGeneration, let kind else { return }
            add(kind, at: location)
        }
        return true
    }

    private func add(_ kind: WidgetKind, at location: CGPoint) {
        let preview = editor.previewDrop(kind, x: location.x, y: location.y)
        editor.dropPreview = nil
        editor.draggedKind = nil
        guard let preview, preview.valid else { return }
        let places = WeatherFavorites.loadLive()
        editor.add(kind, frame: preview.frame, places: places)
    }

    private func updatePreview(_ kind: WidgetKind, info: DropInfo) {
        let preview = editor.previewDrop(kind, x: info.location.x, y: info.location.y)
        editor.dropPreview = preview.map { (frame: $0.frame, valid: $0.valid) }
    }

    private func loadKind(_ info: DropInfo, completion: @escaping @MainActor @Sendable (WidgetKind?) -> Void) {
        guard let provider = info.itemProviders(for: [.plainText]).first else {
            completion(nil)
            return
        }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            let kind = (value as? String).flatMap(BentoWidgetDragPayload.kind(from:))
            DispatchQueue.main.async { completion(kind) }
        }
    }
}
