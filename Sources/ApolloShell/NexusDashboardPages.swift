import ApolloShellCore
import SwiftUI

// Nexus > Dashboard, Abschnitt "Seiten" (design/2026-09-18-bento-plan-edit.md
// Task 4): Liste der Bento-Seiten, verwalten (nicht editierend) oder nur
// waehlen (editierend, `NexusDashboardEditPagesList`). Die Seite selbst mit
// dem Groessenregler und der Vorschau steht in NexusDashboardPage.swift.

/// Etwa 24 SF Symbole zur Auswahl fuer eine Seite - genug Vielfalt, ohne den
/// Menue-Aufwand eines vollen Symbolpickers.
let nexusPageSymbols = [
    "square.grid.2x2", "star", "house", "briefcase", "bolt", "gamecontroller",
    "moon.stars", "sun.max", "cloud.sun", "music.note", "film", "book",
    "paintbrush", "hammer", "wrench.and.screwdriver", "leaf", "pawprint",
    "airplane", "car", "bicycle", "figure.walk", "heart", "flag", "globe",
]

/// Abschnitt "Seiten": nicht editierend voller Baukasten (umsortieren,
/// umbenennen, Symbol, duplizieren, loeschen, hinzufuegen, Standardseiten
/// wiederherstellen).
struct NexusDashboardPagesSection: View {
    @Bindable var store: ShellSettingsStore
    @Binding var selection: DashboardPage.ID?
    let weatherPlaces: WeatherFavorites
    let onEdit: (DashboardPage.ID) -> Void

    @State private var pendingDelete: DashboardPage.ID?

    private var pages: DashboardPages {
        store.settings.dashboardPages
            ?? DashboardPages(pages: DashboardPages.defaultPages(places: .empty,
                                                                  hasBattery: PerformanceSampler.hasInternalBattery))!
    }

    var body: some View {
        Section {
            ForEach(pages.pages) { page in
                NexusDashboardPageRow(store: store, page: page, selected: page.id == selection,
                                      onSelect: { selection = page.id }, onEdit: { onEdit(page.id) },
                                      onDuplicate: { duplicate(page.id) },
                                      onDelete: { pendingDelete = page.id },
                                      canDelete: pages.pages.count > 1)
            }
            .onMove { store.settings.dashboardPages?.movePages(fromOffsets: $0, toOffset: $1) }
        } header: {
            Text("Seiten")
        } footer: {
            Text("Zum Umsortieren ziehen. Ein Klick auf „Bearbeiten“ öffnet die gewählte Seite als Baukasten.")
        }
        Section {
            HStack(spacing: 8) {
                Button {
                    add()
                } label: {
                    Label("Seite hinzufügen", systemImage: "plus")
                }
                Spacer(minLength: 8)
                Button("Standardseiten wiederherstellen") { restoreDefaults() }
                    .disabled(!missingDefaults)
            }
        } footer: {
            Text("Fehlende mitgelieferte Seiten (Dashboard, Medien, Leistung, Wetter) kommen ans Ende zurück; vorhandene Seiten bleiben unverändert.")
        }
        .alert("Seite löschen?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Löschen", role: .destructive) {
                if let id = pendingDelete { delete(id) }
                pendingDelete = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Ihre Widgets gehen dabei verloren.")
        }
    }

    private var missingDefaults: Bool {
        let present = Set(pages.pages.compactMap(\.template))
        return Set(PageTemplate.allCases).contains { !present.contains($0) }
    }

    private func add() {
        let name = String(localized: "Seite \(pages.pages.count + 1)")
        let id = store.settings.dashboardPages?.addPage(name: name)
        selection = id
    }

    private func duplicate(_ id: DashboardPage.ID) {
        guard let page = pages.page(id: id) else { return }
        let name = String(localized: "\(page.name) Kopie")
        selection = store.settings.dashboardPages?.duplicatePage(id: id, name: name)
    }

    private func delete(_ id: DashboardPage.ID) {
        store.settings.dashboardPages?.removePage(id: id)
        if selection == id { selection = nil }
    }

    private func restoreDefaults() {
        store.settings.dashboardPages?.restoreDefaults(
            from: DashboardPages.defaultPages(places: weatherPlaces, hasBattery: PerformanceSampler.hasInternalBattery)
        )
    }
}

private struct NexusDashboardPageRow: View {
    @Bindable var store: ShellSettingsStore
    let page: DashboardPage
    let selected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let canDelete: Bool

    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(nexusPageSymbols, id: \.self) { symbol in
                    Button {
                        store.settings.dashboardPages?.setSymbol(symbol, forPage: page.id)
                    } label: {
                        Label(symbol, systemImage: symbol)
                    }
                }
            } label: {
                NexusTile(symbol: page.symbol, tint: .indigo, size: 24)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()

            TextField("Name", text: Binding(
                get: { page.name },
                set: { store.settings.dashboardPages?.renamePage(id: page.id, to: $0) }
            ))
            .textFieldStyle(.plain)
            .focused($nameFocused)

            Spacer(minLength: 8)
            Text(String(localized: "\(page.widgets.count) Widgets"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Bearbeiten", action: onEdit)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Duplizieren", action: onDuplicate)
            Button("Löschen", role: .destructive, action: onDelete)
                .disabled(!canDelete)
        }
    }
}

/// Abschnitt "Seiten" waehrend einer Bearbeitung: nur waehlen, kein
/// Umsortieren/Hinzufuegen/Loeschen - das wuerde die laufende Sitzung
/// verwirren (andere Seite bearbeiten geht ueber Auswahl selbst).
struct NexusDashboardEditPagesList: View {
    @Bindable var editor: DashboardEditor

    var body: some View {
        if let pages = editor.session?.pages.pages {
            List(selection: Binding(get: { editor.pageID }, set: { if let id = $0 { editor.pageID = id } })) {
                ForEach(pages) { page in
                    Label {
                        Text(page.name)
                    } icon: {
                        Image(systemName: page.symbol)
                    }
                    .tag(page.id)
                }
            }
            .listStyle(.sidebar)
        }
    }
}
