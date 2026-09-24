import ApolloShellCore
import SwiftUI
import UniformTypeIdentifiers

// The edit surface of the sidebar in the global edit mode
// (design/2026-09-20-bar-edit-plan.md task 3): the blocks wobble, can be
// selected, removed and dragged, and the options of the selected block
// appear in a popover next to it. `SidebarContent` shows these building
// blocks only while `editor.isEditing` holds - the calm bar stays exactly
// the view it was (image comparison).

/// Payload while dragging a block that is already in a bar. A different
/// prefix from the gallery's `apolloshell.bar:` (a kind): the drop target
/// has to tell "move this block" from "insert a new one". After the prefix
/// `BarEntryRef.payload`: a sidebar block is still its bare id, a menu bar
/// block names its zone too, so a block can be dropped into another bar.
enum BarEntryDragPayload {
    static let prefix = "apolloshell.bar.entry:"
    static func string(for ref: BarEntryRef) -> String { prefix + ref.payload }
    static func ref(from string: String) -> BarEntryRef? {
        guard string.hasPrefix(prefix) else { return nil }
        return BarEntryRef(payload: String(string.dropFirst(prefix.count)))
    }
}

/// The bar while editing. `layout` is the working copy
/// (`editor.bar.layout`) - a separate parameter instead of reading through
/// `editor`, so the blocks and the animation see the same arrangement.
struct EditableBarContent: View {
    let editor: ShellEditor
    let layout: BarLayout
    let context: BarModuleContext
    let spacing: CGFloat
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dashboardReducesMotionOverride) private var reduceMotionOverride
    @Environment(\.dashboardRendersForScreenshot) private var rendersForScreenshot
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        let entries = layout.entries
        BarStack(spacing: spacing) {
            ForEach(entries) { entry in
                EditableBarBlock(editor: editor, entry: entry, ref: .sidebar(entry.id), context: context,
                                 reduceMotion: reduceMotion, dragging: !rendersForScreenshot)
                    .layoutValue(key: BarFlexible.self, value: entry.kind.isFlexible)
            }
        }
        .animation(SidebarMotion.spatial, value: entries.map(\.id))
        // A block dragged out of the gallery that lands between two blocks,
        // or on the padding above and below, still arrives - at the end.
        .modifier(BarAppendDropModifier(editor: editor, place: .sidebar, active: !rendersForScreenshot))
    }
}

/// One block while editing: it draws exactly what the calm bar draws, but
/// its own controls do nothing - a click selects it instead. The sidebar and
/// the menu bar share it.
struct EditableBarBlock: View {
    let editor: ShellEditor
    let entry: BarEntry
    let ref: BarEntryRef
    let context: BarModuleContext
    let reduceMotion: Bool
    let dragging: Bool
    /// Stands in the menu bar rather than the sidebar.
    var inMenuBar = false
    @Environment(\.shellStyle) private var style
    @State private var isDeleting = false
    @State private var targeted = false

    /// Every block wobbles a touch out of step, so the bar does not pulse
    /// as one piece (the dashboard widgets do the same).
    private var phase: Double { Double(abs(entry.id.hashValue) % 260) / 1000 }
    private var isSelected: Bool { editor.selectedBarEntry == ref }
    /// In the menu bar every block has an option: joining its neighbour.
    private var showsOptions: Bool { isSelected && !isDeleting && (entry.module.hasOptions || inMenuBar) }
    /// The menu bar stretches its blocks across, not along: along they keep
    /// their own length, as in the calm bar.
    private var horizontal: Bool { inMenuBar }

    var body: some View {
        Button {
            editor.selectedBarEntry = isSelected ? nil : ref
        } label: {
            BarModuleView(entry: entry, context: context)
                // The real action of the block belongs to the bar, not to
                // the editor: while editing a click selects instead of
                // opening the dashboard or switching a space.
                .allowsHitTesting(false)
                .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay {
            let shape = RoundedRectangle(cornerRadius: 10)
            if isSelected {
                shape.strokeBorder(style.accent, lineWidth: 2)
            } else if targeted {
                shape.strokeBorder(style.accent.opacity(0.5), lineWidth: 2)
            } else if reduceMotion {
                shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .topLeading) { minusBadge }
        .editWobble(phase: phase, active: !reduceMotion)
        .opacity(isDeleting ? 0 : 1)
        .scaleEffect(isDeleting ? 0.6 : 1)
        .modifier(BarEntryDragModifier(ref: ref, active: dragging))
        .modifier(BarEntryDropModifier(editor: editor, ref: ref, targeted: $targeted, active: dragging))
        .help(entry.kind.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.kind.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // Only lets go of its own selection: the popover closing because a
        // block in another bar was just picked must not clear that pick.
        .popover(isPresented: Binding(
            get: { showsOptions },
            set: { if !$0, isSelected { editor.selectedBarEntry = nil } }
        ), arrowEdge: arrowEdge) {
            BarBlockOptionsView(editor: editor, entry: entry, ref: ref) { editor.selectedBarEntry = nil }
        }
    }

    /// Away from the screen edge the bar stands on.
    private var arrowEdge: Edge { inMenuBar ? .bottom : .trailing }


    private var badgeSize: CGFloat { inMenuBar ? 14 : 18 }

    private var minusBadge: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isDeleting = true }
            if isSelected { editor.selectedBarEntry = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { editor.removeBarEntry(ref) }
        } label: {
            Image(systemName: "minus")
                .font(.system(size: inMenuBar ? 8 : 10, weight: .bold))
                .frame(width: badgeSize, height: badgeSize)
                .background(EditBadge.background, in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Inside the block, not outside it: the bar is only
        // `Sidebar.width` wide (44 pt by default), and a badge hanging over
        // the left edge would be cut off by the window. The menu bar is
        // hardly thicker than its blocks, so its badge is smaller and stays
        // within the block's corner.
        .offset(x: 1, y: inMenuBar ? 1 : -4)
        .help("Remove")
        .accessibilityLabel("Remove \(entry.kind.title)")
    }
}

/// The disc behind the `−` badge of the edit mode.
///
/// A plain fill, not `.regularMaterial`: a material is a live blur, and with
/// one badge per block there were around 28 of them on screen at once.
/// Measured on 20.09. they were the biggest single item in the mode's GPU
/// bill. At 18 pt nobody can tell the difference.
enum EditBadge {
    static let background = Color(nsColor: .windowBackgroundColor).opacity(0.85)
}

/// The wobble of the edit mode, in one place for all three surfaces.
///
/// It used to be a `withAnimation(.repeatForever)` started in `onAppear`.
/// SwiftUI drops such an animation as soon as the subtree redraws without
/// an animated transaction, so only the surface that was just touched kept
/// wobbling (his live test, 20.09.). `phaseAnimator` is held by SwiftUI
/// itself and survives every redraw.
///
/// The old rate was 0.15 s per half turn - nearly 7 Hz on every block of
/// three surfaces at once, which cost half the GPU power of the whole mode
/// (measured 20.09.: 1280 mW with, 650 mW without). 0.45 s reads the same
/// and costs a third.
extension View {
    @ViewBuilder
    func editWobble(phase: Double, active: Bool) -> some View {
        if active {
            phaseAnimator([-0.3, 0.3], trigger: false) { view, angle in
                view.rotationEffect(.degrees(angle))
            } animation: { _ in
                .easeInOut(duration: 0.45).delay(phase)
            }
        } else {
            self
        }
    }
}

// MARK: - Options of the selected block (popover)

/// The same choices the Nexus bar editor offered, in a popover next to the
/// block. It writes into the working copy (`ShellEditor.updateBarEntry`),
/// never into the settings - Cancel has to be able to drop them.
struct BarBlockOptionsView: View {
    let editor: ShellEditor
    let entry: BarEntry
    let ref: BarEntryRef
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.kind.title)
                .font(.headline)
            if ref.place != .sidebar {
                joinToggle
                if entry.module.hasOptions { Divider() }
            }
            if ref.place == .sidebar || entry.module.hasOptions {
                rows
            }
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    @ViewBuilder
    private var rows: some View {
        switch entry.module {
        case .workspaces(let options):
            Picker("Style", selection: binding(options.style) { .workspaces(.init(style: $0)) }) {
                Text("Dots").tag(BarWorkspacesOptions.Style.dots)
                Text("Numbers").tag(BarWorkspacesOptions.Style.numbers)
                Text("Pills").tag(BarWorkspacesOptions.Style.pills)
                Text("Bars").tag(BarWorkspacesOptions.Style.bars)
            }
            .pickerStyle(.segmented)
        case .dock(let options):
            Toggle("Show Running Apps", isOn: binding(options.showRunning) {
                .dock(.init(showRunning: $0, iconSize: options.iconSize))
            })
            Picker("Icon Size", selection: binding(options.iconSize) {
                .dock(.init(showRunning: options.showRunning, iconSize: $0))
            }) {
                ForEach(BarDockOptions.IconSize.allCases, id: \.self) { size in
                    Text(BarEditText.size(size)).tag(size)
                }
            }
            .pickerStyle(.segmented)
        case .clock(let options):
            Toggle("Show Icon", isOn: binding(options.showIcon) {
                .clock(.init(showIcon: $0, showDate: options.showDate, style: options.style))
            })
            Toggle("Show Date", isOn: binding(options.showDate) {
                .clock(.init(showIcon: options.showIcon, showDate: $0, style: options.style))
            })
            // `nil` stays selectable: "Automatic" is what a clock saved
            // before faces had, and it adapts when the block moves between
            // the sidebar and the menu bar.
            Picker("Style", selection: binding(options.style) {
                .clock(.init(showIcon: options.showIcon, showDate: options.showDate, style: $0))
            }) {
                Text("Automatic").tag(BarClockOptions.Style?.none)
                Text("Line").tag(BarClockOptions.Style?.some(.line))
                Text("Stacked").tag(BarClockOptions.Style?.some(.stacked))
                Text("Badge").tag(BarClockOptions.Style?.some(.badge))
            }
        case .statusIcons(let options):
            Toggle("Wi-Fi", isOn: binding(options.showWifi) {
                .statusIcons(.init(showWifi: $0, showBluetooth: options.showBluetooth,
                                   showBattery: options.showBattery))
            })
            Toggle("Bluetooth", isOn: binding(options.showBluetooth) {
                .statusIcons(.init(showWifi: options.showWifi, showBluetooth: $0,
                                   showBattery: options.showBattery))
            })
            Toggle("Battery", isOn: binding(options.showBattery) {
                .statusIcons(.init(showWifi: options.showWifi, showBluetooth: options.showBluetooth,
                                   showBattery: $0))
            })
        case .gap(let options):
            // A stepper, not a slider: every step writes the working copy,
            // and a slider would do that on every mouse movement.
            Stepper(value: binding(options.height) { .gap(.init(height: $0)) },
                    in: BarGapOptions.range, step: 4) {
                LabeledContent("Height", value: "\(Int(options.height)) pt")
            }
        case .appButton(let options):
            AppChoiceRow(bundleID: options.bundleID) { id in
                editor.updateBarEntry(ref, to: .appButton(.init(bundleID: id)))
            }
        case .battery(let options):
            Toggle("Show Icon", isOn: binding(options.showIcon) { .battery(.init(showIcon: $0)) })
        case .cpu(let options):
            Picker("Style", selection: binding(options.style) { .cpu(.init(style: $0)) }) {
                Text("Ring").tag(BarCPUOptions.Style.ring)
                Text("Percent").tag(BarCPUOptions.Style.percent)
            }
            .pickerStyle(.segmented)
        case .weather(let options):
            Toggle("Show Temperature", isOn: binding(options.showTemperature) {
                .weather(.init(showTemperature: $0))
            })
            BarWeatherPlacesSection()
        case .nowPlaying(let options):
            Toggle("Show Controls", isOn: binding(options.showControls) {
                .nowPlaying(.init(maxLength: options.maxLength, showControls: $0))
            })
            lengthStepper(options.maxLength) { .nowPlaying(.init(maxLength: $0, showControls: options.showControls)) }
        case .windowTitle(let options):
            Toggle("Show Icon", isOn: binding(options.showIcon) {
                .windowTitle(.init(showIcon: $0, showTitle: options.showTitle, maxLength: options.maxLength))
            })
            Toggle("Show Window Title", isOn: binding(options.showTitle) {
                .windowTitle(.init(showIcon: options.showIcon, showTitle: $0, maxLength: options.maxLength))
            })
            lengthStepper(options.maxLength) {
                .windowTitle(.init(showIcon: options.showIcon, showTitle: options.showTitle, maxLength: $0))
            }
            Text("The window title needs Accessibility access, like keeping windows out of the bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .keyboardLayout(let options):
            Toggle("Show Icon", isOn: binding(options.showIcon) { .keyboardLayout(.init(showIcon: $0)) })
        case .volume(let options):
            Toggle("Show Percent", isOn: binding(options.showPercent) {
                .volume(.init(showPercent: $0, showDevice: options.showDevice))
            })
            Toggle("Show Output Device", isOn: binding(options.showDevice) {
                .volume(.init(showPercent: options.showPercent, showDevice: $0))
            })
        case .systemStats(let options):
            Toggle("CPU", isOn: binding(options.showCPU) {
                .systemStats(.init(showCPU: $0, showMemory: options.showMemory))
            })
            Toggle("Memory", isOn: binding(options.showMemory) {
                .systemStats(.init(showCPU: options.showCPU, showMemory: $0))
            })
        case .dashboardButton, .utilitiesButton, .power, .spacer, .divider, .mediaButton, .timer, .networkSpeed,
             .wifi, .bluetooth, .appleMenu, .appMenu, .statusItems:
            Text("Nothing to set.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// Menu bar only: one capsule with the block before it. Off for the
    /// first block of a zone - there is nothing before it to join.
    private var joinToggle: some View {
        let canJoin = editor.bar?.canJoin(ref) ?? false
        return Toggle("Join with Previous", isOn: Binding(
            get: { entry.joinsPrevious && canJoin },
            set: { editor.setBarEntryJoins(ref, $0) }
        ))
        .disabled(!canJoin)
        .help(canJoin ? "Share one capsule with the block before it" : "The first block of a zone has nothing to join")
    }

    /// The longest text before the ellipsis. A stepper like the gap's, for
    /// the same reason: every step writes the working copy.
    private func lengthStepper(_ value: Int, _ make: @escaping (Int) -> BarModule) -> some View {
        Stepper(value: binding(value, make), in: BarText.lengthRange, step: 4) {
            LabeledContent("Maximum Length", value: String(localized: "\(value) characters"))
        }
    }

    /// One option of this block: reading stays on the working copy, writing
    /// goes back through the editor as a whole module.
    private func binding<Value>(_ value: Value, _ make: @escaping (Value) -> BarModule) -> Binding<Value> {
        Binding(get: { value }, set: { editor.updateBarEntry(ref, to: make($0)) })
    }
}

/// The words for choices that have none of their own in the core.
@MainActor
enum BarEditText {
    static func size(_ size: BarDockOptions.IconSize) -> String {
        switch size {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
}

// MARK: - Dragging and dropping

private struct BarEntryDragModifier: ViewModifier {
    let ref: BarEntryRef
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrag {
                NSItemProvider(object: BarEntryDragPayload.string(for: ref) as NSString)
            }
        } else {
            content
        }
    }
}

private struct BarEntryDropModifier: ViewModifier {
    let editor: ShellEditor
    let ref: BarEntryRef
    @Binding var targeted: Bool
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrop(of: [.text], delegate: BarEntryDropDelegate(editor: editor, ref: ref,
                                                                      targeted: $targeted))
        } else {
            content
        }
    }
}

/// A block dropped on another one takes its place (from another zone or bar
/// it goes in right before it), and a kind dropped out of the gallery is
/// inserted there - so where it lands is where it lies.
private struct BarEntryDropDelegate: DropDelegate {
    let editor: ShellEditor
    let ref: BarEntryRef
    @Binding var targeted: Bool

    func dropEntered(info: DropInfo) {
        targeted = true
        EditDragPayload.remember(info, types: [.text])
    }

    func dropExited(info: DropInfo) {
        targeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        EditDragPayload.refuses(.bar) ? DropProposal(operation: .forbidden) : DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        if EditDragPayload.refuses(.bar) { return false }
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let ref = ref
        let index = editor.bar?[ref.place].entries.firstIndex { $0.id == ref.id }
        provider.loadObject(ofClass: NSString.self) { text, _ in
            guard let text = text as? String else { return }
            DispatchQueue.main.async {
                if let dragged = BarEntryDragPayload.ref(from: text), dragged != ref {
                    editor.moveBarEntry(dragged, onto: ref)
                } else if let kind = BarModuleDragPayload.kind(from: text) {
                    editor.addBarModule(kind, to: ref.place, at: index)
                }
            }
        }
        return true
    }
}

/// The safety net around the whole bar (or one zone of the menu bar): a kind
/// from the gallery that lands next to a block instead of on one is appended
/// at its usual spot, and a block from another bar or zone goes to the end.
struct BarAppendDropModifier: ViewModifier {
    let editor: ShellEditor
    let place: BarPlace
    let active: Bool
    /// Set while a drag hovers over it, for the zone's drop marking.
    var targeted: Binding<Bool>?

    func body(content: Content) -> some View {
        if active {
            content.onDrop(of: [.text], delegate: BarAppendDropDelegate(editor: editor, place: place,
                                                                       targeted: targeted))
        } else {
            content
        }
    }
}

/// The net itself. A delegate rather than the short closure form: only
/// this way can it say no to a payload of another surface while it is
/// still being dragged, instead of swallowing it at the drop.
private struct BarAppendDropDelegate: DropDelegate {
    let editor: ShellEditor
    let place: BarPlace
    let targeted: Binding<Bool>?

    func dropEntered(info: DropInfo) {
        targeted?.wrappedValue = true
        EditDragPayload.remember(info, types: [.text])
    }

    func dropExited(info: DropInfo) { targeted?.wrappedValue = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        EditDragPayload.refuses(.bar) ? DropProposal(operation: .forbidden) : DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted?.wrappedValue = false
        if EditDragPayload.refuses(.bar) { return false }
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let place = place
        provider.loadObject(ofClass: NSString.self) { text, _ in
            guard let text = text as? String else { return }
            DispatchQueue.main.async {
                if let kind = BarModuleDragPayload.kind(from: text) {
                    editor.addBarModule(kind, to: place)
                } else if let dragged = BarEntryDragPayload.ref(from: text),
                          // A sidebar block let go between sidebar blocks
                          // stays where it was, as it always did.
                          dragged.place != place || place != .sidebar {
                    editor.moveBarEntry(dragged, toEndOf: place)
                }
            }
        }
        return true
    }
}
