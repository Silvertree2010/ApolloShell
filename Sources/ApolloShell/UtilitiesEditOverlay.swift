import ApolloShellCore
import SwiftUI
import UniformTypeIdentifiers

// Edit surface of the control center in the global edit mode
// (design/2026-09-18-bento-dashboard.md section 5, design/2026-09-19-
// shell-edit-plan.md task 5): cards and quick toggles wobble, can be
// selected, removed, and dragged; the options of the selected button
// appear in a popover (the same controls as in the old Nexus editor,
// `UtilitiesEditorOptions.swift`). `UtilitiesPanel.swift` shows these
// building blocks only while `editor.isEditing` holds - the calm view
// (`UtilitiesView`) stays unchanged (screenshot comparison).

/// Root in the edge window during editing. `layout` is the working copy
/// (`editor.utilities.layout`) - a separate parameter instead of reading
/// via `editor`, so the cards below see the same arrangement as the
/// window size (`UtilitiesPanel.apply`).
struct EditableUtilitiesView: View {
    let editor: ShellEditor
    let layout: UtilitiesLayout
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dashboardReducesMotionOverride) private var reduceMotionOverride
    @Environment(\.dashboardRendersForScreenshot) private var rendersForScreenshot
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        let rows = layout.toggleRows
        let cards = layout.visibleCards
        VStack(spacing: UtilitiesView.spacing) {
            if cards.isEmpty {
                UtilitiesEmptyCard(model: UtilitiesEditorPreviewModel.model)
                    .allowsHitTesting(false)
                    .environment(\.utilitiesCardHeight, CGFloat(UtilitiesMetrics.emptyCardHeight))
            }
            ForEach(Array(cards.enumerated()), id: \.element) { index, kind in
                EditableUtilitiesCard(editor: editor, kind: kind, rows: rows, reduceMotion: reduceMotion)
                    .environment(\.utilitiesCardHeight, CGFloat(UtilitiesMetrics.cardHeight(kind, toggleRows: rows.count)))
            }
        }
        .padding(UtilitiesView.padding)
        .frame(width: UtilitiesView.width)
        .fixedSize(horizontal: false, vertical: true)
        // Safety net: a button dragged out of the gallery, or a card that
        // does not land exactly on a tile (gap, empty card), still gets
        // through (to the end, or turned on, respectively).
        .modifier(UtilitiesPanelDropModifier(editor: editor, active: !rendersForScreenshot))
    }
}

// MARK: - Card

/// A card during editing: content disabled (its controls and buttons do
/// nothing), wobbles, can be hidden (minus), and can be dragged
/// vertically onto another card (`ShellEditor.moveUtilitiesCards`).
private struct EditableUtilitiesCard: View {
    let editor: ShellEditor
    let kind: UtilitiesCardKind
    let rows: [[UtilitiesToggleEntry]]
    let reduceMotion: Bool
    @Environment(\.shellStyle) private var style
    @Environment(\.dashboardRendersForScreenshot) private var rendersForScreenshot
    @State private var wobble: Double = 0
    @State private var isHiding = false
    @State private var targeted = false

    /// Different phases like on the Dashboard: the three cards do not
    /// wobble in lockstep.
    private var phase: Double { Double(abs(kind.hashValue) % 260) / 1000 }

    var body: some View {
        content
            // Only mute the Keep Awake and Audio cards (their controls
            // should not trigger anything while editing). The quick-toggles
            // card itself consists of editable tiles while editing -
            // previously `allowsHitTesting(false)` applied to it too, and
            // no tile could be tapped, removed, or moved (self-test 09/19).
            .allowsHitTesting(kind == .quickToggles)
            .overlay {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                if targeted {
                    shape.strokeBorder(style.accent, lineWidth: 2)
                } else if reduceMotion {
                    shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .topLeading) { minusBadge }
            .rotationEffect(.degrees(reduceMotion ? 0 : wobble))
            .opacity(isHiding ? 0 : 1)
            .scaleEffect(isHiding ? 0.94 : 1)
            .onAppear { startWobble() }
            .onChange(of: reduceMotion) { _, _ in startWobble() }
            #if DEBUG
            .background { DebugWindowRectReporter { editor.debugUtilitiesRects["card:" + kind.rawValue] = $0 } }
            #endif
            .modifier(UtilitiesCardDragModifier(kind: kind, active: !rendersForScreenshot))
            .modifier(UtilitiesCardDropModifier(editor: editor, target: kind, targeted: $targeted, active: !rendersForScreenshot))
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .keepAwake: KeepAwakeCard(model: UtilitiesEditorPreviewModel.model)
        case .audio: UtilitiesAudioCard(model: UtilitiesEditorPreviewModel.model)
        case .quickToggles: EditableQuickTogglesCard(editor: editor, rows: rows, reduceMotion: reduceMotion)
        }
    }

    /// Like `EditableWidgetView.startWobble` (Dashboard): 0.3 degrees,
    /// slightly phase-shifted, off with Reduce Motion.
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
            withAnimation(.easeOut(duration: 0.18)) { isHiding = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                editor.setCard(kind, enabled: false)
                isHiding = false
            }
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .background(.regularMaterial, in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: -11, y: -11)
        .help("Hide")
        .accessibilityLabel("Hide \(kind.title)")
    }
}

// MARK: - Quick Toggles Card

/// Like `QuickTogglesCard` (`UtilitiesView.swift`), but every tile
/// wobbles and can be selected (popover with the options), removed, and
/// moved within the grid.
private struct EditableQuickTogglesCard: View {
    let editor: ShellEditor
    let rows: [[UtilitiesToggleEntry]]
    let reduceMotion: Bool
    @Environment(\.shellStyle) private var style
    @Environment(\.dashboardRendersForScreenshot) private var rendersForScreenshot
    @State private var targeted: String?

    var body: some View {
        UtilitiesCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(UtilitiesToggleText.cardTitle)
                    .font(style.font(size: 14, weight: .medium))
                    .lineLimit(1)
                VStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 8) {
                            ForEach(row) { entry in
                                EditableToggleTile(editor: editor, entry: entry, reduceMotion: reduceMotion,
                                                   targeted: targeted == entry.id)
                                    .modifier(UtilitiesToggleDropModifier(editor: editor, target: entry.id,
                                                                          targeted: $targeted, active: !rendersForScreenshot))
                            }
                            // Short last row: empty slots like in the calm
                            // view, so the columns stay the same width.
                            ForEach(row.count..<QuickToggles.columns, id: \.self) { _ in
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: QuickToggleButton.height)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A tile during editing: like `UtilitiesEditorTile` (old Nexus editor),
/// additionally wobbling with a minus button. A click selects it (popover
/// with the options from `UtilitiesToggleOptionsView`); dragging sets its
/// identifier as the payload (`ShellEditor.moveToggle(_:onto:)` when
/// dropped on another tile, see `UtilitiesToggleDropDelegate`).
private struct EditableToggleTile: View {
    let editor: ShellEditor
    let entry: UtilitiesToggleEntry
    let reduceMotion: Bool
    let targeted: Bool
    @Environment(\.shellStyle) private var style
    @Environment(\.dashboardRendersForScreenshot) private var rendersForScreenshot
    @State private var wobble: Double = 0
    @State private var isDeleting = false

    private var phase: Double { Double(abs(entry.id.hashValue) % 260) / 1000 }
    private var isSelected: Bool { editor.selectedToggleID == entry.id }
    /// Popover only for buttons with real options (app, link, shortcut,
    /// hide apps) - for Wi-Fi and the like it only showed a title and
    /// description and was in the way on every click (live test 09/19).
    private var showsOptions: Bool {
        guard isSelected, !isDeleting else { return false }
        switch entry.kind {
        case .openApp, .openLink, .runShortcut, .hideApps: return true
        default: return false
        }
    }

    var body: some View {
        Button {
            editor.selectedToggleID = isSelected ? nil : entry.id
        } label: {
            VStack(spacing: 4) {
                UtilitiesToggleGlyph(icon: UtilitiesEditorText.icon(entry), scale: 0.88)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 12))
                Text(UtilitiesEditorText.title(entry))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay {
            let shape = RoundedRectangle(cornerRadius: 12)
            if reduceMotion {
                shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(.secondary)
            } else if isSelected {
                shape.strokeBorder(style.accent, lineWidth: 2)
            } else if targeted {
                shape.strokeBorder(style.accent.opacity(0.5), lineWidth: 2)
            }
        }
        .overlay(alignment: .topLeading) { minusBadge }
        .rotationEffect(.degrees(reduceMotion ? 0 : wobble))
        .opacity(isDeleting ? 0 : 1)
        .scaleEffect(isDeleting ? 0.6 : 1)
        .onAppear { startWobble() }
        .onChange(of: reduceMotion) { _, _ in startWobble() }
        .modifier(UtilitiesToggleDragModifier(entry: entry, active: !rendersForScreenshot))
        #if DEBUG
        .background { DebugWindowRectReporter { editor.debugUtilitiesRects[entry.id] = $0 } }
        #endif
        .help(UtilitiesEditorText.title(entry))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UtilitiesEditorText.title(entry))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .popover(isPresented: Binding(
            get: { showsOptions },
            set: { if !$0 { editor.selectedToggleID = nil } }
        ), arrowEdge: .trailing) {
            UtilitiesToggleOptionsView(editor: editor, entry: entry) { editor.selectedToggleID = nil }
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
            if isSelected { editor.selectedToggleID = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { editor.removeToggle(entry.id) }
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 18, height: 18)
                .background(.regularMaterial, in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: -8, y: -6)
        .help("Remove")
        .accessibilityLabel("Remove \(entry.kind.title)")
    }
}

// MARK: - Options of the Selected Button (Popover)

/// The same controls as `UtilitiesEditorOptions` (Nexus, before 0.2), now
/// against the working copy of the global edit mode (`ShellEditor`)
/// instead of directly against `store.settings.utilities.layout`.
struct UtilitiesToggleOptionsView: View {
    let editor: ShellEditor
    let entry: UtilitiesToggleEntry
    let onDeselect: () -> Void
    /// Via `editor.pickingShortcut` instead of view-local (task 6): Esc
    /// should be able to close the picker as the innermost element first,
    /// before it hits the popover itself (`ShellEditor.handleEscape`).

    var body: some View {
        // Shortcut picker directly in the popover instead of as a
        // `.sheet`: a sheet on a popover of a borderless, non-activating
        // panel did not appear reliably. Esc (`ShellEditor.handleEscape`)
        // and "Cancel" lead back to the options.
        if editor.pickingShortcut, case .runShortcut(let shortcut) = entry.toggle {
            UtilitiesShortcutPicker(current: shortcut, onPick: { picked in
                update(.runShortcut(with(shortcut) {
                    $0.name = picked.name
                    $0.identifier = picked.identifier
                }))
                editor.pickingShortcut = false
            }, onCancel: { editor.pickingShortcut = false })
        } else {
            Form { optionsSection }
                .formStyle(.grouped)
                .frame(width: 280)
                .frame(minHeight: 120, maxHeight: 420)
        }
    }

    private var optionsSection: some View {
        Section {
            HStack(spacing: 10) {
                UtilitiesEditorGlyphTile(icon: UtilitiesEditorText.icon(entry), tint: entry.kind.group.tint, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(UtilitiesEditorText.title(entry))
                    Text(entry.kind.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    let id = entry.id
                    onDeselect()
                    editor.removeToggle(id)
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
            }
            options
        } header: {
            Text("Button “\(UtilitiesEditorText.title(entry))”")
        }
    }

    @ViewBuilder
    private var options: some View {
        switch entry.toggle {
        case .openApp(let app):
            appRow(app)
            UtilitiesEditorField(title: "Title",
                                 prompt: BarApps.info(for: app.bundleID)?.name ?? String(localized: "App Name"),
                                 value: app.title) { title in
                update(.openApp(with(app) { $0.title = title }))
            }
            symbolRow(current: app.symbol, automatic: String(localized: "App Icon")) { symbol in
                update(.openApp(with(app) { $0.symbol = symbol }))
            }
        case .openLink(let link):
            UtilitiesEditorField(title: "Address", prompt: "example.com", value: link.url) { url in
                update(.openLink(with(link) { $0.url = url }))
            }
            if !link.url.isEmpty, UtilitiesLink.url(from: link.url) == nil {
                Label("Not a valid address – the button stays grey.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            UtilitiesEditorField(title: "Title",
                                 prompt: UtilitiesLink.url(from: link.url).map(UtilitiesLink.displayText) ?? String(localized: "Address"),
                                 value: link.title) { title in
                update(.openLink(with(link) { $0.title = title }))
            }
            symbolRow(current: link.symbol, automatic: String(localized: "Default (Link)")) { symbol in
                update(.openLink(with(link) { $0.symbol = symbol }))
            }
        case .runShortcut(let shortcut):
            shortcutRow(shortcut)
            UtilitiesEditorField(title: "Title",
                                 prompt: shortcut.name.isEmpty ? String(localized: "Shortcut Name") : shortcut.name,
                                 value: shortcut.title) { title in
                update(.runShortcut(with(shortcut) { $0.title = title }))
            }
            symbolRow(current: shortcut.symbol, automatic: String(localized: "Default (Shortcuts)")) { symbol in
                update(.runShortcut(with(shortcut) { $0.symbol = symbol }))
            }
        case .hideApps(let options):
            NexusToggle(title: "Leave Frontmost App", subtitle: "Like ⌥⌘H: only hide the others",
                        isOn: Binding(get: { options.keepFrontmost },
                                      set: { on in update(.hideApps(.init(keepFrontmost: on))) }))
        default:
            Text("No options – the button always does the same thing.")
                .foregroundStyle(.secondary)
        }
    }

    private func appRow(_ app: UtilitiesAppOptions) -> some View {
        NexusAppChoiceRow(bundleID: app.bundleID) { id in
            update(.openApp(with(app) { $0.bundleID = id }))
        }
    }

    private func shortcutRow(_ shortcut: UtilitiesShortcutOptions) -> some View {
        HStack(spacing: 10) {
            Image(systemName: UtilitiesShortcutOptions.fallbackSymbol)
                .foregroundStyle(.secondary)
            Text(shortcut.name.isEmpty ? String(localized: "No Shortcut Chosen Yet") : shortcut.name)
                .foregroundStyle(shortcut.name.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Choose Shortcut…") { editor.pickingShortcut = true }
        }
    }

    private func symbolRow(current: String, automatic: String, onPick: @escaping (String) -> Void) -> some View {
        UtilitiesEditorSymbolRow(current: current, automatic: automatic, fallback: UtilitiesEditorText.icon(entry),
                                 onPick: onPick)
    }

    private func update(_ toggle: UtilitiesToggle) {
        editor.updateToggle(entry.id, to: toggle)
    }

    private func with<T>(_ value: T, _ change: (inout T) -> Void) -> T {
        var copy = value
        change(&copy)
        return copy
    }
}

// MARK: - Drag and Drop

/// Dragging an existing tile: the payload is its identifier (no prefix,
/// unlike `UtilitiesToggleDragPayload` from the gallery - this is how the
/// receiver tells "new button" apart from "existing, moved").
private struct UtilitiesToggleDragModifier: ViewModifier {
    let entry: UtilitiesToggleEntry
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrag { NSItemProvider(object: entry.id as NSString) }
        } else {
            content
        }
    }
}

private struct UtilitiesToggleDropModifier: ViewModifier {
    let editor: ShellEditor
    let target: String
    @Binding var targeted: String?
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrop(of: [.plainText], delegate: UtilitiesToggleDropDelegate(editor: editor, target: target, targeted: $targeted))
        } else {
            content
        }
    }
}

/// Target a tile: from the gallery a new button (to the end, like a
/// click), from another tile its spot (`moveToggle(_:onto:)`).
private struct UtilitiesToggleDropDelegate: DropDelegate {
    let editor: ShellEditor
    let target: String
    @Binding var targeted: String?

    func dropEntered(info: DropInfo) { targeted = target }
    func dropExited(info: DropInfo) { if targeted == target { targeted = nil } }

    func performDrop(info: DropInfo) -> Bool {
        targeted = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let string = value as? String else { return }
            DispatchQueue.main.async {
                if let kind = UtilitiesToggleDragPayload.kind(from: string) {
                    editor.addToggle(kind)
                } else if editor.utilities?.layout[toggle: string] != nil {
                    editor.moveToggle(string, onto: target)
                }
            }
        }
        return true
    }
}

/// Dragging a card: the payload is its raw value (likewise without a
/// prefix, unlike `UtilitiesCardDragPayload` from the gallery).
private struct UtilitiesCardDragModifier: ViewModifier {
    let kind: UtilitiesCardKind
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrag { NSItemProvider(object: kind.rawValue as NSString) }
        } else {
            content
        }
    }
}

private struct UtilitiesCardDropModifier: ViewModifier {
    let editor: ShellEditor
    let target: UtilitiesCardKind
    @Binding var targeted: Bool
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrop(of: [.plainText], delegate: UtilitiesCardDropDelegate(editor: editor, target: target, targeted: $targeted))
        } else {
            content
        }
    }
}

/// Target a card: from the gallery, a disabled card turns back on (stays
/// in its place); from another card, its spot - like SwiftUI's `onMove`
/// (target counted before the move, `moveCards` computes the same way).
///
/// `validateDrop` only accepts plain text (tiles and tile payloads are
/// all `.plainText`) - a sharper check for card vs. quick toggle needs
/// the loaded string, which `NSItemProvider` only delivers asynchronously,
/// while `validateDrop` has to decide synchronously. `performDrop`
/// therefore recognizes all three cases itself: a tile from the gallery,
/// an existing card to move - and a quick toggle that was dropped
/// somewhere on a card instead of its own tile (`editor.addToggle`, the
/// same effect as a click in the gallery). Previously `performDrop`
/// always returned `true`, even when neither of the first two branches
/// matched - a quick toggle dropped that way used to vanish without
/// a trace.
private struct UtilitiesCardDropDelegate: DropDelegate {
    let editor: ShellEditor
    let target: UtilitiesCardKind
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let string = value as? String else { return }
            DispatchQueue.main.async {
                if let kind = UtilitiesCardDragPayload.kind(from: string) {
                    editor.setCard(kind, enabled: true)
                } else if let source = UtilitiesCardKind(rawValue: string), source != target,
                          let cards = editor.utilities?.layout.cards,
                          let sourceIndex = cards.firstIndex(where: { $0.kind == source }),
                          let targetIndex = cards.firstIndex(where: { $0.kind == target }) {
                    let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
                    editor.moveUtilitiesCards(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
                } else if let kind = UtilitiesToggleDragPayload.kind(from: string) {
                    // A new quick toggle from the gallery, dropped on a
                    // card instead of a tile: the same effect as a click
                    // in the gallery, instead of vanishing without a trace.
                    editor.addToggle(kind)
                }
            }
        }
        return true
    }
}

/// Safety net across the whole panel (task 5: "Drop target for gallery
/// payloads"): a button dragged out of the gallery, or a card that does
/// not land exactly on a tile, still gets through. Moving existing tiles
/// needs an exact target and stays reserved for the tiles' own targets.
private struct UtilitiesPanelDropModifier: ViewModifier {
    let editor: ShellEditor
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrop(of: [.plainText], delegate: UtilitiesPanelDropDelegate(editor: editor))
        } else {
            content
        }
    }
}

private struct UtilitiesPanelDropDelegate: DropDelegate {
    let editor: ShellEditor

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let string = value as? String else { return }
            DispatchQueue.main.async {
                if let kind = UtilitiesToggleDragPayload.kind(from: string) {
                    editor.addToggle(kind)
                } else if let kind = UtilitiesCardDragPayload.kind(from: string) {
                    editor.setCard(kind, enabled: true)
                }
            }
        }
        return true
    }
}
