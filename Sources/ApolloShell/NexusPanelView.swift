import AppKit
import ApolloShellCore
import SwiftUI
import UniformTypeIdentifiers

/// The pages of the Nexus panel, as tabs of symbols along the top (modelled
/// on Vorssaint's menu bar panel, which Andrin showed on 21.09.).
enum NexusTab: String, CaseIterable, Identifiable {
    case bar, themes, toasts, providers, system, updates

    var id: Self { self }

    var title: String {
        switch self {
        case .bar: String(localized: "Bar")
        case .themes: String(localized: "Themes")
        case .toasts: String(localized: "Toasts")
        case .providers: String(localized: "Providers")
        case .system: String(localized: "System")
        case .updates: String(localized: "Updates")
        }
    }

    var symbol: String {
        switch self {
        case .bar: "sidebar.left"
        case .themes: "paintpalette"
        case .toasts: "bell.badge"
        case .providers: "cloud.sun"
        case .system: "gearshape"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

/// What the panel reads and writes. The settings live in the store as
/// before; the panel is only a different face for them.
@MainActor
@Observable
final class NexusPanelModel {
    var tab: NexusTab = .bar
    /// Refreshed on every opening: whether the password-free sleep rule lies
    /// on this Mac (one stat).
    var lidRuleInstalled = false
    /// Heights measured by the view; the window follows their sum, so the
    /// panel is as tall as its page (up to `NexusPanel.maxHeight`).
    var chromeHeight: CGFloat = 0
    var pageHeight: CGFloat = 0

    /// The height the whole panel wants: padding, the openers and tabs,
    /// the page, the footer, and the gaps between them.
    var wantedHeight: CGFloat {
        chromeHeight + pageHeight + 2 * NexusPanelView.padding + 3 * NexusPanelView.spacing
    }

    @ObservationIgnored let settings: ShellSettingsStore
    @ObservationIgnored let themes: ThemeStore?
    @ObservationIgnored let updates: UpdateController?
    @ObservationIgnored let autostart: OnboardingAutostartModel?
    /// Set by `NexusMenu`: close the panel, then do the thing.
    @ObservationIgnored var actions = NexusMenu.Actions()
    @ObservationIgnored var close: @MainActor () -> Void = {}
    @ObservationIgnored var report: @MainActor (_ title: String, _ message: String) -> Void = { _, _ in }

    init(settings: ShellSettingsStore, themes: ThemeStore?, updates: UpdateController?,
         autostart: OnboardingAutostartModel?) {
        self.settings = settings
        self.themes = themes
        self.updates = updates
        self.autostart = autostart
    }

    func refresh() {
        lidRuleInstalled = LidAwakeRule.isInstalled
        autostart?.refresh()
    }

    /// Closes first, so the panel does not stand over what opens.
    func run(_ action: @escaping @MainActor () -> Void) {
        close()
        action()
    }

    static let releasesPage = URL(string: "https://github.com/Silvertree2010/ApolloShell/releases")!
}

/// The panel itself: the openers, the tabs, one page of cards, and at the
/// bottom Shortcuts and Quit.
struct NexusPanelView: View {
    static let width: CGFloat = 380
    static let padding: CGFloat = 14
    static let spacing: CGFloat = 12

    @Bindable var model: NexusPanelModel
    @Environment(\.shellStyle) private var style
    @State private var top: CGFloat = 0
    @State private var bottom: CGFloat = 0

    var body: some View {
        VStack(spacing: Self.spacing) {
            VStack(spacing: Self.spacing) {
                openers
                tabs
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { top = $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.tab.title.uppercased())
                        .font(style.font(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(style.secondaryText)
                        .padding(.leading, 4)
                    page
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.pageHeight = $0 }
            }
            .scrollIndicators(.never)
            footer
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottom = $0 }
        }
        .onChange(of: top + bottom, initial: true) { model.chromeHeight = top + bottom }
        .padding(Self.padding)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(style.paint(.text, or: .primary))
        .tint(style.accent)
    }

    // MARK: - Top

    private var openers: some View {
        let editing = model.actions.isEditing()
        return HStack(spacing: 8) {
            opener("Dashboard", "square.grid.2x2.fill", model.actions.dashboard)
            opener("Control Centre", "slider.horizontal.3", model.actions.utilities)
            opener("Launcher", "magnifyingglass", model.actions.launcher)
            opener("Edit", "pencil", model.actions.editInterface)
        }
        .disabled(editing)
        .opacity(editing ? 0.4 : 1)
    }

    private func opener(_ title: LocalizedStringKey, _ symbol: String,
                        _ action: @escaping @MainActor () -> Void) -> some View {
        Button { model.run(action) } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(style.font(size: 17, weight: .medium))
                    .frame(height: 20)
                Text(title)
                    .font(style.font(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .cardSurface(radius: 14)
            .contentShape(.rect)
        }
        .buttonStyle(NexusPressStyle())
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(NexusTab.allCases) { tab in
                let selected = model.tab == tab
                Button { model.tab = tab } label: {
                    Image(systemName: tab.symbol)
                        .font(style.font(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(selected ? AnyShapeStyle(style.onAccent) : AnyShapeStyle(.primary))
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: style.controlRadius(10), style: .continuous)
                                    .fill(style.accent)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .cardSurface(radius: 14)
    }

    // MARK: - Pages

    @ViewBuilder private var page: some View {
        switch model.tab {
        case .bar: NexusBarPage(model: model)
        case .themes: NexusThemesPage(model: model)
        case .toasts: NexusToastsPage(model: model)
        case .providers: NexusProvidersPage(model: model)
        case .system: NexusSystemPage(model: model)
        case .updates: NexusUpdatesPage(model: model)
        }
    }

    // MARK: - Bottom

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton("Shortcuts…", "keyboard") { model.run(model.actions.shortcuts) }
            footerButton("Quit", "power") { NSApp.terminate(nil) }
        }
    }

    private func footerButton(_ title: LocalizedStringKey, _ symbol: String,
                              action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(style.font(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 34)
                .cardSurface(radius: 12)
                .contentShape(.rect)
        }
        .buttonStyle(NexusPressStyle())
    }
}

// MARK: - Pages

private struct NexusBarPage: View {
    let model: NexusPanelModel

    var body: some View {
        @Bindable var store = model.settings
        let choice = store.settings.bar.screens
        var seen: Set<String> = []
        let screens = ShellScreens.current().map(\.info).filter { seen.insert($0.key).inserted }
        var options: [NexusOption<ScreenChoice>] = [
            .init(.all, String(localized: "All Screens")),
            .init(.primary, String(localized: "Main Display Only")),
        ]
        options += screens.map { .init(.single($0.key), $0.name) }
        if case .single(let key) = choice, !screens.contains(where: { $0.key == key }) {
            options.append(.init(choice, String(localized: "\(key) (not connected)")))
        }
        return VStack(spacing: 8) {
            NexusChoiceCard(symbol: "display.2", title: "Screens",
                            subtitle: "Where the bar stands – and with it the desktop clock and the strip kept clear of windows.",
                            options: options, selected: choice) { store.settings.bar.screens = $0 }
        }
    }
}

private struct NexusThemesPage: View {
    let model: NexusPanelModel

    var body: some View {
        if let themes = model.themes {
            let options = [NexusOption<String?>(nil, String(localized: "No Theme"),
                                                String(localized: "The colours of macOS"))]
                + themes.available.map { theme in
                    NexusOption<String?>(theme.identifier, theme.title, Self.subtitle(theme))
                }
            VStack(spacing: 8) {
                NexusChoiceCard(symbol: "paintpalette", title: "Theme",
                                subtitle: "A change to the file takes effect at once.",
                                options: options, selected: themes.selection) { themes.select($0) }
                NexusCard(symbol: "folder", title: "Theme Folder",
                          subtitle: LocalizedStringKey((themes.folder.path as NSString).abbreviatingWithTildeInPath)) {
                    EmptyView()
                } footer: {
                    HStack(spacing: 6) {
                        NexusSmallButton("Add Theme…") { importTheme(into: themes) }
                        NexusSmallButton("Show in Finder") { themes.revealFolder() }
                        NexusSmallButton("Read Again") { themes.reload() }
                    }
                }
            }
        } else {
            NexusCard(symbol: "paintpalette", title: "Themes",
                      subtitle: "Themes are not available in this build.") { EmptyView() }
        }
    }

    private static func subtitle(_ theme: Theme) -> String? {
        var parts: [String] = []
        if !theme.author.isEmpty { parts.append(theme.author) }
        if !theme.issues.isEmpty { parts.append(String(localized: "\(theme.issues.count) note(s)")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func importTheme(into themes: ThemeStore) {
        model.close()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "css") ?? .plainText, .folder]
        panel.prompt = String(localized: "Add")
        // An accessory app: without activating, the panel opens behind the
        // app in front.
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            themes.select(try themes.importTheme(from: url))
        } catch {
            model.report(String(localized: "Theme not added"), error.localizedDescription)
        }
    }
}

private struct NexusToastsPage: View {
    let model: NexusPanelModel

    var body: some View {
        @Bindable var store = model.settings
        VStack(spacing: 8) {
            NexusSwitchCard(symbol: "powerplug", title: "Charger", subtitle: "Connected or unplugged.",
                            isOn: $store.settings.toasts.chargingChanged)
            NexusSwitchCard(symbol: "battery.25percent", title: "Battery Warnings",
                            subtitle: "On battery, at 20, 10 and 5 %.",
                            isOn: $store.settings.toasts.batteryWarnings)
            NexusSwitchCard(symbol: "hifispeaker", title: "Audio Output",
                            subtitle: "A different output device is chosen.",
                            isOn: $store.settings.toasts.audioOutputChanged)
            NexusSwitchCard(symbol: "mic", title: "Audio Input", subtitle: "A different microphone is chosen.",
                            isOn: $store.settings.toasts.audioInputChanged)
        }
    }
}

private struct NexusProvidersPage: View {
    let model: NexusPanelModel

    var body: some View {
        @Bindable var store = model.settings
        let weather = store.settings.providers.weather.provider().id
        let setting = store.settings.providers.fileManager
        let automatic = ProviderFileManager.automatic(isInstalled: Self.isInstalled)
        let managers = [NexusOption<String?>(nil, String(localized: "Automatic"),
                                             String(localized: "Currently \(Self.name(for: automatic))"))]
            + ProviderFileManager.choices(setting: setting, isInstalled: Self.isInstalled).map { id in
                NexusOption<String?>(id, Self.name(for: id),
                                     Self.isInstalled(id) ? nil : String(localized: "Not installed"))
            }
        return VStack(spacing: 8) {
            NexusChoiceCard(symbol: "cloud.sun", title: "Weather",
                            subtitle: "All without an account. The dashboard picks up a change the next time it opens.",
                            options: WeatherProviderID.allCases.map { id in
                                let provider = id.provider()
                                return .init(id, provider.attribution.name, provider.capabilities.summary)
                            },
                            selected: weather) { store.settings.providers.weather = $0 }
            NexusChoiceCard(symbol: "folder", title: "File Manager",
                            subtitle: "Stands at the top of the bar's Dock in Finder's place.",
                            options: managers, selected: setting) { store.settings.providers.fileManager = $0 } footer: {
                NexusSmallButton("Other App…") { chooseFileManager() }
            }
        }
    }

    private func chooseFileManager() {
        model.close()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Choose")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let id = Bundle(url: url)?.bundleIdentifier else {
            model.report(String(localized: "File manager not changed"), String(localized: "That app has no bundle ID."))
            return
        }
        model.settings.settings.providers.fileManager = id
    }

    static func isInstalled(_ id: String) -> Bool {
        id == ProviderFileManager.finder || NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    static func name(for id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

private struct NexusSystemPage: View {
    let model: NexusPanelModel

    var body: some View {
        @Bindable var store = model.settings
        VStack(spacing: 8) {
            NexusSwitchCard(symbol: "clock", title: "Desktop Clock", subtitle: "Bottom right, behind all windows.",
                            isOn: $store.settings.background.desktopClock)
            NexusSwitchCard(symbol: "dock.rectangle", title: "Hide Apple's Dock",
                            subtitle: "While ApolloShell runs. It comes back when ApolloShell quits.",
                            isOn: $store.settings.appleDockHiding.hideWhileRunning)
            NexusSwitchCard(symbol: "laptopcomputer", title: "Keep Awake with the Lid Closed",
                            subtitle: "Needs your password once; ApolloShell then adds a rule for just this setting.",
                            isOn: $store.settings.keepAwake.lidClosed) {
                if model.lidRuleInstalled {
                    NexusSmallButton("Remove Password-Free Rule…") {
                        LidAwakeRule.remove { _ in model.lidRuleInstalled = LidAwakeRule.isInstalled }
                    }
                }
            }
            if let autostart = model.autostart {
                let state = autostart.state
                NexusSwitchCard(symbol: "power.circle", title: "Start at Login",
                                subtitle: state.note.map { LocalizedStringKey($0) } ?? "Opens ApolloShell when you log in.",
                                isOn: Binding(get: { state.isOn }, set: { autostart.setEnabled($0) }))
                    .disabled(!state.canToggle)
            }
            NexusSwitchCard(symbol: "menubar.rectangle", title: "Show in Menu Bar",
                            subtitle: "Off hides this icon. Open ApolloShell again to bring it back.",
                            isOn: $store.settings.menuBar.shown)
            NexusCard(symbol: "info.circle", title: "ApolloShell", subtitle: LocalizedStringKey(Self.version)) {
                EmptyView()
            } footer: {
                HStack(spacing: 6) {
                    NexusSmallButton("Introduction…") { model.run(model.actions.introduction) }
                    NexusSmallButton("System Settings") { model.run { SystemSettings.open(nil) } }
                    NexusSmallButton("About") {
                        model.run {
                            NSApp.activate()
                            NSApp.orderFrontStandardAboutPanel(nil)
                        }
                    }
                }
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        return NexusText.version(short: info?["CFBundleShortVersionString"] as? String,
                                 build: info?["CFBundleVersion"] as? String)
    }
}

private struct NexusUpdatesPage: View {
    let model: NexusPanelModel

    var body: some View {
        @Bindable var store = model.settings
        if let updates = model.updates {
            VStack(spacing: 8) {
                NexusCard(symbol: "arrow.triangle.2.circlepath", title: LocalizedStringKey(Self.status(updates.status)),
                          subtitle: LocalizedStringKey(updates.lastCheck.map {
                              String(localized: "Last check \($0.formatted(.relative(presentation: .named)))")
                          } ?? String(localized: "Not checked yet"))) {
                    EmptyView()
                } footer: {
                    HStack(spacing: 6) {
                        if updates.isReadyToInstall {
                            NexusSmallButton("Restart to Update", prominent: true) { updates.installNowIfReady() }
                        }
                        NexusSmallButton("Check Now") { updates.checkNow() }
                            .disabled(updates.status == .checking || updates.status == .unavailable)
                        NexusSmallButton("Release Notes") {
                            let page: URL = if case let .found(_, page?) = updates.status { page } else { NexusPanelModel.releasesPage }
                            model.run { NSWorkspace.shared.open(page) }
                        }
                    }
                }
                NexusSwitchCard(symbol: "clock.arrow.circlepath", title: "Check Automatically",
                                subtitle: "Once a day in the background.",
                                isOn: $store.settings.updates.checkAutomatically)
                if updates.canUpdateItself {
                    NexusSwitchCard(symbol: "square.and.arrow.down", title: "Install Automatically",
                                    subtitle: "When you quit, so at the latest when you next log out.",
                                    isOn: $store.settings.updates.installAutomatically)
                } else {
                    NexusCard(symbol: "mug", title: "Homebrew",
                              subtitle: LocalizedStringKey(updates.upgradeCommand)) {
                        EmptyView()
                    } footer: {
                        NexusSmallButton("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(updates.upgradeCommand, forType: .string)
                        }
                    }
                }
            }
        } else {
            NexusCard(symbol: "arrow.triangle.2.circlepath", title: "Updates",
                      subtitle: "Not available in launcher-only mode.") { EmptyView() }
        }
    }

    static func status(_ status: UpdateController.Status) -> String {
        switch status {
        case .idle: String(localized: "Up to date, as far as known")
        case .checking: String(localized: "Checking…")
        case .upToDate: String(localized: "Up to date")
        case let .found(version, _): String(localized: "Version \(version) available")
        case let .ready(version): String(localized: "Version \(version) ready to install")
        case .failed: String(localized: "Last check failed")
        case .unavailable: String(localized: "Updates unavailable in this build")
        }
    }
}

// MARK: - Building blocks

/// A card: symbol, title, one line of explanation, something on the right,
/// and optionally something below (buttons, a list).
struct NexusCard<Accessory: View, Footer: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let footer: () -> Footer
    @Environment(\.shellStyle) private var style

    init(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey?,
         @ViewBuilder accessory: @escaping () -> Accessory,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(style.font(size: 17, weight: .regular))
                    .foregroundStyle(style.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(style.font(size: 14, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(style.font(size: 12))
                            .foregroundStyle(style.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                accessory()
            }
            footer()
                .padding(.leading, 36)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 14)
    }
}

extension NexusCard where Footer == EmptyView {
    init(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey?,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, accessory: accessory) { EmptyView() }
    }
}

/// A card with a switch on the right.
struct NexusSwitchCard<Footer: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @Binding var isOn: Bool
    @ViewBuilder var footer: () -> Footer

    init(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey?, isOn: Binding<Bool>,
         @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
        self.footer = footer
    }

    var body: some View {
        NexusCard(symbol: symbol, title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .toggleStyle(NexusSwitchStyle())
                .labelsHidden()
        } footer: {
            footer()
        }
    }
}

struct NexusOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let subtitle: String?

    init(_ value: Value, _ title: String, _ subtitle: String? = nil) {
        self.value = value
        self.title = title
        self.subtitle = subtitle
    }

    var id: String { "\(value)|\(title)" }
}

/// A card with a list to pick one from, a tick on the chosen row.
struct NexusChoiceCard<Value: Hashable, Footer: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let options: [NexusOption<Value>]
    let selected: Value
    let choose: (Value) -> Void
    @ViewBuilder var footer: () -> Footer
    @Environment(\.shellStyle) private var style

    init(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey?, options: [NexusOption<Value>],
         selected: Value, choose: @escaping (Value) -> Void,
         @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.options = options
        self.selected = selected
        self.choose = choose
        self.footer = footer
    }

    var body: some View {
        NexusCard(symbol: symbol, title: title, subtitle: subtitle) {
            EmptyView()
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options) { option in
                    let isSelected = option.value == selected
                    Button { choose(option.value) } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.title)
                                    .font(style.font(size: 13, weight: isSelected ? .semibold : .regular))
                                if let sub = option.subtitle {
                                    Text(sub)
                                        .font(style.font(size: 11))
                                        .foregroundStyle(style.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 6)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(style.font(size: 12, weight: .bold))
                                    .foregroundStyle(style.accent)
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: style.controlRadius(8), style: .continuous)
                                    .fill(style.accent.opacity(0.14))
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
                footer()
                    .padding(.top, 4)
            }
        }
    }
}

struct NexusSmallButton: View {
    let title: LocalizedStringKey
    var prominent = false
    let action: () -> Void
    @Environment(\.shellStyle) private var style

    init(_ title: LocalizedStringKey, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(style.font(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .foregroundStyle(prominent ? AnyShapeStyle(style.onAccent) : AnyShapeStyle(.primary))
                .background(prominent ? AnyShapeStyle(style.accent) : AnyShapeStyle(Color.primary.opacity(0.10)),
                            in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// A switch drawn by the shell. The system one turns grey in a window that
/// is not the key window - and the panel never becomes one, so every switch
/// that is on would look off-colour. In the accent colour instead, like
/// the quick toggles of the control centre.
struct NexusSwitchStyle: ToggleStyle {
    @Environment(\.shellStyle) private var style
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(style.accent) : AnyShapeStyle(Color.primary.opacity(0.18)))
                .frame(width: 42, height: 24)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .padding(2)
                }
                .animation(.snappy(duration: 0.18), value: configuration.isOn)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
    }
}

/// Darker while pressed, as the bar's buttons.
struct NexusPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
