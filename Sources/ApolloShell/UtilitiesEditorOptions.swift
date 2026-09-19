import ApolloShellCore
import SwiftUI

// Kleine Bausteine der Optionen eines Knopfs, seit Task 7 nur noch fuer den
// Options-Popover des globalen Bearbeitungsmodus gebraucht
// (`UtilitiesToggleOptionsView`, `UtilitiesEditOverlay.swift`). Bis dahin
// stand hier auch der Rahmen dafuer in Nexus' altem Raster-Editor
// (UtilitiesEditorGrid.swift, entfernt).

/// Textfeld, das erst beim Bestaetigen (Return) oder beim Verlassen
/// schreibt - nicht bei jedem Tastendruck settings.json, und das Panel
/// zeichnet nicht jeden halben Link neu.
///
/// Nicht `private`: `UtilitiesToggleOptionsView` (Task 5, Popover im
/// globalen Bearbeitungsmodus) nutzt dasselbe Feld.
struct UtilitiesEditorField: View {
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
///
/// Nicht `private`: siehe `UtilitiesEditorField`.
struct UtilitiesEditorSymbolRow: View {
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
