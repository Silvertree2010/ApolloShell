import AppKit
import ApolloShellCore
import SwiftUI

/// Gruppen der Seitenleiste, nach Caelestias Kategorien (PageRegistry:
/// appearance, connectivity, system, shell, about).
///
/// Caelestia verschachtelt: "Panels" ist eine Seite mit Unterseiten
/// (Dashboard, Taskbar, Launcher, ...). Die Systemeinstellungen von macOS
/// haben eine flache Seitenleiste; deshalb stehen die Unterseiten hier
/// direkt unter der Ueberschrift "Panels". Was macOS selbst regelt (Netzwerk,
/// Bluetooth, Ton, Hintergrund, Sprache - bei Caelestia eigene Seiten), ist
/// eine Seite mit Spruengen in die Systemeinstellungen, keine Nachbildung.
enum NexusSection: CaseIterable, Identifiable {
    case general, panels, services, system, about

    var id: Self { self }

    var title: String? {
        switch self {
        // Oberste Gruppe ohne Ueberschrift, wie in den Systemeinstellungen.
        case .general: nil
        case .panels: String(localized: "Panels")
        case .services: String(localized: "Dienste")
        case .system: String(localized: "macOS")
        case .about: nil
        }
    }
}

/// Eine Seite von Nexus. Titel und Unterzeile wie Caelestias PageRegistry
/// (label, description), auf Deutsch.
enum NexusPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general, hotKeys, bar, utilities, launcher, dashboard, desktop, themes, toasts, providers, updates, system, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "Allgemein")
        case .hotKeys: String(localized: "Tastenkürzel")
        case .bar: String(localized: "Leiste")
        case .utilities: String(localized: "Schnellaktionen")
        case .launcher: String(localized: "Launcher")
        case .dashboard: String(localized: "Dashboard")
        case .desktop: String(localized: "Schreibtisch")
        case .toasts: String(localized: "Kurzmeldungen")
        case .providers: String(localized: "Anbieter")
        case .themes: String(localized: "Themes")
        case .updates: String(localized: "Updates")
        case .system: String(localized: "Systemeinstellungen")
        case .about: String(localized: "Über")
        }
    }

    var subtitle: String {
        switch self {
        case .general: String(localized: "Start bei der Anmeldung und die Freigaben, die ApolloShell von macOS braucht.")
        case .hotKeys: String(localized: "Globale Kürzel für Launcher, Dashboard, Schnellaktionen und Nexus.")
        case .bar: String(localized: "Die Bausteine der Leiste links: anordnen, hinzufügen, einstellen.")
        case .utilities: String(localized: "Karten und Schnellschalter im Utilities-Panel unten rechts.")
        case .launcher: String(localized: "Die angehefteten Apps, die ohne Suchtext ganz oben stehen.")
        case .dashboard: String(localized: "Reiter und Karten des Dashboards: anordnen, hinzufügen, einstellen. Dazu der Ort fürs Wetter.")
        case .desktop: String(localized: "Die Uhr unten rechts auf dem Schreibtisch.")
        case .toasts: String(localized: "Welche Ereignisse unten rechts eine Kurzmeldung zeigen.")
        case .providers: String(localized: "Woher das Wetter kommt und welcher Dateimanager oben im Dock steht.")
        case .themes: String(localized: "Das Aussehen der ganzen Shell aus einer CSS-Datei.")
        case .updates: String(localized: "Wie ApolloShell sich auf dem neuesten Stand hält.")
        case .system: String(localized: "Netzwerk, Bluetooth, Ton, Hintergrund und Sprache regelt macOS.")
        case .about: String(localized: "Version, System und Quelltext.")
        }
    }

    var symbol: String {
        switch self {
        case .general: "switch.2"
        case .hotKeys: "command"
        case .bar: "sidebar.left"
        case .utilities: "slider.horizontal.3"
        case .launcher: "magnifyingglass"
        case .dashboard: "square.grid.2x2.fill"
        case .desktop: "clock.fill"
        case .toasts: "bell.badge.fill"
        case .providers: "puzzlepiece.extension.fill"
        case .themes: "paintpalette.fill"
        case .updates: "arrow.down.circle.fill"
        case .system: "gearshape.fill"
        case .about: "info"
        }
    }

    /// Kachelfarbe wie in den Systemeinstellungen: jede Seite ihre eigene.
    var tint: Color {
        switch self {
        case .general: .gray
        case .hotKeys: .pink
        case .bar: .blue
        case .utilities: .green
        case .launcher: .purple
        case .dashboard: .indigo
        case .desktop: .teal
        case .toasts: .red
        case .providers: .orange
        case .themes: .pink
        case .updates: .indigo
        case .system, .about: .gray
        }
    }

    var section: NexusSection {
        switch self {
        case .general, .hotKeys: .general
        case .bar, .utilities, .launcher, .dashboard, .desktop, .themes: .panels
        case .toasts, .providers, .updates: .services
        case .system: .system
        case .about: .about
        }
    }

    /// Zusaetzliche Suchwoerter (Caelestia: "Search settings").
    var keywords: [String] {
        switch self {
        case .general: ["autostart", "anmeldung", "anmeldeobjekte", "login", "bedienungshilfen", "freigabe",
                        "berechtigung", "system events", "datenschutz"]
        case .hotKeys: ["hotkey", "kürzel", "tastatur", "shortcut", "launcher", "f20", "hyper", "spotlight", "karabiner"]
        case .bar: ["taskbar", "spaces", "dock", "uhr", "datum", "status", "wlan", "akku", "cpu", "wetter",
                    "medien", "abstand", "vorlage", "baustein", "app", "bildschirm", "monitor", "anzeige"]
        case .utilities: ["utilities", "schnellschalter", "kontrollzentrum", "karten", "wach halten", "ton", "knopf",
                          "kurzbefehl", "fokus", "link", "app", "bildschirm", "ausblenden", "vorlage"]
        case .launcher: ["apps", "angeheftet", "favoriten", "pinned", "reihenfolge"]
        case .dashboard: ["wetter", "ort", "standort", "reiter", "karten", "kalender", "kalenderwoche", "uhr", "medien",
                          "ressourcen", "benutzer", "leistung", "vorlage"]
        case .desktop: ["uhr", "hintergrund", "desktop"]
        case .toasts: ["mitteilungen", "toasts", "akku", "ladegerät", "audio"]
        case .providers: ["wetter", "open-meteo", "met norway", "yr", "wttr", "quelle", "dateimanager", "finder",
                          "forklift"]
        case .themes: ["theme", "farbe", "farben", "aussehen", "css", "verlauf", "gradient", "schrift",
                       "dunkel", "hell", "importieren"]
        case .updates: ["update", "aktualisierung", "version", "sparkle", "homebrew", "brew", "neustart",
                        "release"]
        case .system: ["netzwerk", "bluetooth", "ton", "audio", "hintergrund", "sprache", "updates"]
        case .about: ["version", "macos", "laufzeit", "quelltext"]
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return ([title, subtitle] + keywords).contains { $0.localizedStandardContains(q) }
    }
}

/// Welche Seite offen ist und was in der Suche steht (Caelestia: NexusState).
@MainActor
@Observable
final class NexusState {
    var page: NexusPage? = .bar
    var search = ""
}

/// Das Fenster: Seitenleiste links, Seite rechts - aufgebaut wie die
/// Systemeinstellungen (NavigationSplitView, gruppierte Formulare). Das
/// Liquid-Glass der Seitenleiste bringt macOS 26 selbst mit.
struct NexusView: View {
    @Bindable var state: NexusState
    let settings: ShellSettingsStore
    let pinned: NexusPinnedModel
    let weather: NexusWeatherModel
    let providers: NexusProvidersModel
    let system: NexusSystemInfo
    let shell: NexusShellParts

    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        NavigationSplitView {
            NexusSidebar(state: state)
                .searchable(text: $state.search, placement: .sidebar, prompt: "Suchen")
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            NexusDetail(page: state.page ?? .bar, settings: settings, pinned: pinned, weather: weather,
                        providers: providers, system: system, shell: shell)
        }
        .frame(minWidth: 680, minHeight: 440)
        // Mit Theme faerbt `--apollo-surface-color` auch das Fenster. Ohne
        // Theme bleibt es beim Fenster von macOS, samt Glas der Seitenleiste.
        .themedWindowBackground(style)
    }
}

/// Was die Seiten "Allgemein", "Tastenkürzel" und "Über" von der Shell
/// brauchen: Kuerzel, Autostart, Freigaben und den Weg zur Einfuehrung.
struct NexusShellParts {
    let hotKeys: HotKeyCenter
    let autostart: OnboardingAutostartModel
    let permissions: OnboardingPermissions
    let updates: UpdateController
    let themes: ThemeStore?
    var showOnboarding: @MainActor () -> Void = {}
}

/// Seitenleiste (Caelestia: NavPane/NavLocations): Seiten nach Gruppen, mit
/// Suche gefiltert. Eine Gruppe ohne Treffer verschwindet ganz.
struct NexusSidebar: View {
    @Bindable var state: NexusState

    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        List(selection: $state.page) {
            ForEach(NexusSection.allCases) { section in
                let pages = NexusPage.allCases.filter { $0.section == section && $0.matches(state.search) }
                if !pages.isEmpty {
                    Section {
                        ForEach(pages) { page in
                            Label {
                                Text(page.title)
                            } icon: {
                                NexusTile(symbol: page.symbol, tint: page.tint, size: 22)
                            }
                            .tag(page)
                        }
                    } header: {
                        if let title = section.title { Text(title) }
                    }
                }
            }
        }
        .themedWindowBackground(style)
    }
}

/// Rechte Seite fuer die gewaehlte Seite.
struct NexusDetail: View {
    let page: NexusPage
    let settings: ShellSettingsStore
    let pinned: NexusPinnedModel
    let weather: NexusWeatherModel
    let providers: NexusProvidersModel
    let system: NexusSystemInfo
    let shell: NexusShellParts

    var body: some View {
        switch page {
        case .general: NexusGeneralPage(store: settings, autostart: shell.autostart, permissions: shell.permissions)
        case .hotKeys: NexusHotKeysPage(store: settings, center: shell.hotKeys)
        case .bar: NexusBarPage(store: settings)
        case .utilities: UtilitiesEditorPage(store: settings)
        case .launcher: NexusLauncherPage(model: pinned)
        case .dashboard: NexusDashboardPage(store: settings, model: weather)
        case .desktop: NexusDesktopPage(store: settings)
        case .toasts: NexusToastsPage(store: settings)
        case .providers: NexusProvidersPage(store: settings, model: providers)
        case .themes: NexusThemesPage(store: settings, themes: shell.themes)
        case .updates: NexusUpdatesPage(store: settings, updates: shell.updates)
        case .system: NexusSystemPage()
        case .about: NexusAboutPage(system: system, showOnboarding: shell.showOnboarding)
        }
    }
}

// MARK: - Bausteine

/// Farbige Kachel mit weissem Symbol, wie die Seitensymbole der
/// Systemeinstellungen.
struct NexusTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// Gruppiertes Formular mit der Kopfkarte oben (grosse Kachel, Titel,
/// Beschreibung) - so beginnen die Seiten der Systemeinstellungen.
struct NexusPageForm<Content: View>: View {
    let page: NexusPage
    var title: String?
    var subtitle: String?
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    NexusTile(symbol: page.symbol, tint: page.tint, size: 52)
                        .padding(.bottom, 4)
                    Text(title ?? page.title)
                        .font(.title2.weight(.bold))
                    Text(subtitle ?? page.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            content
        }
        .formStyle(.grouped)
        .themedWindowBackground(style)
        .navigationTitle(page.title)
    }
}

/// Schalter mit Titel und grauer Unterzeile (Caelestia: ToggleRow mit
/// text/subtext). Immer als Schalter, nicht als Kaestchen.
struct NexusToggle: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
            if let subtitle { Text(subtitle) }
        }
        .toggleStyle(.switch)
    }
}

/// Zeile, die einen Bereich der Systemeinstellungen oeffnet.
struct NexusSystemLink: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let symbol: String
    let tint: Color
    /// `nil`: die Systemeinstellungen ohne Bereich.
    let pane: NexusSystemSettings.Pane?

    var body: some View {
        Button {
            NexusSystemSettings.open(pane)
        } label: {
            HStack(spacing: 10) {
                NexusTile(symbol: symbol, tint: tint, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("In den Systemeinstellungen öffnen")
    }
}

/// Spruenge in die Systemeinstellungen.
///
/// Die Bereichs-Kennungen sind die Bundle-IDs der Einstellungs-Erweiterungen
/// in /System/Library/ExtensionKit/Extensions (gemessen 14.09., macOS 26.6).
/// Ohne Bereich wird die App ueber ihre Bundle-ID geoeffnet: das klappt
/// sicher, egal wie sie nach Updates heisst oder wo sie liegt.
enum NexusSystemSettings {
    enum Pane: String {
        case wallpaper = "com.apple.Wallpaper-Settings.extension"
        case appearance = "com.apple.Appearance-Settings.extension"
        case network = "com.apple.Network-Settings.extension"
        case bluetooth = "com.apple.BluetoothSettings"
        case sound = "com.apple.Sound-Settings.extension"
        case notifications = "com.apple.Notifications-Settings.extension"
        case softwareUpdate = "com.apple.Software-Update-Settings.extension"
        case language = "com.apple.Localization-Settings.extension"
        case about = "com.apple.SystemProfiler.AboutExtension"
        /// Datenschutz & Sicherheit > Bedienungshilfen (Anker aus den
        /// Suchbegriffen der Erweiterung, gemessen 14.09., macOS 26.6).
        case accessibility = "com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
    }

    static func open(_ pane: Pane?) {
        if let pane, let url = URL(string: "x-apple.systempreferences:\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
            return
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }
}
