import AppKit
import ApolloShellCore
import UniformTypeIdentifiers

/// The settings half of the Nexus menu (design/2026-09-21-menubar-nexus.md,
/// task 2): what the Nexus pages held, as submenus with check marks.
///
/// Every item reads and writes the same settings the pages wrote; the parts
/// that react to them (bar, clock, toasts, Dock, updates) observe the store
/// themselves. Built anew on every opening, so the check marks always follow
/// the store.
@MainActor
struct NexusMenuSettings {
    let settings: ShellSettingsStore
    let themes: ThemeStore?
    let updates: UpdateController?
    let autostart: OnboardingAutostartModel?
    /// Failures (a theme that cannot be added) go here instead of an alert.
    let report: @MainActor (_ title: String, _ message: String) -> Void

    static let releasesPage = URL(string: "https://github.com/Silvertree2010/ApolloShell/releases")!

    func append(to menu: NSMenu) {
        menu.addItem(submenu(String(localized: "Bar"), barMenu()))
        if let themes { menu.addItem(submenu(String(localized: "Themes"), themesMenu(themes))) }
        menu.addItem(submenu(String(localized: "Toasts"), toastsMenu()))
        menu.addItem(submenu(String(localized: "Weather Provider"), weatherMenu()))
        menu.addItem(submenu(String(localized: "File Manager"), fileManagerMenu()))
        menu.addItem(.separator())
        menu.addItem(toggle(String(localized: "Desktop Clock"), settings.settings.background.desktopClock) {
            settings.settings.background.desktopClock = $0
        })
        menu.addItem(toggle(String(localized: "Hide Apple's Dock"), settings.settings.appleDockHiding.hideWhileRunning) {
            settings.settings.appleDockHiding.hideWhileRunning = $0
        })
        menu.addItem(toggle(String(localized: "Keep Awake with the Lid Closed"), settings.settings.keepAwake.lidClosed) {
            settings.settings.keepAwake.lidClosed = $0
        })
        if LidAwakeRule.isInstalled {
            let remove = ClosureMenuItem(String(localized: "Remove Password-Free Sleep Rule…")) {
                LidAwakeRule.remove { _ in }
            }
            remove.indentationLevel = 1
            menu.addItem(remove)
        }
        if let autostart {
            autostart.refresh()
            let state = autostart.state
            let item = toggle(String(localized: "Start at Login"), state.isOn) { autostart.setEnabled($0) }
            item.isEnabled = state.canToggle
            if let note = state.note { item.toolTip = note }
            menu.addItem(item)
        }
        if let updates { menu.addItem(submenu(String(localized: "Updates"), updatesMenu(updates))) }
    }

    // MARK: - Bar

    private func barMenu() -> NSMenu {
        let menu = plainMenu()
        menu.addItem(header(String(localized: "Screens")))
        let choice = settings.settings.bar.screens
        menu.addItem(radio(String(localized: "All"), choice == .all) { settings.settings.bar.screens = .all })
        menu.addItem(radio(String(localized: "Main Display Only"), choice == .primary) {
            settings.settings.bar.screens = .primary
        })
        // Identical screens cannot be told apart for this setting: one row each.
        var seen: Set<String> = []
        let screens = ShellScreens.current().map(\.info).filter { seen.insert($0.key).inserted }
        for screen in screens {
            menu.addItem(radio(screen.name, choice == .single(screen.key)) {
                settings.settings.bar.screens = .single(screen.key)
            })
        }
        // The remembered screen stays choosable while it is unplugged.
        if case .single(let key) = choice, !screens.contains(where: { $0.key == key }) {
            menu.addItem(radio(String(localized: "\(key) (not connected)"), true) {})
        }
        menu.addItem(.separator())
        menu.addItem(header(String(localized: "Background")))
        for background in BarBackground.allCases {
            menu.addItem(radio(Self.title(background), settings.settings.bar.background == background) {
                settings.settings.bar.background = background
            })
        }
        return menu
    }

    static func title(_ background: BarBackground) -> String {
        switch background {
        case .material: String(localized: "Material")
        case .glass: String(localized: "Liquid Glass")
        case .tintedGlass: String(localized: "Liquid Glass, Tinted")
        case .fixedGlass: String(localized: "Liquid Glass on a Solid Fill")
        }
    }

    // MARK: - Themes

    private func themesMenu(_ themes: ThemeStore) -> NSMenu {
        let menu = plainMenu()
        menu.addItem(radio(String(localized: "No Theme"), themes.selection == nil) { themes.select(nil) })
        for theme in themes.available {
            let item = radio(theme.title, themes.selection == theme.identifier) { themes.select(theme.identifier) }
            if !theme.issues.isEmpty {
                item.toolTip = theme.issues.prefix(8).map(\.description).joined(separator: "\n")
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(String(localized: "Add Theme…")) { importTheme(into: themes) })
        menu.addItem(ClosureMenuItem(String(localized: "Show Folder in Finder")) { themes.revealFolder() })
        menu.addItem(ClosureMenuItem(String(localized: "Read Again")) { themes.reload() })
        return menu
    }

    private func importTheme(into themes: ThemeStore) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "css") ?? .plainText, .folder]
        panel.prompt = String(localized: "Add")
        // An accessory app: without activating, the panel opens behind
        // whatever app is in front.
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let name = try themes.importTheme(from: url)
            themes.select(name)
        } catch {
            report(String(localized: "Theme not added"), error.localizedDescription)
        }
    }

    // MARK: - Toasts

    private func toastsMenu() -> NSMenu {
        let menu = plainMenu()
        let toasts = settings.settings.toasts
        menu.addItem(toggle(String(localized: "Charger"), toasts.chargingChanged) {
            settings.settings.toasts.chargingChanged = $0
        })
        menu.addItem(toggle(String(localized: "Battery Warnings"), toasts.batteryWarnings) {
            settings.settings.toasts.batteryWarnings = $0
        })
        menu.addItem(toggle(String(localized: "Audio Output"), toasts.audioOutputChanged) {
            settings.settings.toasts.audioOutputChanged = $0
        })
        menu.addItem(toggle(String(localized: "Audio Input"), toasts.audioInputChanged) {
            settings.settings.toasts.audioInputChanged = $0
        })
        return menu
    }

    // MARK: - Providers

    private func weatherMenu() -> NSMenu {
        let menu = plainMenu()
        let chosen = settings.settings.providers.weather.provider().id
        for id in WeatherProviderID.allCases {
            let provider = id.provider()
            let item = radio(provider.attribution.name, id == chosen) { settings.settings.providers.weather = id }
            item.toolTip = provider.capabilities.summary
            menu.addItem(item)
        }
        return menu
    }

    private func fileManagerMenu() -> NSMenu {
        let menu = plainMenu()
        let setting = settings.settings.providers.fileManager
        let installed: (String) -> Bool = Self.isInstalled
        let automatic = ProviderFileManager.automatic(isInstalled: installed)
        menu.addItem(radio(String(localized: "Automatic (\(Self.name(for: automatic)))"), setting == nil) {
            settings.settings.providers.fileManager = nil
        })
        for id in ProviderFileManager.choices(setting: setting, isInstalled: installed) {
            let item = radio(Self.name(for: id), setting == id) { settings.settings.providers.fileManager = id }
            item.isEnabled = installed(id)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(String(localized: "Other App…")) { chooseFileManager() })
        return menu
    }

    private func chooseFileManager() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Choose")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let id = Bundle(url: url)?.bundleIdentifier else {
            report(String(localized: "File manager not changed"), String(localized: "That app has no bundle ID."))
            return
        }
        settings.settings.providers.fileManager = id
    }

    private static func isInstalled(_ id: String) -> Bool {
        id == ProviderFileManager.finder || NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    private static func name(for id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Updates

    private func updatesMenu(_ updates: UpdateController) -> NSMenu {
        let menu = plainMenu()
        menu.addItem(header(Self.statusLine(updates.status)))
        if updates.isReadyToInstall {
            menu.addItem(ClosureMenuItem(String(localized: "Restart to Update")) { updates.installNowIfReady() })
        }
        let check = ClosureMenuItem(String(localized: "Check Now")) { updates.checkNow() }
        check.isEnabled = updates.status != .checking && updates.status != .unavailable
        menu.addItem(check)
        menu.addItem(.separator())
        menu.addItem(toggle(String(localized: "Check Automatically"), settings.settings.updates.checkAutomatically) {
            settings.settings.updates.checkAutomatically = $0
        })
        if updates.canUpdateItself {
            menu.addItem(toggle(String(localized: "Install Automatically"), settings.settings.updates.installAutomatically) {
                settings.settings.updates.installAutomatically = $0
            })
        } else {
            menu.addItem(ClosureMenuItem(String(localized: "Copy Upgrade Command")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(updates.upgradeCommand, forType: .string)
            })
        }
        menu.addItem(.separator())
        let notes: URL = if case let .found(_, page?) = updates.status { page } else { Self.releasesPage }
        menu.addItem(ClosureMenuItem(String(localized: "Release Notes")) { NSWorkspace.shared.open(notes) })
        return menu
    }

    static func statusLine(_ status: UpdateController.Status) -> String {
        switch status {
        case .idle: String(localized: "Not checked yet")
        case .checking: String(localized: "Checking…")
        case .upToDate: String(localized: "Up to date")
        case let .found(version, _): String(localized: "Version \(version) available")
        case let .ready(version): String(localized: "Version \(version) ready to install")
        case .failed: String(localized: "Last check failed")
        case .unavailable: String(localized: "Updates unavailable in this build")
        }
    }

    // MARK: - Building blocks

    private func plainMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func header(_ title: String) -> NSMenuItem {
        NSMenuItem.sectionHeader(title: title)
    }

    private func toggle(_ title: String, _ isOn: Bool, set: @escaping @MainActor (Bool) -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title) { set(!isOn) }
        item.state = isOn ? .on : .off
        return item
    }

    private func radio(_ title: String, _ selected: Bool, choose: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title) { choose() }
        item.state = selected ? .on : .off
        return item
    }
}
