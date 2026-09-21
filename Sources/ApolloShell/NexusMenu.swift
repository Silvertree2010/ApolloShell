import AppKit
import ApolloShellCore
import os

/// Nexus in the menu bar: the one way into the shell that is always there -
/// in full screen, on a screen without a bar, with no shortcut set
/// (design/2026-09-21-menubar-nexus.md, task 1).
///
/// On top the four openers, below them the settings (`NexusMenuSettings`),
/// at the bottom the windows and Quit. The openers only call what the bar
/// buttons and shortcuts call; no logic of its own lives here.
///
/// Its place survives restarts through the autosave name. The item is not
/// removed when hidden, only made invisible: `NSStatusBar.removeStatusItem`
/// would forget the place along with it.
@MainActor
final class NexusMenu: NSObject, NSMenuDelegate {
    /// What the items do. Set by the app delegate, which owns the parts.
    struct Actions {
        var dashboard: @MainActor () -> Void = {}
        var utilities: @MainActor () -> Void = {}
        var launcher: @MainActor () -> Void = {}
        var editInterface: @MainActor () -> Void = {}
        var introduction: @MainActor () -> Void = {}
        var shortcuts: @MainActor () -> Void = {}
        /// While the global edit mode runs the openers stay greyed out, like
        /// their shortcuts do nothing then.
        var isEditing: @MainActor () -> Bool = { false }
    }

    static let iconID = "menubar-nexus"
    /// Menu bar icons are drawn at 18 pt; larger ones get clipped.
    private static let iconSize = NSSize(width: 18, height: 18)
    private static let autosaveName = "ApolloShell.Nexus"

    private let settings: ShellSettingsStore
    private weak var themes: ThemeStore?
    /// Settable later: the introduction comes about after the menu.
    var actions: Actions
    private let settingsMenu: NexusMenuSettings
    private let item: NSStatusItem
    private let log = Logger(category: "menubar")
    private var shownObservation: Task<Void, Never>?
    private var themeObservation: Task<Void, Never>?

    init(settings: ShellSettingsStore, themes: ThemeStore?, actions: Actions, settingsMenu: NexusMenuSettings) {
        self.settings = settings
        self.themes = themes
        self.actions = actions
        self.settingsMenu = settingsMenu
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.autosaveName = Self.autosaveName
        item.button?.toolTip = "ApolloShell"
        item.button?.setAccessibilityLabel("Nexus")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        // AppKit restores a visibility of its own under the autosave name;
        // the setting wins, and so does every later change to it. The loops
        // live as long as the app (AppDelegate holds the menu).
        shownObservation = Task { [weak self, settings] in
            for await shown in Observations({ settings.settings.menuBar.shown }) {
                self?.item.isVisible = shown
            }
        }
        themeObservation = Task { [weak self, themes] in
            for await _ in Observations({ themes?.theme }) {
                self?.updateIcon()
            }
        }
    }

    deinit {
        shownObservation?.cancel()
        themeObservation?.cancel()
    }

    /// Opens the menu: under the item when it stands in the menu bar,
    /// otherwise at the pointer (hidden, or pushed behind the notch - the
    /// menu itself does not depend on the item). For the Nexus shortcut, the
    /// settings button of the control centre and a second launch.
    func open() {
        if item.isVisible, let button = item.button, button.window?.isVisible == true,
           button.window?.screen != nil {
            button.performClick(nil)
            return
        }
        guard let menu = item.menu else { return }
        menuNeedsUpdate(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Shows the item again - the way back for whoever hid it and opens the
    /// app a second time.
    func reveal() {
        guard !settings.settings.menuBar.shown else { return }
        log.notice("menu bar item shown again after a second launch")
        settings.settings.menuBar.shown = true
    }

    // MARK: - Icon

    /// The theme's image when it brings one, otherwise the SF Symbol from the
    /// catalogue. The theme image is a template only when the theme asks for
    /// monochrome icons, as everywhere else (`ThemedIcon`).
    private func updateIcon() {
        item.button?.image = Self.icon(theme: themes?.theme)
    }

    private static func icon(theme: Theme?) -> NSImage? {
        if let url = theme?.icon(iconID), let source = ThemedIconCache.image(at: url),
           let image = source.copy() as? NSImage {
            image.size = fitted(image.size)
            image.isTemplate = ShellStyle(theme: theme ?? .standard, dark: false).tintsThemeIcons
            return image
        }
        let fallback = ThemeIconCatalog.standard.descriptor(for: iconID)?.fallback ?? "circle.hexagongrid"
        let image = NSImage(systemSymbolName: fallback, accessibilityDescription: "Nexus")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        image?.isTemplate = true
        return image
    }

    /// Keeps the proportions of a theme image inside 18 x 18 pt.
    private static func fitted(_ size: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0 else { return iconSize }
        let scale = min(iconSize.width / size.width, iconSize.height / size.height)
        return NSSize(width: size.width * scale, height: size.height * scale)
    }

    // MARK: - Menu

    /// Built on every opening, so that the greyed-out state follows the edit mode.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let editing = actions.isEditing()
        let openers: [(String, @MainActor () -> Void)] = [
            (String(localized: "Dashboard"), actions.dashboard),
            (String(localized: "Control Centre"), actions.utilities),
            (String(localized: "Launcher"), actions.launcher),
            (String(localized: "Edit Interface"), actions.editInterface),
        ]
        for (title, action) in openers {
            let entry = ClosureMenuItem(title) { action() }
            entry.isEnabled = !editing
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        settingsMenu.append(to: menu)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(String(localized: "Shortcuts…")) { [actions] in actions.shortcuts() })
        menu.addItem(ClosureMenuItem(String(localized: "Introduction…")) { [actions] in actions.introduction() })
        menu.addItem(ClosureMenuItem(String(localized: "Open System Settings")) { SystemSettings.open(nil) })
        menu.addItem(ClosureMenuItem(String(localized: "About ApolloShell")) {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(String(localized: "Hide from Menu Bar")) { [weak self] in
            self?.settings.settings.menuBar.shown = false
        })
        let hint = NSMenuItem(title: String(localized: "Open ApolloShell again to bring it back"),
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "Quit ApolloShell"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }
}
