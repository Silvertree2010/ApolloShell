import AppKit
import ApolloShellCore
import Observation
import SwiftUI
import os

/// Die angehefteten Apps zum Bearbeiten (pinned.json). Jede Aenderung wird
/// sofort atomar geschrieben; der Launcher liest die Datei bei jedem Oeffnen
/// neu und zeigt die neue Reihenfolge also beim naechsten fn.
@MainActor
@Observable
final class NexusPinnedModel {
    private(set) var list = PinnedList()
    /// Installierte Apps mit Bundle-ID - nur solche lassen sich anheften
    /// (pinned.json fuehrt Bundle-IDs).
    private(set) var apps: [AppEntry] = []
    var query = ""
    private(set) var saveFailed = false

    /// Hoechstens so viele Suchtreffer: mehr passt nicht ohne Scrollen, und
    /// wer mehr braucht, tippt einen Buchstaben mehr.
    @ObservationIgnored private static let maxResults = 8

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var byID: [String: AppEntry] = [:]
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private let matcher = FuzzyMatcher()
    @ObservationIgnored private let log = Logger(category: "nexus")

    /// `url == nil`: nur im Speicher.
    init(url: URL?) {
        self.url = url
        live = true
    }

    private init(preview list: PinnedList, apps: [AppEntry]) {
        url = nil
        live = false
        self.list = list
        setApps(apps)
    }

    /// Fuer Bildproben: feste Liste und Apps, liest und schreibt nichts.
    static func preview(pinned: [String], apps: [AppEntry], query: String = "") -> NexusPinnedModel {
        let model = NexusPinnedModel(preview: PinnedList(pinned), apps: apps)
        model.query = query
        return model
    }

    /// Apps suchen (wie der Launcher bei jedem Oeffnen, einige ms) und
    /// pinned.json lesen.
    func reload() {
        guard live else { return }
        setApps(AppCatalog().scan())
        list = PinnedList.load(from: ShellFiles.read(url))
    }

    private func setApps(_ scanned: [AppEntry]) {
        apps = scanned.filter { $0.bundleID != nil }
        byID = Dictionary(apps.map { ($0.bundleID!, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func app(for id: String) -> AppEntry? { byID[id] }

    /// Unscharf wie im Launcher, schon angeheftete fallen weg.
    var results: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        // In Schritten mit festen Typen: als eine Kette brauchte der
        // Typpruefer zu lange.
        var scored: [(app: AppEntry, score: Int)] = []
        for app in apps where !list.contains(app.bundleID ?? "") {
            if let score = matcher.score(q, in: app.name) { scored.append((app, score)) }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
        }
        return scored.prefix(Self.maxResults).map(\.app)
    }

    func icon(for id: String) -> NSImage {
        if let cached = icons[id] { return cached }
        let image = byID[id].map { NSWorkspace.shared.icon(forFile: $0.url.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        icons[id] = image
        return image
    }

    func add(_ app: AppEntry) {
        guard let id = app.bundleID else { return }
        var next = list
        if next.add(id) { apply(next) }
    }

    func remove(_ id: String) {
        var next = list
        next.remove(id)
        apply(next)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var next = list
        next.move(fromOffsets: source, toOffset: destination)
        apply(next)
    }

    func move(_ id: String, by step: Int) {
        var next = list
        next.move(id, by: step)
        apply(next)
    }

    private func apply(_ next: PinnedList) {
        guard next != list else { return }
        list = next
        guard let url else { return }
        do {
            try ShellFiles.write(list.encoded(), to: url)
            if saveFailed { saveFailed = false }
        } catch {
            saveFailed = true
            log.error("pinned.json nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Caelestia: Panels > Launcher und Apps > Favoriten - bei uns die festen
/// Top 10 des Launchers.
struct NexusLauncherPage: View {
    @Bindable var model: NexusPinnedModel

    var body: some View {
        NexusPageForm(page: .launcher) {
            Section {
                if model.list.ids.isEmpty {
                    Text("Noch keine Apps angeheftet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(model.list.ids.enumerated()), id: \.element) { index, id in
                    NexusPinnedRow(model: model, id: id, position: index + 1, count: model.list.ids.count)
                }
                .onMove { model.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                HStack {
                    Text("Angeheftete Apps")
                    Spacer()
                    Text(NexusText.pinnedCount(model.list.ids.count))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Stehen im Launcher ohne Suchtext in dieser Reihenfolge ganz oben. Zum Umsortieren ziehen oder das Kontextmenü nehmen.")
            }

            Section {
                NexusSearchField(prompt: "App suchen", text: $model.query)
                ForEach(model.results) { app in
                    NexusAddAppRow(model: model, app: app)
                }
                if !model.query.trimmingCharacters(in: .whitespaces).isEmpty, model.results.isEmpty {
                    Text("Keine passende App.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("App hinzufügen")
            } footer: {
                if model.list.isFull {
                    Text("\(PinnedList.limit) Apps sind angeheftet – erst eine entfernen.")
                }
            }
            NexusSaveWarning(failed: model.saveFailed, file: "pinned.json")
        }
    }
}

private struct NexusPinnedRow: View {
    let model: NexusPinnedModel
    let id: String
    let position: Int
    let count: Int

    var body: some View {
        let app = model.app(for: id)
        HStack(spacing: 10) {
            Text("\(position)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Image(nsImage: model.icon(for: id))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .opacity(app == nil ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(app?.name ?? id)
                    .lineLimit(1)
                if app == nil {
                    // Deinstalliert oder umbenannt: der Launcher uebergeht
                    // sie, entfernen kann man sie trotzdem.
                    Text("Nicht installiert")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                model.remove(id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Entfernen")
            .accessibilityLabel("\(app?.name ?? id) entfernen")
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .contextMenu {
            Button("Nach oben") { model.move(id, by: -1) }
                .disabled(position == 1)
            Button("Nach unten") { model.move(id, by: 1) }
                .disabled(position == count)
            Divider()
            Button("Entfernen", role: .destructive) { model.remove(id) }
        }
    }
}

private struct NexusAddAppRow: View {
    let model: NexusPinnedModel
    let app: AppEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.icon(for: app.bundleID ?? ""))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
            Text(app.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                model.add(app)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(model.list.isFull ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
            }
            .buttonStyle(.borderless)
            .disabled(model.list.isFull)
            .help("Anheften")
            .accessibilityLabel("\(app.name) anheften")
        }
    }
}

/// Suchzeile im Formular: Lupe, schlichtes Feld, Loeschen-Knopf.
struct NexusSearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    var busy = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
            if busy {
                ProgressView()
                    .controlSize(.small)
            } else if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Suche leeren")
            }
        }
    }
}
