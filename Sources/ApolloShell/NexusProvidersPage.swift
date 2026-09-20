import AppKit
import ApolloShellCore
import Observation
import SwiftUI

/// What the "Providers" page needs for the display: the installed apps for
/// "Other App …", their names and symbols. The settings themselves lie in
/// settings.json (`ShellSettingsStore`) and hold right away - the bar watches
/// the file manager, and the weather reads the provider the next time the
/// dashboard opens.
@MainActor
@Observable
final class NexusProvidersModel {
    /// The installed apps with a bundle ID - only those can be chosen.
    private(set) var apps: [AppEntry] = []
    var query = ""
    /// "Other App …" unfolded.
    var showsOtherApps = false

    /// At most as many hits as with the pinned apps.
    @ObservationIgnored private static let maxResults = 8
    @ObservationIgnored private let live: Bool
    /// Image samples: which apps count as installed (the Finder always).
    @ObservationIgnored private var previewInstalled: Set<String> = []
    @ObservationIgnored private var byID: [String: AppEntry] = [:]
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private let matcher = FuzzyMatcher()

    init() {
        live = true
    }

    private init(preview apps: [AppEntry], installed: Set<String>) {
        live = false
        previewInstalled = installed
        setApps(apps)
    }

    /// For image samples: fixed apps, reads nothing but symbols.
    static func preview(apps: [AppEntry], installed: Set<String>, query: String = "",
                        showsOtherApps: Bool = false) -> NexusProvidersModel {
        let model = NexusProvidersModel(preview: apps, installed: installed)
        model.query = query
        model.showsOtherApps = showsOtherApps
        return model
    }

    /// When Nexus opens: search for apps (a few ms, like the launcher).
    func reload() {
        guard live else { return }
        setApps(AppCatalog().scan())
    }

    private func setApps(_ scanned: [AppEntry]) {
        apps = scanned.filter { $0.bundleID != nil }
        byID = Dictionary(apps.map { ($0.bundleID!, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func isInstalled(_ id: String) -> Bool {
        if id == ProviderFileManager.finder { return true }
        guard live else { return previewInstalled.contains(id) }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    /// The display name; the Finder does not lie in the searched folders, so
    /// through LaunchServices. Unknown: the bundle ID.
    func name(for id: String) -> String {
        if let app = byID[id] { return app.name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    func icon(for id: String) -> NSImage {
        if let cached = icons[id] { return cached }
        let url = byID[id]?.url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        let image = url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .applicationBundle)
        icons[id] = image
        return image
    }

    /// Fuzzy as in the launcher.
    var results: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var scored: [(app: AppEntry, score: Int)] = []
        for app in apps {
            if let score = matcher.score(q, in: app.name) { scored.append((app, score)) }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
        }
        return scored.prefix(Self.maxResults).map(\.app)
    }
}

/// Providers: where the weather comes from and which file manager stands at
/// the top of the Dock. Caelestia knows no choice (fixed Open-Meteo, or wttr.in
/// earlier); here both can be chosen, all of it without an account.
struct NexusProvidersPage: View {
    @Bindable var store: ShellSettingsStore
    @Bindable var model: NexusProvidersModel

    var body: some View {
        NexusPageForm(page: .providers) {
            weather
            fileManager
            NexusSaveWarning(failed: store.saveFailed)
        }
    }

    // MARK: Weather

    private var weather: some View {
        let chosen = store.settings.providers.weather.provider()
        return Section {
            ForEach(WeatherProviderID.allCases) { id in
                let provider = id.provider()
                NexusChoiceRow(selected: id == chosen.id) {
                    store.settings.providers.weather = id
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(provider.attribution.name)
                        Text(provider.capabilities.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Quellenangabe") {
                Link(destination: chosen.attribution.url) {
                    HStack(spacing: 4) {
                        Text(chosen.attribution.text)
                        Image(systemName: "arrow.up.forward")
                            .font(.caption.weight(.semibold))
                    }
                }
                .help(chosen.attribution.url.absoluteString)
            }
        } header: {
            Text("Weather")
        } footer: {
            Text("All without an account or key. The Dashboard only asks the provider while it's open, and picks up a new choice the next time it opens. The place search stays with Open-Meteo.")
        }
    }

    // MARK: File manager

    private var fileManager: some View {
        let setting = store.settings.providers.fileManager
        let automatic = ProviderFileManager.automatic(isInstalled: model.isInstalled)
        let active = ProviderFileManager.resolve(setting: setting, isInstalled: model.isInstalled)
        return Section {
            NexusChoiceRow(selected: setting == nil) {
                store.settings.providers.fileManager = nil
            } label: {
                HStack(spacing: 10) {
                    NexusTile(symbol: "wand.and.stars", tint: .gray, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Automatic")
                        Text("ForkLift if installed, otherwise Finder – currently \(model.name(for: automatic))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(ProviderFileManager.choices(setting: setting, isInstalled: model.isInstalled), id: \.self) { id in
                NexusChoiceRow(selected: setting == id) {
                    store.settings.providers.fileManager = id
                } label: {
                    NexusAppLabel(model: model, id: id,
                                  note: model.isInstalled(id) ? nil : "Nicht installiert – oben steht \(model.name(for: active))")
                }
            }
            otherApps
        } header: {
            Text("File Manager")
        } footer: {
            Text("Sits at the top of the bar in Finder's place, always with a dot. Finder only disappears there when another app replaces it. “Show in …” in the Dock menu uses this app; the macOS default for other apps stays as it is.")
        }
    }

    /// Unfoldable: most people never need it, and the list of all apps would
    /// burst the page.
    @ViewBuilder private var otherApps: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { model.showsOtherApps.toggle() }
        } label: {
            HStack {
                Text("Other App…")
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(model.showsOtherApps ? 90 : 0))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        if model.showsOtherApps {
            NexusSearchField(prompt: "Search Apps", text: $model.query)
            ForEach(model.results) { app in
                if let id = app.bundleID {
                    NexusChoiceRow(selected: store.settings.providers.fileManager == id) {
                        store.settings.providers.fileManager = id
                        model.query = ""
                        model.showsOtherApps = false
                    } label: {
                        NexusAppLabel(model: model, id: id, note: nil)
                    }
                }
            }
            if !model.query.trimmingCharacters(in: .whitespaces).isEmpty, model.results.isEmpty {
                Text("No matching app.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The app symbol and the name, below it a grey note when needed.
private struct NexusAppLabel: View {
    let model: NexusProvidersModel
    let id: String
    let note: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.icon(for: id))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .opacity(note == nil ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name(for: id))
                    .lineLimit(1)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A choice row with a tick on the right, like the lists of System Settings
/// (which have no radio buttons either, and the whole row is clickable).
struct NexusChoiceRow<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                label
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
