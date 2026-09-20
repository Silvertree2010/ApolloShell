import AppKit
import ApolloShellCore
import SwiftUI

/// The groups of the sidebar, after Caelestia's categories (PageRegistry:
/// appearance, connectivity, system, shell, about).
///
/// Caelestia nests: "Panels" is one page with subpages (Dashboard, Taskbar,
/// Launcher, ...). The System Settings of macOS have a flat sidebar; so the
/// subpages stand right under the heading "Panels" here. What macOS handles
/// itself (network, Bluetooth, sound, background, language - pages of their
/// own in Caelestia) is one page with jumps into System Settings, not a
/// rebuild.
enum NexusSection: CaseIterable, Identifiable {
    case general, panels, services, system, about

    var id: Self { self }

    var title: String? {
        switch self {
        // The topmost group without a heading, as in System Settings.
        case .general: nil
        case .panels: String(localized: "Panels")
        case .services: String(localized: "Services")
        case .system: String(localized: "macOS")
        case .about: nil
        }
    }
}

/// One page of Nexus. The title and the subtitle as in Caelestia's
/// PageRegistry (label, description).
enum NexusPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general, hotKeys, bar, launcher, desktop, themes, toasts, providers, updates, system, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .hotKeys: String(localized: "Keyboard Shortcuts")
        case .bar: String(localized: "Bar")
        case .launcher: String(localized: "Launcher")
        case .desktop: String(localized: "Desktop")
        case .toasts: String(localized: "Toasts")
        case .providers: String(localized: "Providers")
        case .themes: String(localized: "Themes")
        case .updates: String(localized: "Updates")
        case .system: String(localized: "System Settings")
        case .about: String(localized: "About")
        }
    }

    var subtitle: String {
        switch self {
        case .general: String(localized: "Start at login and the permissions ApolloShell needs from macOS.")
        case .hotKeys: String(localized: "Global shortcuts for Launcher, Dashboard, Control Centre and Nexus.")
        case .bar: String(localized: "The building blocks of the bar on the left: arrange, add, configure.")
        case .launcher: String(localized: "The pinned apps that appear at the top without a search text.")
        case .desktop: String(localized: "The clock at the bottom right of the desktop.")
        case .toasts: String(localized: "Which events show a toast at the bottom right.")
        case .providers: String(localized: "Where the weather comes from and which file manager sits at the top of the Dock.")
        case .themes: String(localized: "The look of the whole shell, from one CSS file.")
        case .updates: String(localized: "How ApolloShell keeps itself up to date.")
        case .system: String(localized: "macOS handles network, Bluetooth, sound, background and language.")
        case .about: String(localized: "Version, system and source code.")
        }
    }

    var symbol: String {
        switch self {
        case .general: "switch.2"
        case .hotKeys: "command"
        case .bar: "sidebar.left"
        case .launcher: "magnifyingglass"
        case .desktop: "clock.fill"
        case .toasts: "bell.badge.fill"
        case .providers: "puzzlepiece.extension.fill"
        case .themes: "paintpalette.fill"
        case .updates: "arrow.down.circle.fill"
        case .system: "gearshape.fill"
        case .about: "info"
        }
    }

    /// The tile color as in System Settings: every page its own.
    var tint: Color {
        switch self {
        case .general: .gray
        case .hotKeys: .pink
        case .bar: .blue
        case .launcher: .purple
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
        case .bar, .launcher, .desktop, .themes: .panels
        case .toasts, .providers, .updates: .services
        case .system: .system
        case .about: .about
        }
    }

    /// Extra search words (Caelestia: "Search settings").
    var keywords: [String] {
        switch self {
        case .general: ["autostart", "anmeldung", "anmeldeobjekte", "login", "bedienungshilfen", "freigabe",
                        "berechtigung", "system events", "datenschutz", "wach halten", "deckel", "zugeklappt",
                        "bearbeiten", "oberfläche", "kontrollzentrum", "dashboard"]
        case .hotKeys: ["hotkey", "kürzel", "tastatur", "shortcut", "launcher", "f20", "hyper", "spotlight", "karabiner"]
        case .bar: ["taskbar", "spaces", "dock", "uhr", "datum", "status", "wlan", "akku", "cpu", "wetter",
                    "medien", "abstand", "vorlage", "baustein", "app", "bildschirm", "monitor", "anzeige",
                    "ort", "orte", "standort", "favoriten"]
        case .launcher: ["apps", "angeheftet", "favoriten", "pinned", "reihenfolge"]
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

/// Which page is open and what stands in the search (Caelestia: NexusState).
@MainActor
@Observable
final class NexusState {
    var page: NexusPage? = .bar
    var search = ""
}

/// The window: the sidebar on the left, the page on the right - built like
/// System Settings (NavigationSplitView, grouped forms). The Liquid Glass of
/// the sidebar comes with macOS 26 itself.
struct NexusView: View {
    @Bindable var state: NexusState
    let settings: ShellSettingsStore
    let pinned: NexusPinnedModel
    let weather: NexusWeatherModel
    let providers: NexusProvidersModel
    let system: NexusSystemInfo
    let shell: NexusShellParts

    @Environment(\.shellStyle) private var style

    var body: some View {
        NavigationSplitView {
            NexusSidebar(state: state, beginEditing: shell.beginEditing)
                .searchable(text: $state.search, placement: .sidebar, prompt: "Search")
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            NexusDetail(page: state.page ?? .bar, settings: settings, pinned: pinned, weather: weather,
                        providers: providers, system: system, shell: shell)
        }
        .frame(minWidth: 680, minHeight: 440)
        // With a theme, `--apollo-surface-color` colors the window too.
        // Without a theme it stays the macOS window, glass sidebar and all.
        .themedWindowBackground(style)
    }
}

/// What the pages "General", "Shortcuts" and "About" need from the shell:
/// the shortcuts, autostart, the permissions and the way to the introduction.
struct NexusShellParts {
    let hotKeys: HotKeyCenter
    let autostart: OnboardingAutostartModel
    let permissions: OnboardingPermissions
    let updates: UpdateController
    let themes: ThemeStore?
    var showOnboarding: @MainActor () -> Void = {}
    /// The “Edit Interface” button, on every page (`Nexus.beginEditing`).
    var beginEditing: @MainActor () -> Void = {}
}

/// The sidebar (Caelestia: NavPane/NavLocations): the pages by group,
/// filtered by the search. A group without a hit disappears entirely.
struct NexusSidebar: View {
    @Bindable var state: NexusState
    /// The button in the footer, on every page (spec section 4): starts the
    /// global edit mode for the dashboard and the control centre.
    let beginEditing: @MainActor () -> Void

    @Environment(\.shellStyle) private var style

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
        .safeAreaInset(edge: .bottom) {
            Button {
                beginEditing()
            } label: {
                Label("Edit Interface", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(10)
        }
    }
}

/// The right-hand side for the chosen page.
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
        case .bar: NexusBarPage(store: settings, weather: weather)
        case .launcher: NexusLauncherPage(model: pinned)
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

// MARK: - Building blocks

/// A colored tile with a white symbol, like the page symbols of System
/// Settings.
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

/// A grouped form with the header card at the top (a big tile, a title, a
/// description) - that is how the pages of System Settings begin.
struct NexusPageForm<Content: View>: View {
    let page: NexusPage
    var title: String?
    var subtitle: String?
    @ViewBuilder let content: Content

    @Environment(\.shellStyle) private var style

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

/// A switch with a title and a grey subtitle (Caelestia: ToggleRow with
/// text/subtext). Always as a switch, never as a checkbox.
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

/// A row that opens an area of System Settings.
struct NexusSystemLink: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let symbol: String
    let tint: Color
    /// `nil`: System Settings without an area.
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
        .help("Open in System Settings")
    }
}

/// Jumps into System Settings.
///
/// The area ids are the bundle IDs of the settings extensions in
/// /System/Library/ExtensionKit/Extensions (measured 14.09., macOS 26.6).
/// Without an area the app is opened through its bundle ID: that works for
/// sure, no matter what it is called after updates or where it lies.
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
        /// Privacy & Security > Accessibility (the anchor out of the search
        /// terms of the extension, measured 14.09., macOS 26.6).
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
