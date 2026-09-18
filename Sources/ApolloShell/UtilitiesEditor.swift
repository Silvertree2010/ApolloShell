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
    @State private var pending: LayoutPresetReplacement<UtilitiesPreset>?
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
        .nexusPresetAlert($pending, title: UtilitiesEditorText.replacementTitle, message: UtilitiesEditorText.replacementMessage) { layout in
            store.settings.utilities.layout = layout
            selection = nil
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
                NexusPresetMenu<UtilitiesPreset> { pending = .preset($0) }
                Spacer(minLength: 8)
                NexusPresetResetButton<UtilitiesPreset>(layout: layout) { pending = .reset }
            }
        } header: {
            Text("Vorlagen")
        } footer: {
            Text("Eine Vorlage ersetzt Karten und Schnellschalter. „Standard“ ist das Panel, wie es am Anfang war.")
        }
    }

    /// Aus der Galerie: ans Ende und gleich gewaehlt - bei App, Link und
    /// Kurzbefehl muss man ja noch das Ziel waehlen.
    private func add(_ kind: UtilitiesToggleKind) {
        showsGallery = false
        if let id = store.settings.utilities.layout.add(kind) {
            selection = id
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
    /// Titel der Vorlagen-Rueckfrage.
    static func replacementTitle(_ replacement: LayoutPresetReplacement<UtilitiesPreset>) -> String {
        switch replacement {
        case .preset(let preset): String(localized: "Vorlage „\(preset.title)“ laden?")
        case .reset: String(localized: "Schnellaktionen zurücksetzen?")
        }
    }

    /// Erklaerung der Vorlagen-Rueckfrage.
    static func replacementMessage(_ replacement: LayoutPresetReplacement<UtilitiesPreset>) -> String {
        switch replacement {
        case .preset(let preset): String(localized: "\(preset.summary) Die jetzige Anordnung wird ersetzt.")
        case .reset: String(localized: "Das Panel sieht wieder aus wie am Anfang (Vorlage Standard). Die jetzige Anordnung wird ersetzt.")
        }
    }

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
