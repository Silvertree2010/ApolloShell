import ApolloShellCore
import SwiftUI

// Unter dem Raster in Nexus > Schnellaktionen: die Optionen des gewaehlten
// Knopfs. Das Raster selbst steht in UtilitiesEditorGrid.swift, die Seite in
// UtilitiesEditor.swift.

// MARK: - Optionen eines Knopfs

/// Unter dem Raster: welcher Knopf gewaehlt ist, Entfernen, und - bei App,
/// Link, Kurzbefehl, Apps ausblenden - seine Optionen. Jede Aenderung
/// ersetzt die Optionen dieses einen Knopfs (`UtilitiesLayout.update`).
struct UtilitiesEditorOptions: View {
    @Bindable var store: ShellSettingsStore
    let entry: UtilitiesToggleEntry
    let onDeselect: () -> Void
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
            Button("Choose Shortcut…") { picksShortcut = true }
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

/// "Icon": das jetzige, daneben "Choose…" mit der kleinen Auswahl.
private struct UtilitiesEditorSymbolRow: View {
    let current: String
    let automatic: String
    let fallback: UtilitiesToggleItem.Icon
    let onPick: (String) -> Void
    @State private var picking = false

    var body: some View {
        LabeledContent("Icon") {
            HStack(spacing: 8) {
                UtilitiesToggleGlyph(icon: fallback, scale: 0.8)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                Text(current.isEmpty ? automatic : current)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Choose…") { picking = true }
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
