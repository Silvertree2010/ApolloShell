import ApolloShellCore
import SwiftUI
import UniformTypeIdentifiers

// The edit surface of the sidebar in the global edit mode
// (design/2026-09-20-bar-edit-plan.md task 3): the blocks wobble, can be
// selected, removed and dragged, and the options of the selected block
// appear in a popover next to it. `SidebarContent` shows these building
// blocks only while `editor.isEditing` holds - the calm bar stays exactly
// the view it was (image comparison).

/// Payload while dragging a block that is already in the bar. A different
/// prefix from the gallery's `apolloshell.bar:` (a kind): the drop target
/// has to tell "move this block" from "insert a new one".
enum BarEntryDragPayload {
    static let prefix = "apolloshell.bar.entry:"
    static func string(for id: String) -> String { prefix + id }
    static func id(from string: String) -> String? {
        guard string.hasPrefix(prefix) else { return nil }
        return String(string.dropFirst(prefix.count))
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
                EditableBarBlock(editor: editor, entry: entry, context: context,
                                 reduceMotion: reduceMotion, dragging: !rendersForScreenshot)
                    .layoutValue(key: BarFlexible.self, value: entry.kind.isFlexible)
            }
        }
        .animation(SidebarMotion.spatial, value: entries.map(\.id))
        // A block dragged out of the gallery that lands between two blocks,
        // or on the padding above and below, still arrives - at the end.
        .modifier(BarAppendDropModifier(editor: editor, active: !rendersForScreenshot))
    }
}

/// One block while editing: it draws exactly what the calm bar draws, but
/// its own controls do nothing - a click selects it instead.
private struct EditableBarBlock: View {
    let editor: ShellEditor
    let entry: BarEntry
    let context: BarModuleContext
    let reduceMotion: Bool
    let dragging: Bool
    @Environment(\.shellStyle) private var style
    @State private var wobble: Double = 0
    @State private var isDeleting = false
    @State private var targeted = false

    /// Every block wobbles a touch out of step, so the bar does not pulse
    /// as one piece (the dashboard widgets do the same).
    private var phase: Double { Double(abs(entry.id.hashValue) % 260) / 1000 }
    private var isSelected: Bool { editor.selectedBarEntryID == entry.id }
    private var showsOptions: Bool { isSelected && !isDeleting && entry.module.hasOptions }

    var body: some View {
        Button {
            editor.selectedBarEntryID = isSelected ? nil : entry.id
        } label: {
            BarModuleView(entry: entry, context: context)
                // The real action of the block belongs to the bar, not to
                // the editor: while editing a click selects instead of
                // opening the dashboard or switching a space.
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity)
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
        .rotationEffect(.degrees(reduceMotion ? 0 : wobble))
        .opacity(isDeleting ? 0 : 1)
        .scaleEffect(isDeleting ? 0.6 : 1)
        .onAppear { startWobble() }
        .onChange(of: reduceMotion) { _, _ in startWobble() }
        .modifier(BarEntryDragModifier(entry: entry, active: dragging))
        .modifier(BarEntryDropModifier(editor: editor, entry: entry, targeted: $targeted, active: dragging))
        .help(entry.kind.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.kind.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .popover(isPresented: Binding(
            get: { showsOptions },
            set: { if !$0 { editor.selectedBarEntryID = nil } }
        ), arrowEdge: .trailing) {
            BarBlockOptionsView(editor: editor, entry: entry) { editor.selectedBarEntryID = nil }
        }
    }

    private func startWobble() {
        guard !reduceMotion else {
            wobble = 0
            return
        }
        wobble = -0.3
        withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true).delay(phase)) {
            wobble = 0.3
        }
    }

    private var minusBadge: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isDeleting = true }
            if isSelected { editor.selectedBarEntryID = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { editor.removeBarModule(entry.id) }
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 18, height: 18)
                .background(.regularMaterial, in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Inside the block, not outside it: the bar is only
        // `Sidebar.width` wide (44 pt by default), and a badge hanging over
        // the left edge would be cut off by the window.
        .offset(x: 1, y: -4)
        .help("Remove")
        .accessibilityLabel("Remove \(entry.kind.title)")
    }
}

// MARK: - Options of the selected block (popover)

/// The same choices the Nexus bar editor offered, in a popover next to the
/// block. It writes into the working copy (`ShellEditor.updateBarModule`),
/// never into the settings - Cancel has to be able to drop them.
struct BarBlockOptionsView: View {
    let editor: ShellEditor
    let entry: BarEntry
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.kind.title)
                .font(.headline)
            rows
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
                    Text(NexusBarText.size(size)).tag(size)
                }
            }
            .pickerStyle(.segmented)
        case .clock(let options):
            Toggle("Show Icon", isOn: binding(options.showIcon) {
                .clock(.init(showIcon: $0, showDate: options.showDate))
            })
            Toggle("Show Date", isOn: binding(options.showDate) {
                .clock(.init(showIcon: options.showIcon, showDate: $0))
            })
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
            NexusAppChoiceRow(bundleID: options.bundleID) { id in
                editor.updateBarModule(entry.id, to: .appButton(.init(bundleID: id)))
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
        case .dashboardButton, .utilitiesButton, .power, .spacer, .divider, .mediaButton:
            Text("Nothing to set.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// One option of this block: reading stays on the working copy, writing
    /// goes back through the editor as a whole module.
    private func binding<Value>(_ value: Value, _ make: @escaping (Value) -> BarModule) -> Binding<Value> {
        Binding(get: { value }, set: { editor.updateBarModule(entry.id, to: make($0)) })
    }
}

// MARK: - Dragging and dropping

private struct BarEntryDragModifier: ViewModifier {
    let entry: BarEntry
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrag {
                NSItemProvider(object: BarEntryDragPayload.string(for: entry.id) as NSString)
            }
        } else {
            content
        }
    }
}

private struct BarEntryDropModifier: ViewModifier {
    let editor: ShellEditor
    let entry: BarEntry
    @Binding var targeted: Bool
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrop(of: [.text], delegate: BarEntryDropDelegate(editor: editor, entry: entry,
                                                                      targeted: $targeted))
        } else {
            content
        }
    }
}

/// A block dropped on another one takes its place, and a kind dropped out
/// of the gallery is inserted there - so where it lands is where it lies.
private struct BarEntryDropDelegate: DropDelegate {
    let editor: ShellEditor
    let entry: BarEntry
    @Binding var targeted: Bool

    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let index = editor.bar?.layout.entries.firstIndex { $0.id == entry.id }
        provider.loadObject(ofClass: NSString.self) { text, _ in
            guard let text = text as? String else { return }
            DispatchQueue.main.async {
                if let id = BarEntryDragPayload.id(from: text), id != entry.id {
                    editor.moveBarModule(id, onto: entry.id)
                } else if let kind = BarModuleDragPayload.kind(from: text) {
                    editor.addBarModule(kind, at: index)
                }
            }
        }
        return true
    }
}

/// The safety net around the whole bar: a kind from the gallery that lands
/// next to a block instead of on one is appended at its usual spot.
private struct BarAppendDropModifier: ViewModifier {
    let editor: ShellEditor
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrop(of: [.text], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                provider.loadObject(ofClass: NSString.self) { text, _ in
                    guard let text = text as? String,
                          let kind = BarModuleDragPayload.kind(from: text) else { return }
                    DispatchQueue.main.async { editor.addBarModule(kind) }
                }
                return true
            }
        } else {
            content
        }
    }
}
