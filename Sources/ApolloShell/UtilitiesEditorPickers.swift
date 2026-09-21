import ApolloShellCore
import SwiftUI

// The two small pick dialogs behind a button's options
// (UtilitiesEditorOptions.swift): the symbol and the shortcut.

// MARK: - Choose symbol

/// The small symbol picker: "automatic", the list from
/// `UtilitiesSymbols` (only the ones that exist on this macOS) and a field
/// for any other SF Symbol name - which is only accepted once it
/// actually exists.
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // `Grid` instead of `LazyVGrid`: the lazy version estimated its height
            // at over 1000 pt (screenshot 14.09.) - the popover would have gotten
            // that tall. 48 symbols can be drawn without laziness too.
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
                TextField("Custom Symbol", text: $custom, prompt: Text("SF Symbol Name"))
                    .onSubmit(takeCustom)
                Button("Apply", action: takeCustom)
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

// MARK: - Choose shortcut

/// The user's shortcuts with search. Reads only the list on open
/// (`UtilitiesShortcutCatalog`); nothing here actually runs.
struct UtilitiesShortcutPicker: View {
    let current: UtilitiesShortcutOptions
    let onPick: (UtilitiesShortcut) -> Void
    let onCancel: () -> Void
    @State private var query = ""
    /// `nil`: still being read.
    @State private var shortcuts: [UtilitiesShortcut]?

    /// `shortcuts` given (screenshot test): no loading.
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
        SearchSheet(title: "Choose Shortcut", subtitle: "From the Shortcuts app. It only runs when clicked in the panel.",
                         searchPrompt: "Search Shortcuts", query: $query, onCancel: onCancel) {
            if shortcuts == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                Text(query.isEmpty ? String(localized: "No Shortcuts Found") : String(localized: "No Match"))
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
        .task {
            guard shortcuts == nil else { return }
            shortcuts = await UtilitiesShortcutCatalog.load()
        }
    }

    private func isCurrent(_ shortcut: UtilitiesShortcut) -> Bool {
        current.identifier.isEmpty ? shortcut.name == current.name : shortcut.identifier == current.identifier
    }
}
