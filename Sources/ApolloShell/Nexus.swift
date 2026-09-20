import AppKit
import SwiftUI

/// Nexus, the settings window of the shell (Caelestia: modules/nexus). Opens
/// through the settings button in the utilities panel and SUPER+,.
///
/// Unlike every other part, an ordinary window: title bar, close, minimise,
/// resize - like System Settings. The app is an accessory app though (no Dock
/// symbol, never active). So that one can type into the search fields, the
/// window has to become the key window, and that only works while the app is
/// active: `NSApp.activate()` when showing it. On closing, the app that was
/// at the front before gets the focus back, otherwise one would stand in an
/// app without a window.
///
/// Exactly one window: opening it again brings the existing one forward.
/// Closing only hides it (`isReleasedWhenClosed = false`); the app goes on
/// running, since an accessory app does not end with its last window.
@MainActor
final class Nexus: NSObject, NSWindowDelegate {
    private static let frameName = "Nexus"
    private static let defaultSize = NSSize(width: 820, height: 600)

    private let state = NexusState()
    private let settings: ShellSettingsStore
    private let pinned: NexusPinnedModel
    private let weather: NexusWeatherModel
    private let providers = NexusProvidersModel()
    private let shellEditor: ShellEditor
    private var shell: NexusShellParts
    private var window: NexusWindow?
    /// Who was at the front before the opening - gets the focus back on closing.
    private var previousApp: NSRunningApplication?

    /// "Show Introduction" on the About page. Set it before the first opening.
    var onShowOnboarding: @MainActor () -> Void {
        get { shell.showOnboarding }
        set { shell.showOnboarding = newValue }
    }

    init(settings: ShellSettingsStore, hotKeys: HotKeyCenter, autostart: OnboardingAutostartModel,
         permissions: OnboardingPermissions, updates: UpdateController, themes: ThemeStore?,
         shellEditor: ShellEditor, paths: NexusPaths = .live) {
        self.settings = settings
        self.shellEditor = shellEditor
        pinned = NexusPinnedModel(url: paths.pinned)
        weather = NexusWeatherModel.file(url: paths.weather)
        shell = NexusShellParts(hotKeys: hotKeys, autostart: autostart, permissions: permissions,
                                updates: updates, themes: themes)
        super.init()
        // Comes back as soon as the global edit mode ends (Done, Cancel, Esc)
        // - on the same page it stood on at the start. `NSApp.activate()`
        // first: without it the window came forward but without focus when
        // another app became active in between (the scrim, the toolbar and the
        // gallery never take the keyboard themselves) - it then stood visibly,
        // but behind the app that was really active.
        shellEditor.addEndHandler { [weak self] in
            NSApp.activate()
            self?.window?.makeKeyAndOrderFront(nil)
        }
        shell.beginEditing = { [weak self] in self?.beginEditing() }
    }

    /// The “Edit Interface” button (every Nexus page, spec section 4): starts
    /// the global edit mode on the screen of this window and steps aside
    /// itself until it ends.
    func beginEditing() {
        guard let window, window.isVisible else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }
        shellEditor.begin(screen: screen)
        // Only step aside once the mode really runs: `begin` turns down a
        // second start, and Nexus that hid anyway would be gone with
        // nothing to bring it back (`onEnd` never comes).
        guard shellEditor.isEditing else { return }
        window.orderOut(nil)
    }

    func show(page: NexusPage? = nil) {
        if let page { state.page = page }
        let window = self.window ?? makeWindow()
        if !window.isVisible {
            // Read fresh: pinned.json and weather.json may have been changed
            // by hand since the last time.
            pinned.reload()
            weather.reload()
            // Apps for "Other App …" (file manager): newly installed ones count.
            providers.reload()
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NexusWindow {
        let window = NexusWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Nexus"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        // Through SUPER+, out of another space: the window comes there instead
        // of macOS jumping to the space of the window.
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self

        // `shellTheme` sets the tint of the controls by the theme.
        let root = NexusView(state: state, settings: settings, pinned: pinned, weather: weather,
                             providers: providers, system: .read(), shell: shell)
            .shellTheme()
        let hosting = NSHostingController(rootView: root)
        // The title and the toolbar of the SwiftUI pages into the window, as
        // with a SwiftUI scene. The size: only the minimum size out of the
        // content, otherwise the window could not be dragged freely.
        hosting.sceneBridgingOptions = [.title, .toolbars]
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setContentSize(Self.defaultSize)

        // Remember the frame (in the app's UserDefaults). The first time: centred.
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        weather.cancelSearch()
        // Hidden pages report no onDisappear: end the recording and the
        // permission check here.
        shell.hotKeys.cancelRecording()
        shell.permissions.watch(false, by: NexusGeneralPage.watcher)
        // Closing Nexus while editing counts as "Cancel" - otherwise the
        // dashboard and the control centre would stay pinned open with no way
        // to end it. Spec section 4: only the “Done” button writes the working
        // copy, every other way out (Esc, closing) discards it - `done()`
        // would have saved here unasked. In practice this hardly happens:
        // Nexus stands aside while editing (`beginEditing` orders it out), and
        // this path only catches the case that the window is closed in the
        // middle after all.
        if shellEditor.isEditing { shellEditor.cancel() }
        previousApp?.activate()
        previousApp = nil
    }
}

/// An ordinary window that knows the usual editing shortcuts itself.
///
/// The app has no menu bar (accessory). Cmd+C/V/X/A/Z and Cmd+W run through
/// the menu entries in macOS though - without a menu, Cmd+V would do nothing
/// in the search field. Instead of an invisible main menu for the whole app
/// (which would take in the launcher and the panels too), only this window
/// does it: the same actions up the responder chain. Cmd+Q on purpose not -
/// that would end the whole shell, bar and all.
final class NexusWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return false }
        let shift = flags.contains(.shift)
        let action: Selector? = switch (key, shift) {
        case ("w", false): #selector(NSWindow.performClose(_:))
        case ("x", false): #selector(NSText.cut(_:))
        case ("c", false): #selector(NSText.copy(_:))
        case ("v", false): #selector(NSText.paste(_:))
        case ("a", false): #selector(NSText.selectAll(_:))
        case ("z", false): Selector(("undo:"))
        case ("z", true): Selector(("redo:"))
        default: nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }
}
