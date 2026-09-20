import ApolloShellCore
import SwiftUI

// Small building blocks for a toggle's options, only needed since Task 7
// for the options popover of the global edit mode
// (`UtilitiesToggleOptionsView`, `UtilitiesEditOverlay.swift`). Until then
// this also held the frame for it in Nexus's old grid editor
// (UtilitiesEditorGrid.swift, removed).

/// Text field that writes only on commit (Return) or on leaving focus -
/// not settings.json on every keystroke, and the panel doesn't redraw
/// every half-typed link.
///
/// Not `private`: `UtilitiesToggleOptionsView` (Task 5, popover in the
/// global edit mode) uses the same field.
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

/// "Symbol": the current one, next to it "Choose…" with the small picker.
///
/// Not `private`: see `UtilitiesEditorField`.
struct UtilitiesEditorSymbolRow: View {
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
