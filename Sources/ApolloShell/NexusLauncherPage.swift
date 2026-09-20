import AppKit
import ApolloShellCore
import Observation
import SwiftUI
import os

/// The pinned apps for editing (pinned.json). Every change is written
/// atomically right away; the launcher reads the file anew on every opening
/// and therefore shows the new order on the next fn.
@MainActor
@Observable
final class NexusPinnedModel {
    private(set) var list = PinnedList()
    /// The installed apps with a bundle ID - only those can be pinned
    /// (pinned.json carries bundle IDs).
    private(set) var apps: [AppEntry] = []
    var query = ""
    private(set) var saveFailed = false

    /// At most this many search hits: more does not fit without scrolling, and
    /// whoever needs more types one more letter.
    @ObservationIgnored private static let maxResults = 8

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var byID: [String: AppEntry] = [:]
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private let matcher = FuzzyMatcher()
    @ObservationIgnored private let log = Logger(category: "nexus")

    /// `url == nil`: only in memory.
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

    /// For image samples: a fixed list and fixed apps, reads and writes nothing.
    static func preview(pinned: [String], apps: [AppEntry], query: String = "") -> NexusPinnedModel {
        let model = NexusPinnedModel(preview: PinnedList(pinned), apps: apps)
        model.query = query
        return model
    }

    /// Search for apps (as the launcher does on every opening, a few ms) and
    /// read pinned.json.
    func reload() {
        guard live else { return }
        setApps(AppCatalog().scan())
        let data = ShellFiles.read(url)
        // Broken (edited by hand): keep it before the next pin writes the empty
        // list over it.
        if let url, PinnedList.isUnreadable(data) {
            ShellFiles.preserveUnreadable(url)
            log.error("pinned.json unlesbar, Kopie als pinned.json.unreadable")
        }
        list = PinnedList.load(from: data)
    }

    private func setApps(_ scanned: [AppEntry]) {
        apps = scanned.filter { $0.bundleID != nil }
        byID = Dictionary(apps.map { ($0.bundleID!, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func app(for id: String) -> AppEntry? { byID[id] }

    /// Fuzzy as in the launcher, the ones already pinned fall away.
    var results: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        // In steps with fixed types: as one chain the type checker took too long.
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

/// Caelestia: Panels > Launcher and Apps > Favourites - with us the fixed top
/// 10 of the launcher.
struct NexusLauncherPage: View {
    @Bindable var model: NexusPinnedModel

    var body: some View {
        NexusPageForm(page: .launcher) {
            Section {
                if model.list.ids.isEmpty {
                    Text("No apps pinned yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(model.list.ids.enumerated()), id: \.element) { index, id in
                    NexusPinnedRow(model: model, id: id, position: index + 1, count: model.list.ids.count)
                }
                .onMove { model.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                HStack {
                    Text("Pinned Apps")
                    Spacer()
                    Text(NexusText.pinnedCount(model.list.ids.count))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Appear at the top of the launcher without a search text, in this order. Drag to reorder, or use the context menu.")
            }

            Section {
                NexusSearchField(prompt: "Search Apps", text: $model.query)
                ForEach(model.results) { app in
                    NexusAddAppRow(model: model, app: app)
                }
                if !model.query.trimmingCharacters(in: .whitespaces).isEmpty, model.results.isEmpty {
                    Text("No matching app.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Add App")
            } footer: {
                if model.list.isFull {
                    Text("\(PinnedList.limit) apps are pinned – remove one first.")
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
                    // Uninstalled or renamed: the launcher passes them over,
                    // but they can still be removed.
                    Text("Not Installed")
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
            .help("Remove")
            .accessibilityLabel("Remove \(app?.name ?? id)")
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .contextMenu {
            Button("Move Up") { model.move(id, by: -1) }
                .disabled(position == 1)
            Button("Move Down") { model.move(id, by: 1) }
                .disabled(position == count)
            Divider()
            Button("Remove", role: .destructive) { model.remove(id) }
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
            .help("Pin")
            .accessibilityLabel("Pin \(app.name)")
        }
    }
}

/// A search row in the form: a magnifier, a plain field, a clear button.
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
                .help("Clear Search")
            }
        }
    }
}
