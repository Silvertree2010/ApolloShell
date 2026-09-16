import AppKit
import ApolloShellCore
import SwiftUI

// MARK: - Seite

/// Nexus > Schnellaktionen: das Utilities-Panel als Baukasten, gebaut wie
/// Nexus > Leiste. Links die Karten (ein/aus, ziehen), das Raster der
/// Schnellschalter (ziehen, +, Optionen des gewaehlten Knopfs) und die
/// Vorlagen; rechts das echte Panel (`UtilitiesView`) mit Vorschau-Modell,
/// verkleinert. Jede Aenderung gilt sofort im Panel und landet in
/// settings.json.
struct UtilitiesEditorPage: View {
    @Bindable var store: ShellSettingsStore
    @State private var showsGallery = false
    @State private var pending: UtilitiesEditorReplacement?
    /// Gewaehlter Knopf nach Kennung: seine Optionen stehen unter dem Raster.
    @State private var selection: String?
    /// Liegt die Regel ohne Passwort fuer den Deckel-Teil auf diesem Mac?
    @State private var lidRuleInstalled = false
    @State private var removingLidRule = false

    /// `selection`: schon gewaehlter Knopf (Bildprobe).
    init(store: ShellSettingsStore, selection: String? = nil) {
        _store = Bindable(store)
        _selection = State(initialValue: selection)
    }

    private var layout: UtilitiesLayout { store.settings.utilities.layout }

    var body: some View {
        HStack(spacing: 0) {
            NexusPageForm(page: .utilities) {
                cardsSection
                keepAwakeSection
                togglesSection
                if let id = selection, let entry = layout[toggle: id] {
                    UtilitiesEditorOptions(store: store, entry: entry) { selection = nil }
                        // Anderer Knopf: frische Textfelder, nicht die Entwuerfe des vorigen.
                        .id(entry.id)
                }
                presetsSection
                NexusSaveWarning(failed: store.saveFailed)
            }
            Divider()
            UtilitiesEditorPreview(store: store)
                .frame(width: 236)
        }
        .sheet(isPresented: $showsGallery) {
            UtilitiesEditorGallery(layout: layout, onAdd: add, onCancel: { showsGallery = false })
        }
        .alert(pending?.title ?? "", isPresented: confirming, presenting: pending) { replacement in
            Button(replacement.confirm) { apply(replacement) }
            Button("Abbrechen", role: .cancel) {}
        } message: { replacement in
            Text(replacement.message)
        }
    }

    private var cardsSection: some View {
        Section {
            ForEach(Array(layout.cards.enumerated()), id: \.element.id) { index, card in
                UtilitiesEditorCardRow(store: store, card: card, isFirst: index == 0,
                                       isLast: index == layout.cards.count - 1)
            }
            .onMove { store.settings.utilities.layout.moveCards(fromOffsets: $0, toOffset: $1) }
        } header: {
            Text("Karten")
        } footer: {
            Text("Von oben nach unten wie im Panel. Zum Umsortieren ziehen. Ausgeschaltete Karten verschwinden, das Panel wird entsprechend niedriger.")
        }
    }

    /// Der Deckel-Teil braucht root (pmset disablesleep). Beim ersten
    /// Einschalten fragt macOS einmal nach einem Administrator und legt dabei
    /// die Regel ohne Passwort an - das soll man vorher lesen koennen, und
    /// man soll sie hier wieder loswerden.
    private var keepAwakeSection: some View {
        Section {
            NexusToggle(title: "Auch bei zugeklapptem Deckel",
                        subtitle: "Solange „Wach halten“ läuft, schläft der Mac auch zugeklappt nicht",
                        isOn: $store.settings.keepAwake.lidClosed)
            if lidRuleInstalled {
                LabeledContent {
                    Button("Entfernen …") { removeLidRule() }
                        .disabled(removingLidRule)
                } label: {
                    Text("Regel ohne Passwort")
                    Text("Erlaubt nur, diesen Ruhezustand ohne Passwort umzuschalten")
                }
            }
        } header: {
            Text("Wach halten")
        } footer: {
            Text("Braucht einmal Administratorrechte: Beim ersten Einschalten fragt macOS nach dem Passwort, und ApolloShell legt eine Regel an, die nur das Umschalten dieses Ruhezustands ohne Passwort erlaubt. Danach fragt niemand mehr. Wer ablehnt, bekommt „Wach halten“ nur aufgeklappt. Im Akkubetrieb endet es bei \(LidAwake.batteryFloor) % von selbst.")
        }
        // Die Regel entsteht im Hintergrund, sobald die Frage beantwortet
        // ist; solange die Seite offen ist, alle 2 s nachsehen (ein stat).
        .task {
            while !Task.isCancelled {
                lidRuleInstalled = LidAwakeRule.isInstalled
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func removeLidRule() {
        removingLidRule = true
        LidAwakeRule.remove { _ in
            removingLidRule = false
            lidRuleInstalled = LidAwakeRule.isInstalled
        }
    }

    private var togglesSection: some View {
        Section {
            UtilitiesEditorGrid(store: store, selection: $selection) { showsGallery = true }
            HStack(spacing: 8) {
                Button {
                    showsGallery = true
                } label: {
                    Label("Hinzufügen …", systemImage: "plus")
                }
                Spacer(minLength: 8)
                Text(UtilitiesEditorText.count(layout))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Schnellschalter")
        } footer: {
            Text("Fünf pro Reihe wie im Panel, jede Reihe macht es 56 pt höher. Zum Umsortieren einen Knopf auf einen anderen ziehen; ein Klick wählt ihn zum Einstellen, das Kontextmenü verschiebt oder entfernt.")
        }
    }

    private var presetsSection: some View {
        Section {
            HStack(spacing: 8) {
                Menu("Vorlage laden …") {
                    ForEach(UtilitiesPreset.allCases) { preset in
                        Button(preset.title) { pending = .preset(preset) }
                    }
                }
                .fixedSize()
                Spacer(minLength: 8)
                Button("Zurücksetzen") { pending = .reset }
                    .disabled(layout == UtilitiesPreset.standard.layout)
            }
        } header: {
            Text("Vorlagen")
        } footer: {
            Text("Eine Vorlage ersetzt Karten und Schnellschalter. „Standard“ ist das Panel, wie es am Anfang war.")
        }
    }

    private var confirming: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    /// Aus der Galerie: ans Ende und gleich gewaehlt - bei App, Link und
    /// Kurzbefehl muss man ja noch das Ziel waehlen.
    private func add(_ kind: UtilitiesToggleKind) {
        showsGallery = false
        if let id = store.settings.utilities.layout.add(kind) {
            selection = id
        }
    }

    private func apply(_ replacement: UtilitiesEditorReplacement) {
        store.settings.utilities.layout = replacement.layout
        selection = nil
    }
}

/// Was nach Rueckfrage das ganze Panel ersetzt.
private enum UtilitiesEditorReplacement {
    case preset(UtilitiesPreset)
    case reset

    var layout: UtilitiesLayout {
        switch self {
        case .preset(let preset): preset.layout
        case .reset: UtilitiesPreset.standard.layout
        }
    }

    var title: String {
        switch self {
        case .preset(let preset): String(localized: "Vorlage „\(preset.title)“ laden?")
        case .reset: String(localized: "Schnellaktionen zurücksetzen?")
        }
    }

    var message: String {
        switch self {
        case .preset(let preset): String(localized: "\(preset.summary) Die jetzige Anordnung wird ersetzt.")
        case .reset: String(localized: "Das Panel sieht wieder aus wie am Anfang (Vorlage Standard). Die jetzige Anordnung wird ersetzt.")
        }
    }

    var confirm: String {
        switch self {
        case .preset: String(localized: "Laden")
        case .reset: String(localized: "Zurücksetzen")
        }
    }
}

// MARK: - Karten

/// Kachel, Name, eine Zeile, Schalter, Griff. Kontextmenue "Nach oben/unten"
/// fuer alle, die nicht ziehen wollen; dasselbe als Bedienungshilfen-Aktion.
private struct UtilitiesEditorCardRow: View {
    @Bindable var store: ShellSettingsStore
    let card: UtilitiesCardEntry
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: 10) {
            NexusTile(symbol: card.kind.symbol, tint: card.kind.tint, size: 24)
                .opacity(card.enabled ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.kind.title)
                Text(card.kind.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle(card.kind.title, isOn: enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        // Wie die Zeilen ohne Optionen in Nexus > Leiste eingerueckt.
        .padding(.leading, 11.5)
        .padding(.trailing, 4)
        .contentShape(.rect)
        .contextMenu {
            Button("Nach oben") { store.settings.utilities.layout.moveCard(card.kind, by: -1) }
                .disabled(isFirst)
            Button("Nach unten") { store.settings.utilities.layout.moveCard(card.kind, by: 1) }
                .disabled(isLast)
        }
        .accessibilityAction(named: "Nach oben") { store.settings.utilities.layout.moveCard(card.kind, by: -1) }
        .accessibilityAction(named: "Nach unten") { store.settings.utilities.layout.moveCard(card.kind, by: 1) }
    }

    private var enabled: Binding<Bool> {
        let kind = card.kind
        let store = store
        return Binding(get: { store.settings.utilities.layout.isEnabled(kind) },
                       set: { store.settings.utilities.layout.setCard(kind, enabled: $0) })
    }
}

// MARK: - Raster

/// Die Knoepfe fuenf pro Reihe wie im Panel, am Ende das +. Ziehen legt
/// einen Knopf auf den Platz eines anderen (`UtilitiesLayout.moveToggle
/// (_:onto:)`), auf das + ans Ende.
///
/// Warum `draggable`/`dropDestination` statt Umsortieren waehrend des
/// Ziehens (DropDelegate): dort bliebe nach einem abgebrochenen Ziehen der
/// gemerkte Knopf haengen, und fremder Text aus einer anderen App liesse ihn
/// wandern. Hier traegt der Zug die Kennung selbst; das Ziel leuchtet, der
/// Rest rueckt beim Loslassen nach.
private struct UtilitiesEditorGrid: View {
    @Bindable var store: ShellSettingsStore
    @Binding var selection: String?
    let onAdd: () -> Void
    @State private var targeted: String?

    /// Kennung des +-Felds als Ziel.
    private static let endTarget = "\u{0}end"

    var body: some View {
        let toggles = store.settings.utilities.layout.toggles
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: QuickToggles.columns),
                  alignment: .leading, spacing: 10) {
            ForEach(Array(toggles.enumerated()), id: \.element.id) { index, entry in
                UtilitiesEditorTile(entry: entry, selected: selection == entry.id, targeted: targeted == entry.id)
                    .onTapGesture { selection = selection == entry.id ? nil : entry.id }
                    .draggable(entry.id) {
                        UtilitiesEditorTile(entry: entry, selected: false, targeted: false)
                            .frame(width: 58)
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        drop(ids, onto: entry.id)
                    } isTargeted: { over in
                        targeted = over ? entry.id : (targeted == entry.id ? nil : targeted)
                    }
                    .contextMenu {
                        Button("Nach vorne") { store.settings.utilities.layout.moveToggle(entry.id, by: -1) }
                            .disabled(index == 0)
                        Button("Nach hinten") { store.settings.utilities.layout.moveToggle(entry.id, by: 1) }
                            .disabled(index == toggles.count - 1)
                        Divider()
                        Button("Entfernen", role: .destructive) { remove(entry.id) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(UtilitiesEditorText.title(entry))
                    .accessibilityAddTraits(selection == entry.id ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { selection = entry.id }
                    .accessibilityAction(named: "Nach vorne") { store.settings.utilities.layout.moveToggle(entry.id, by: -1) }
                    .accessibilityAction(named: "Nach hinten") { store.settings.utilities.layout.moveToggle(entry.id, by: 1) }
                    .accessibilityAction(named: "Entfernen") { remove(entry.id) }
            }
            UtilitiesEditorAddTile(targeted: targeted == Self.endTarget, action: onAdd)
                .dropDestination(for: String.self) { ids, _ in
                    drop(ids, onto: nil)
                } isTargeted: { over in
                    targeted = over ? Self.endTarget : (targeted == Self.endTarget ? nil : targeted)
                }
        }
        .padding(.vertical, 4)
        .animation(.snappy(duration: 0.25), value: toggles.map(\.id))
    }

    /// Nur Kennungen aus diesem Raster zaehlen - fremder Text, der
    /// zufaellig hierher gezogen wird, bewegt nichts.
    private func drop(_ ids: [String], onto target: String?) -> Bool {
        targeted = nil
        guard let id = ids.first, store.settings.utilities.layout[toggle: id] != nil else { return false }
        if let target {
            store.settings.utilities.layout.moveToggle(id, onto: target)
        } else if let index = store.settings.utilities.layout.toggles.firstIndex(where: { $0.id == id }) {
            let count = store.settings.utilities.layout.toggles.count
            store.settings.utilities.layout.moveToggles(fromOffsets: IndexSet(integer: index), toOffset: count)
        }
        return true
    }

    private func remove(_ id: String) {
        if selection == id { selection = nil }
        store.settings.utilities.layout.remove(toggle: id)
    }
}

/// Ein Knopf im Raster: dieselbe Flaeche wie im Panel (aus), darunter sein
/// Name. Gewaehlt mit Rand in Akzentfarbe.
private struct UtilitiesEditorTile: View {
    let entry: UtilitiesToggleEntry
    let selected: Bool
    let targeted: Bool

    var body: some View {
        VStack(spacing: 4) {
            UtilitiesToggleGlyph(icon: UtilitiesEditorText.icon(entry), scale: 0.88)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.primary.opacity(targeted ? 0.16 : 0.08), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor.opacity(selected ? 1 : targeted ? 0.5 : 0), lineWidth: 2)
                }
            // Verkleinern statt abschneiden: "Bildschirm…" hiesse sonst
            // sowohl Bildschirmfoto als auch Bildschirm aus (Bildprobe 14.09.).
            Text(UtilitiesEditorText.title(entry))
                .font(.caption2)
                .foregroundStyle(selected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
        }
        .contentShape(.rect)
        .help(UtilitiesEditorText.title(entry))
    }
}

/// Das + am Ende des Rasters: gestrichelt, oeffnet die Galerie.
private struct UtilitiesEditorAddTile: View {
    let targeted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(targeted ? Color.accentColor : Color.primary.opacity(0.25))
                    }
                Text("Hinzufügen")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Knopf hinzufügen")
    }
}

// MARK: - Optionen eines Knopfs

/// Unter dem Raster: welcher Knopf gewaehlt ist, Entfernen, und - bei App,
/// Link, Kurzbefehl, Apps ausblenden - seine Optionen. Jede Aenderung
/// ersetzt die Optionen dieses einen Knopfs (`UtilitiesLayout.update`).
private struct UtilitiesEditorOptions: View {
    @Bindable var store: ShellSettingsStore
    let entry: UtilitiesToggleEntry
    let onDeselect: () -> Void
    @State private var picksApp = false
    @State private var picksShortcut = false

    var body: some View {
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
                    store.settings.utilities.layout.remove(toggle: id)
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
        HStack(spacing: 10) {
            if let info = BarApps.info(for: app.bundleID) {
                Image(nsImage: info.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                Text(info.name)
            } else {
                Text(app.bundleID.isEmpty ? String(localized: "Noch keine App gewählt")
                     : String(localized: "\(app.bundleID) ist nicht installiert"))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("App wählen …") { picksApp = true }
        }
        .sheet(isPresented: $picksApp) {
            NexusBarAppPicker(current: app.bundleID, onPick: { id in
                update(.openApp(with(app) { $0.bundleID = id }))
                picksApp = false
            }, onCancel: { picksApp = false })
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
            Button("Kurzbefehl wählen …") { picksShortcut = true }
        }
        .sheet(isPresented: $picksShortcut) {
            UtilitiesShortcutPicker(current: shortcut, onPick: { picked in
                update(.runShortcut(with(shortcut) {
                    $0.name = picked.name
                    $0.identifier = picked.identifier
                }))
                picksShortcut = false
            }, onCancel: { picksShortcut = false })
        }
    }

    private func symbolRow(current: String, automatic: String, onPick: @escaping (String) -> Void) -> some View {
        UtilitiesEditorSymbolRow(current: current, automatic: automatic, fallback: UtilitiesEditorText.icon(entry),
                                 onPick: onPick)
    }

    private func update(_ toggle: UtilitiesToggle) {
        store.settings.utilities.layout.update(toggle: entry.id, to: toggle)
    }

    private func with<T>(_ value: T, _ change: (inout T) -> Void) -> T {
        var copy = value
        change(&copy)
        return copy
    }
}

/// Textfeld, das erst beim Bestaetigen (Return) oder beim Verlassen
/// schreibt - nicht bei jedem Tastendruck settings.json, und das Panel
/// zeichnet nicht jeden halben Link neu.
private struct UtilitiesEditorField: View {
    let title: LocalizedStringKey
    let prompt: String
    let value: String
    let onCommit: (String) -> Void
    @State private var draft: String
    @FocusState private var focused: Bool

    init(title: LocalizedStringKey, prompt: String, value: String, onCommit: @escaping (String) -> Void) {
        self.title = title
        self.prompt = prompt
        self.value = value
        self.onCommit = onCommit
        _draft = State(initialValue: value)
    }

    var body: some View {
        TextField(title, text: $draft, prompt: Text(prompt))
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, now in
                if !now { commit() }
            }
            .onChange(of: value) { _, new in
                if !focused { draft = new }
            }
            .onDisappear(perform: commit)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != value { onCommit(trimmed) }
    }
}

/// "Symbol": das jetzige, daneben "Wählen …" mit der kleinen Auswahl.
private struct UtilitiesEditorSymbolRow: View {
    let current: String
    let automatic: String
    let fallback: UtilitiesToggleItem.Icon
    let onPick: (String) -> Void
    @State private var picking = false

    var body: some View {
        LabeledContent("Symbol") {
            HStack(spacing: 8) {
                UtilitiesToggleGlyph(icon: fallback, scale: 0.8)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                Text(current.isEmpty ? automatic : current)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Wählen …") { picking = true }
                    .popover(isPresented: $picking, arrowEdge: .trailing) {
                        UtilitiesSymbolPicker(current: current, automatic: automatic) { symbol in
                            onPick(symbol)
                            picking = false
                        }
                    }
            }
        }
    }
}

/// Die kleine Symbolauswahl: "automatisch", die Liste aus
/// `UtilitiesSymbols` (nur die, die es auf diesem macOS gibt) und ein Feld
/// fuer jeden anderen SF-Symbol-Namen - der wird erst angenommen, wenn es
/// ihn gibt.
struct UtilitiesSymbolPicker: View {
    let current: String
    let automatic: String
    let onPick: (String) -> Void
    @State private var custom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onPick("")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .opacity(current.isEmpty ? 1 : 0)
                    Text(automatic)
                }
            }
            .buttonStyle(.plain)
            // `Grid` statt `LazyVGrid`: die faule Fassung schaetzte ihre Hoehe
            // auf ueber 1000 pt (Bildprobe 14.09.) - das Popover waere so
            // hoch geworden. 48 Symbole zeichnet man auch ohne Faulheit.
            let symbols = UtilitiesSymbols.choices.filter(UtilitiesSymbolCheck.exists)
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Array(stride(from: 0, to: symbols.count, by: Self.columns)), id: \.self) { start in
                    GridRow {
                        ForEach(symbols[start..<min(start + Self.columns, symbols.count)], id: \.self) { name in
                            symbolButton(name)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("Eigenes Symbol", text: $custom, prompt: Text("SF-Symbol-Name"))
                    .onSubmit(takeCustom)
                Button("Übernehmen", action: takeCustom)
                    .disabled(!UtilitiesSymbolCheck.exists(custom.trimmingCharacters(in: .whitespaces)))
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private static let columns = 8

    private func symbolButton(_ name: String) -> some View {
        Button {
            onPick(name)
        } label: {
            Image(systemName: name)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .background(name == current ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.06),
                            in: .rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private func takeCustom() {
        let name = custom.trimmingCharacters(in: .whitespaces)
        guard UtilitiesSymbolCheck.exists(name) else { return }
        onPick(name)
    }
}

// MARK: - Kurzbefehl waehlen

/// Die Kurzbefehle des Benutzers mit Suche. Liest beim Oeffnen nur die Liste
/// (`UtilitiesShortcutCatalog`); ausgefuehrt wird hier nichts.
struct UtilitiesShortcutPicker: View {
    let current: UtilitiesShortcutOptions
    let onPick: (UtilitiesShortcut) -> Void
    let onCancel: () -> Void
    @State private var query = ""
    /// `nil`: wird noch gelesen.
    @State private var shortcuts: [UtilitiesShortcut]?

    /// `shortcuts` vorgegeben (Bildprobe): kein Einlesen.
    init(current: UtilitiesShortcutOptions, shortcuts: [UtilitiesShortcut]? = nil,
         onPick: @escaping (UtilitiesShortcut) -> Void, onCancel: @escaping () -> Void) {
        self.current = current
        self.onPick = onPick
        self.onCancel = onCancel
        _shortcuts = State(initialValue: shortcuts)
    }

    private var results: [UtilitiesShortcut] {
        let all = shortcuts ?? []
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        let matcher = FuzzyMatcher()
        return all.compactMap { shortcut in matcher.score(q, in: shortcut.name).map { (shortcut, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Kurzbefehl wählen")
                    .font(.headline)
                Text("Aus der Kurzbefehle-App. Ausgeführt wird er erst beim Klick im Panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 10)
            NexusSearchField(prompt: "Kurzbefehl suchen", text: $query)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            Divider()
            Group {
                if shortcuts == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    Text(query.isEmpty ? String(localized: "Keine Kurzbefehle gefunden") : String(localized: "Kein Treffer"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results) { shortcut in
                        Button {
                            onPick(shortcut)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: UtilitiesShortcutOptions.fallbackSymbol)
                                    .foregroundStyle(.secondary)
                                Text(shortcut.name)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if isCurrent(shortcut) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Abbrechen", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(width: 380, height: 480)
        .task {
            guard shortcuts == nil else { return }
            shortcuts = await UtilitiesShortcutCatalog.load()
        }
    }

    private func isCurrent(_ shortcut: UtilitiesShortcut) -> Bool {
        current.identifier.isEmpty ? shortcut.name == current.name : shortcut.identifier == current.identifier
    }
}

// MARK: - Galerie

/// Hinter "+": jede Art nach Gruppen, mit Symbol, Name und einer Zeile. Ein
/// Klick fuegt sie hinten an; was es nur einmal gibt und schon da ist,
/// bleibt grau.
struct UtilitiesEditorGallery: View {
    let layout: UtilitiesLayout
    let onAdd: (UtilitiesToggleKind) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Knopf hinzufügen")
                    .font(.title3.weight(.semibold))
                Text("Er kommt ans Ende des Rasters – danach an die richtige Stelle ziehen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Eigene Knoepfe zuerst: die gehen immer, die festen
                    // stehen im Standard-Panel meist schon da.
                    ForEach([UtilitiesToggleGroup.custom, .actions, .switches]) { group in
                        Text(group.title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        // Oben ausgerichtet und gleich hoch: sonst stuenden Kacheln
                        // mit zwei und drei Zeilen Text versetzt (Bildprobe 14.09.).
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .top)],
                                  spacing: 10) {
                            ForEach(group.kinds) { kind in
                                UtilitiesEditorGalleryTile(kind: kind, available: layout.canAdd(kind)) { onAdd(kind) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            Divider()
            HStack {
                Spacer()
                Button("Abbrechen", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(width: 560, height: 600)
    }
}

private struct UtilitiesEditorGalleryTile: View {
    let kind: UtilitiesToggleKind
    let available: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    UtilitiesEditorGlyphTile(icon: kind.symbol.map(UtilitiesToggleItem.Icon.symbol) ?? .bluetooth,
                                             tint: kind.group.tint, size: 30)
                    Spacer(minLength: 4)
                    if !available {
                        Text("Schon da")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(kind.title)
                    .font(.headline)
                Text(kind.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(Color.primary.opacity(hovering && available ? 0.09 : 0.05),
                        in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.45)
        // Nexus ist ein normales, aktives Fenster: hier reicht onHover.
        .onHover { hovering = $0 }
        .help(available ? "\(kind.title) hinzufügen" : "Gibt es nur einmal und steht schon im Panel")
    }
}

/// Farbige Kachel wie `NexusTile`, aber mit dem Zeichen des Knopfs (auch
/// der Bluetooth-Rune und dem App-Symbol).
private struct UtilitiesEditorGlyphTile: View {
    let icon: UtilitiesToggleItem.Icon
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        if case .app = icon {
            UtilitiesToggleGlyph(icon: icon, scale: size / 28)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(tint.gradient)
                .frame(width: size, height: size)
                .overlay {
                    UtilitiesToggleGlyph(icon: icon, scale: size / 34)
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Vorschau

/// Das echte Panel mit Vorschau-Modell, auf die Breite der Spalte
/// verkleinert. Ohne Maus: ein Klick hier soll nichts schalten (das Modell
/// schaltet ohnehin nichts, siehe `UtilitiesModel.preview`).
struct UtilitiesEditorPreview: View {
    let store: ShellSettingsStore
    var model = UtilitiesEditorPreviewModel.model

    var body: some View {
        GeometryReader { geometry in
            let layout = store.settings.utilities.layout
            let height = CGFloat(layout.panelHeight)
            let scale = min(1, (geometry.size.width - 24) / UtilitiesView.width, max(geometry.size.height - 70, 80) / height)
            VStack(spacing: 8) {
                Text("Vorschau")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                UtilitiesView(model: model, layout: layout)
                    // Ersatz fuer das Glas: eine leicht abgesetzte Flaeche.
                    .background(Color.primary.opacity(0.07))
                    .clipShape(.rect(cornerRadius: 25, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1 / scale)
                    }
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: UtilitiesView.width * scale, height: height * scale, alignment: .top)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Vorschau des Panels")
                    .animation(.snappy(duration: 0.25), value: layout)
                Text("\(Int(height)) pt hoch · Beispieldaten")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 14)
        }
    }
}

/// Festes Modell fuer die Vorschau: liest und schaltet nichts. Neutrale
/// Beispielgeraete.
@MainActor
enum UtilitiesEditorPreviewModel {
    static let model = UtilitiesModel.preview(
        keepAwakeSince: nil, wifiOn: true, micMuted: false, bluetoothOn: true, darkMode: true, nightShift: false,
        volume: 0.6,
        audioDevices: [
            UtilitiesAudioDevice(id: 1, name: "Lautsprecher", outputStreams: 1, inputStreams: 0,
                                 canBeDefaultOutput: true, canBeDefaultInput: false, hidden: false),
            UtilitiesAudioDevice(id: 2, name: "Mikrofon", outputStreams: 0, inputStreams: 1,
                                 canBeDefaultOutput: false, canBeDefaultInput: true, hidden: false),
        ],
        defaultOutput: 1, defaultInput: 2
    )
}

// MARK: - Texte und Farben

@MainActor
enum UtilitiesEditorText {
    /// Name im Raster: eigener Titel, sonst App-Name, Adresse oder Name des
    /// Kurzbefehls, sonst der Name der Art.
    static func title(_ entry: UtilitiesToggleEntry) -> String {
        let own: String? = switch entry.toggle {
        case .openApp(let o): nonEmpty(o.title) ?? BarApps.info(for: o.bundleID)?.name
        case .openLink(let o): nonEmpty(o.title) ?? UtilitiesLink.url(from: o.url).map(UtilitiesLink.displayText)
        case .runShortcut(let o): nonEmpty(o.title) ?? nonEmpty(o.name)
        default: nil
        }
        return own ?? entry.kind.title
    }

    /// Dasselbe Zeichen wie im Panel, ohne Zustand (WLAN immer "wifi").
    static func icon(_ entry: UtilitiesToggleEntry) -> UtilitiesToggleItem.Icon {
        let look: QuickToggleLook = switch entry.toggle {
        case .openApp(let o): QuickToggles.openApp(o, appName: BarApps.info(for: o.bundleID)?.name)
        case .openLink(let o): QuickToggles.openLink(o)
        case .runShortcut(let o): QuickToggles.runShortcut(o)
        default: QuickToggleLook(symbol: entry.kind.symbol, active: false, enabled: true, help: "")
        }
        return UtilitiesToggleItem.icon(for: entry.toggle, look: look)
    }

    /// "10 Knöpfe · 2 Reihen".
    static func count(_ layout: UtilitiesLayout) -> String {
        let buttons = layout.toggles.count
        let rows = layout.toggleRows.count
        return "\(buttons) \(buttons == 1 ? "Knopf" : "Knöpfe") · \(rows) \(rows == 1 ? "Reihe" : "Reihen")"
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension UtilitiesCardKind {
    /// Kachelfarbe in Nexus.
    var tint: Color {
        switch self {
        case .keepAwake: .brown
        case .audio: .pink
        case .quickToggles: .blue
        }
    }
}

extension UtilitiesToggleGroup {
    var tint: Color {
        switch self {
        case .switches: .blue
        case .actions: .indigo
        case .custom: .orange
        }
    }
}
