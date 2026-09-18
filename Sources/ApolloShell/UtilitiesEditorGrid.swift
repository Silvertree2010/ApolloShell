import ApolloShellCore
import SwiftUI

// Die linke Haelfte von Nexus > Schnellaktionen unterhalb von "Wach halten":
// die drei Karten (ein/aus, ziehen) und das Raster der Schnellschalter
// (ziehen, +, Galerie). Die Optionen des gewaehlten Knopfs stehen in
// UtilitiesEditorOptions.swift, die Seite selbst in UtilitiesEditor.swift.

// MARK: - Karten

/// Kachel, Name, eine Zeile, Schalter, Griff. Kontextmenue "Nach oben/unten"
/// fuer alle, die nicht ziehen wollen; dasselbe als Bedienungshilfen-Aktion.
struct UtilitiesEditorCardRow: View {
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
struct UtilitiesEditorGrid: View {
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

// MARK: - Galerie

/// Hinter "+": jede Art nach Gruppen, mit Symbol, Name und einer Zeile. Ein
/// Klick fuegt sie hinten an; was es nur einmal gibt und schon da ist,
/// bleibt grau.
struct UtilitiesEditorGallery: View {
    let layout: UtilitiesLayout
    let onAdd: (UtilitiesToggleKind) -> Void
    let onCancel: () -> Void

    var body: some View {
        NexusGallerySheet(title: String(localized: "Knopf hinzufügen"),
                          subtitle: String(localized: "Er kommt ans Ende des Rasters – danach an die richtige Stelle ziehen."),
                          size: CGSize(width: 560, height: 600), onCancel: onCancel) {
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
                            let available = layout.canAdd(kind)
                            NexusGalleryTile(title: kind.title, summary: kind.summary,
                                             badge: available ? nil : String(localized: "Schon da"), minHeight: 132,
                                             available: available,
                                             help: available ? String(localized: "\(kind.title) hinzufügen")
                                                 : String(localized: "Gibt es nur einmal und steht schon im Panel"),
                                             action: { onAdd(kind) }) {
                                UtilitiesEditorGlyphTile(icon: kind.symbol.map(UtilitiesToggleItem.Icon.symbol) ?? .bluetooth,
                                                         tint: kind.group.tint, size: 30)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Farbige Kachel wie `NexusTile`, aber mit dem Zeichen des Knopfs (auch
/// der Bluetooth-Rune und dem App-Symbol). Auch von den Optionen des
/// gewaehlten Knopfs gebraucht (UtilitiesEditorOptions.swift).
struct UtilitiesEditorGlyphTile: View {
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
