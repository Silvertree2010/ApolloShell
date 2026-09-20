import AppKit
import ApolloShellCore
import SwiftUI

// Die gewaehlte App eines Bausteins: in Nexus > Leiste (App-Knopf) und
// Nexus > Schnellaktionen (Knopf "App oeffnen") dieselbe Zeile und derselbe
// Auswahl-Dialog.

/// Zeile "gewaehlte App bzw. Hinweis, Knopf App waehlen". Oeffnet
/// `NexusBarAppPicker` und meldet die gewaehlte Bundle-ID zurueck.
struct NexusAppChoiceRow: View {
    let bundleID: String
    let onPick: (String) -> Void
    @State private var picksApp = false

    var body: some View {
        HStack(spacing: 10) {
            if let info = BarApps.info(for: bundleID) {
                Image(nsImage: info.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                Text(info.name)
            } else {
                Text(bundleID.isEmpty ? String(localized: "No App Chosen Yet")
                     : String(localized: "\(bundleID) is not installed"))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Choose App…") { picksApp = true }
        }
        .sheet(isPresented: $picksApp) {
            NexusBarAppPicker(current: bundleID, onPick: { id in
                onPick(id)
                picksApp = false
            }, onCancel: { picksApp = false })
        }
    }
}

// MARK: - App waehlen

/// Installierte Apps mit Suche (unscharf wie im Launcher). Gelesen beim
/// Oeffnen, wie der Launcher es bei jedem Oeffnen tut (einige ms).
struct NexusBarAppPicker: View {
    let current: String
    let onPick: (String) -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @State private var apps: [AppEntry]

    /// `apps` vorgegeben (Bildprobe): kein Einlesen.
    init(current: String, apps: [AppEntry] = [], onPick: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.current = current
        self.onPick = onPick
        self.onCancel = onCancel
        _apps = State(initialValue: apps)
    }

    private var results: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        let matcher = FuzzyMatcher()
        var scored: [(app: AppEntry, score: Int)] = []
        for app in apps {
            if let score = matcher.score(q, in: app.name) { scored.append((app, score)) }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
        }
        return scored.map(\.app)
    }

    var body: some View {
        NexusSearchSheet(title: "Choose App", subtitle: nil, searchPrompt: "Search Apps",
                         query: $query, onCancel: onCancel) {
            List(results, id: \.url) { app in
                Button {
                    if let id = app.bundleID { onPick(id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 24, height: 24)
                        Text(app.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if app.bundleID == current {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            guard apps.isEmpty else { return }
            apps = AppCatalog().scan()
                .filter { $0.bundleID != nil }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
