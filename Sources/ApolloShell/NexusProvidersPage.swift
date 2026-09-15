import AppKit
import ApolloShellCore
import Observation
import SwiftUI

/// Was die Seite "Anbieter" zum Anzeigen braucht: installierte Apps fuer
/// "Andere App …", ihre Namen und Symbole. Die Einstellungen selbst liegen in
/// settings.json (`ShellSettingsStore`) und gelten sofort - die Leiste
/// beobachtet den Dateimanager, das Wetter liest den Anbieter beim naechsten
/// Oeffnen des Dashboards.
@MainActor
@Observable
final class NexusProvidersModel {
    /// Installierte Apps mit Bundle-ID - nur solche lassen sich waehlen.
    private(set) var apps: [AppEntry] = []
    var query = ""
    /// "Andere App …" aufgeklappt.
    var showsOtherApps = false

    /// Hoechstens so viele Treffer, wie bei den angehefteten Apps.
    @ObservationIgnored private static let maxResults = 8
    @ObservationIgnored private let live: Bool
    /// Bildproben: welche Apps als installiert gelten (Finder immer).
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

    /// Fuer Bildproben: feste Apps, liest nichts ausser Symbolen.
    static func preview(apps: [AppEntry], installed: Set<String>, query: String = "",
                        showsOtherApps: Bool = false) -> NexusProvidersModel {
        let model = NexusProvidersModel(preview: apps, installed: installed)
        model.query = query
        model.showsOtherApps = showsOtherApps
        return model
    }

    /// Beim Oeffnen von Nexus: Apps suchen (einige ms, wie der Launcher).
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

    /// Anzeigename; Finder liegt nicht in den durchsuchten Ordnern, also
    /// ueber LaunchServices. Unbekannt: die Bundle-ID.
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

    /// Unscharf wie im Launcher.
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

/// Anbieter: woher das Wetter kommt und welcher Dateimanager oben im Dock
/// steht. Caelestia kennt keine Auswahl (fest Open-Meteo bzw. frueher
/// wttr.in); hier ist beides waehlbar, alles ohne Konto.
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

    // MARK: Wetter

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
            Text("Wetter")
        } footer: {
            Text("Alle ohne Konto und Schlüssel. Das Dashboard fragt den Anbieter nur, solange es offen ist, und nimmt die neue Wahl beim nächsten Öffnen. Die Ortssuche bleibt bei Open-Meteo.")
        }
    }

    // MARK: Dateimanager

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
                        Text("Automatisch")
                        Text("ForkLift, wenn installiert, sonst Finder – jetzt \(model.name(for: automatic))")
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
            Text("Dateimanager")
        } footer: {
            Text("Steht in der Leiste zuoberst an Finders Platz, immer mit Punkt. Finder verschwindet dort nur, wenn eine andere App ihn ersetzt. „In … zeigen“ im Dock-Menü nimmt diese App; der macOS-Standard für andere Apps bleibt, wie er ist.")
        }
    }

    /// Aufklappbar: die meisten brauchen es nie, und die Liste aller Apps
    /// wuerde die Seite sprengen.
    @ViewBuilder private var otherApps: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { model.showsOtherApps.toggle() }
        } label: {
            HStack {
                Text("Andere App …")
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
            NexusSearchField(prompt: "App suchen", text: $model.query)
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
                Text("Keine passende App.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// App-Symbol und Name, darunter bei Bedarf ein grauer Hinweis.
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

/// Auswahlzeile mit Haekchen rechts, wie die Listen der Systemeinstellungen
/// (dort ebenfalls ohne Radio-Knoepfe, die ganze Zeile ist klickbar).
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
