import ApolloShellCore
import SwiftUI

// Die zwei kleinen Ausw-Dialoge hinter den Optionen eines Knopfs
// (UtilitiesEditorOptions.swift): das Symbol und der Kurzbefehl.

// MARK: - Symbol waehlen

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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
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
                TextField("Eigenes Symbol", text: $custom, prompt: Text("SF Symbol Name"))
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
        NexusSearchSheet(title: "Choose Shortcut", subtitle: "From the Shortcuts app. It only runs when clicked in the panel.",
                         searchPrompt: "Search Shortcuts", query: $query, onCancel: onCancel) {
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
        .task {
            guard shortcuts == nil else { return }
            shortcuts = await UtilitiesShortcutCatalog.load()
        }
    }

    private func isCurrent(_ shortcut: UtilitiesShortcut) -> Bool {
        current.identifier.isEmpty ? shortcut.name == current.name : shortcut.identifier == current.identifier
    }
}
