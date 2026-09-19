import ApolloShellCore
import SwiftUI
import UniformTypeIdentifiers

// Bearbeitungsflaeche des Kontrollzentrums im globalen Bearbeitungsmodus
// (design/2026-09-18-bento-dashboard.md Abschnitt 5, design/2026-09-19-
// shell-edit-plan.md Task 5): Karten und Schnellschalter wackeln, lassen sich
// waehlen, entfernen und ziehen; die Optionen des gewaehlten Knopfs erscheinen
// im Popover (dieselben Regler wie im alten Nexus-Editor,
// `UtilitiesEditorOptions.swift`). `UtilitiesPanel.swift` zeigt diese
// Bausteine nur, waehrend `editor.isEditing` gilt - die ruhige Ansicht
// (`UtilitiesView`) bleibt unveraendert (Bildvergleich).

/// Wurzel im Kantenfenster waehrend der Bearbeitung. `layout` ist die
/// Arbeitskopie (`editor.utilities.layout`) - eigener Parameter statt ueber
/// `editor` gelesen, damit die Karten unten dieselbe Anordnung sehen wie das
/// Fenstermass (`UtilitiesPanel.apply`).
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
        // Auffangnetz: ein aus der Galerie gezogener Knopf oder eine Karte,
        // die nicht genau auf einer Kachel landet (Luecke, leere Karte),
        // kommt trotzdem an (ans Ende bzw. an).
        .modifier(UtilitiesPanelDropModifier(editor: editor, active: !rendersForScreenshot))
    }
}

// MARK: - Karte

/// Eine Karte waehrend der Bearbeitung: Inhalt abgeschaltet (Regler und
/// Knoepfe darin tun nichts), wackelt, laesst sich ausblenden (Minus) und
/// vertikal auf eine andere Karte ziehen (`ShellEditor.moveUtilitiesCards`).
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

    /// Verschiedene Phasen wie beim Dashboard: die drei Karten wackeln nicht
    /// im Gleichtakt.
    private var phase: Double { Double(abs(kind.hashValue) % 260) / 1000 }

    var body: some View {
        content
            // Nur Wach-halten- und Audio-Karte stumm schalten (deren Regler
            // sollen beim Bearbeiten nichts ausloesen). Die Schnellschalter-
            // Karte besteht beim Bearbeiten selbst aus bearbeitbaren Kacheln -
            // vorher galt `allowsHitTesting(false)` auch fuer sie, und keine
            // Kachel liess sich antippen, entfernen oder verschieben
            // (Selbsttest 19.09.).
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

    /// Wie `EditableWidgetView.startWobble` (Dashboard): 0.3 Grad, leicht
    /// phasenversetzt, aus bei Reduce Motion.
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
        .help("Ausblenden")
        .accessibilityLabel("\(kind.title) ausblenden")
    }
}

// MARK: - Schnellschalter-Karte

/// Wie `QuickTogglesCard` (`UtilitiesView.swift`), aber jede Kachel wackelt,
/// laesst sich waehlen (Popover mit den Optionen), entfernen und im Raster
/// verschieben.
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
                            // Kurze letzte Reihe: leere Plaetze wie in der
                            // ruhigen Ansicht, damit die Spalten gleich breit
                            // bleiben.
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

/// Eine Kachel waehrend der Bearbeitung: wie `UtilitiesEditorTile` (alter
/// Nexus-Editor), zusaetzlich wackelnd mit Minus-Knopf. Ein Klick waehlt
/// (Popover mit den Optionen aus `UtilitiesToggleOptionsView`); Ziehen setzt
/// die Kennung als Nutzlast (`ShellEditor.moveToggle(_:onto:)` beim Ablegen
/// auf einer anderen Kachel, siehe `UtilitiesToggleDropDelegate`).
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
    /// Popover nur fuer Knoepfe mit echten Optionen (App, Link, Kurzbefehl,
    /// Apps ausblenden) - bei WLAN & Co. zeigte es nur Titel und
    /// Beschreibung und stand bei jedem Klick im Weg (Live-Test 19.09.).
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
        .help("Entfernen")
        .accessibilityLabel("\(entry.kind.title) entfernen")
    }
}

// MARK: - Optionen des gewaehlten Knopfs (Popover)

/// Dieselben Regler wie `UtilitiesEditorOptions` (Nexus, vor 0.2), jetzt
/// gegen die Arbeitskopie des globalen Bearbeitungsmodus (`ShellEditor`)
/// statt direkt gegen `store.settings.utilities.layout`.
struct UtilitiesToggleOptionsView: View {
    let editor: ShellEditor
    let entry: UtilitiesToggleEntry
    let onDeselect: () -> Void
    /// Auf `editor.pickingShortcut` statt View-lokal (Task 6): Esc soll den
    /// Picker als innerstes Element zuerst schliessen koennen, bevor es das
    /// Popover selbst trifft (`ShellEditor.handleEscape`).

    var body: some View {
        // Kurzbefehl-Auswahl direkt im Popover statt als `.sheet`: ein Sheet
        // an einem Popover eines randlosen, nicht aktivierenden Panels
        // erschien nicht verlaesslich. Esc (`ShellEditor.handleEscape`) und
        // „Abbrechen“ fuehren zurueck zu den Optionen.
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
                    Label("Entfernen", systemImage: "minus.circle")
                }
            }
            options
        } header: {
            Text("Knopf „\(UtilitiesEditorText.title(entry))“")
        }
    }

    @ViewBuilder
    private var options: some View {
        switch entry.toggle {
        case .openApp(let app):
            appRow(app)
            UtilitiesEditorField(title: "Titel",
                                 prompt: BarApps.info(for: app.bundleID)?.name ?? String(localized: "Name der App"),
                                 value: app.title) { title in
                update(.openApp(with(app) { $0.title = title }))
            }
            symbolRow(current: app.symbol, automatic: String(localized: "Symbol der App")) { symbol in
                update(.openApp(with(app) { $0.symbol = symbol }))
            }
        case .openLink(let link):
            UtilitiesEditorField(title: "Adresse", prompt: "example.com", value: link.url) { url in
                update(.openLink(with(link) { $0.url = url }))
            }
            if !link.url.isEmpty, UtilitiesLink.url(from: link.url) == nil {
                Label("Keine gültige Adresse – der Knopf bleibt grau.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            UtilitiesEditorField(title: "Titel",
                                 prompt: UtilitiesLink.url(from: link.url).map(UtilitiesLink.displayText) ?? String(localized: "Adresse"),
                                 value: link.title) { title in
                update(.openLink(with(link) { $0.title = title }))
            }
            symbolRow(current: link.symbol, automatic: String(localized: "Standard (Link)")) { symbol in
                update(.openLink(with(link) { $0.symbol = symbol }))
            }
        case .runShortcut(let shortcut):
            shortcutRow(shortcut)
            UtilitiesEditorField(title: "Titel",
                                 prompt: shortcut.name.isEmpty ? String(localized: "Name des Kurzbefehls") : shortcut.name,
                                 value: shortcut.title) { title in
                update(.runShortcut(with(shortcut) { $0.title = title }))
            }
            symbolRow(current: shortcut.symbol, automatic: String(localized: "Standard (Kurzbefehle)")) { symbol in
                update(.runShortcut(with(shortcut) { $0.symbol = symbol }))
            }
        case .hideApps(let options):
            NexusToggle(title: "Vordere App stehen lassen", subtitle: "Wie ⌥⌘H: nur die anderen ausblenden",
                        isOn: Binding(get: { options.keepFrontmost },
                                      set: { on in update(.hideApps(.init(keepFrontmost: on))) }))
        default:
            Text("Keine Optionen – der Knopf tut immer dasselbe.")
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
            Text(shortcut.name.isEmpty ? String(localized: "Noch kein Kurzbefehl gewählt") : shortcut.name)
                .foregroundStyle(shortcut.name.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Kurzbefehl wählen …") { editor.pickingShortcut = true }
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

// MARK: - Ziehen und Ablegen

/// Ziehen einer bestehenden Kachel: die Nutzlast ist ihre Kennung (kein
/// Praefix, anders als `UtilitiesToggleDragPayload` aus der Galerie - so
/// unterscheidet der Empfaenger "neuer Knopf" von "bestehender, verschoben").
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

/// Ziel eine Kachel: aus der Galerie ein neuer Knopf (ans Ende, wie ein
/// Klick), von einer anderen Kachel deren Platz (`moveToggle(_:onto:)`).
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

/// Ziehen einer Karte: Nutzlast ist ihr Rohwert (ebenfalls ohne Praefix,
/// anders als `UtilitiesCardDragPayload` aus der Galerie).
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

/// Ziel eine Karte: aus der Galerie eine ausgeschaltete Karte wieder an
/// (bleibt an ihrem Platz), von einer anderen Karte ihr Platz - wie
/// SwiftUIs `onMove` (Ziel vor dem Verschieben gezaehlt, `moveCards`
/// rechnet genauso).
///
/// `validateDrop` nimmt nur reinen Text an (Kacheln und Kacheln-Nutzlasten
/// sind alle `.plainText`) - eine schaerfere Prüfung nach Karte/Schnellschalter
/// braucht die geladene Zeichenkette, die `NSItemProvider` erst asynchron
/// liefert, `validateDrop` aber synchron entscheiden muss. `performDrop`
/// erkennt darum selbst alle drei Faelle: eine Kachel aus der Galerie, eine
/// bestehende Karte zum Verschieben - und einen Schnellschalter, der
/// irgendwo auf einer Karte statt einer eigenen Kachel losgelassen wurde
/// (`editor.addToggle`, dieselbe Wirkung wie ein Klick in der Galerie).
/// Vorher gab `performDrop` immer `true` zurueck, auch wenn keiner der ersten
/// beiden Zweige traf - ein so abgelegter Schnellschalter verschwand darum
/// wortlos.
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
                    // Ein neuer Schnellschalter aus der Galerie, auf einer
                    // Karte statt einer Kachel abgelegt: dieselbe Wirkung wie
                    // ein Klick in der Galerie, statt spurlos zu verschwinden.
                    editor.addToggle(kind)
                }
            }
        }
        return true
    }
}

/// Auffangnetz auf dem ganzen Panel (Task 5: "Drop target for gallery
/// payloads"): ein aus der Galerie gezogener Knopf oder eine Karte, die
/// nicht genau auf einer Kachel landet, kommt trotzdem an. Verschieben
/// bestehender Kacheln braucht ein genaues Ziel und bleibt den
/// Kachel-eigenen Zielen vorbehalten.
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
