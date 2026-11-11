import AppKit
import ApolloShellCore
import SwiftUI

/// Nexus, das Einstellungsfenster der Shell (Caelestia: modules/nexus).
/// Oeffnet ueber den Einstellungs-Knopf im Utilities-Panel und SUPER+,.
///
/// Anders als alle anderen Teile ein ganz normales Fenster: Titelleiste,
/// schliessen, verkleinern, Groesse aendern - wie die Systemeinstellungen.
/// Die App ist aber eine Accessory-App (kein Dock-Symbol, nie aktiv). Damit
/// man in die Suchfelder tippen kann, muss das Fenster Schluesselfenster
/// werden, und das geht nur, wenn die App aktiv ist: `NSApp.activate()`
/// beim Zeigen. Beim Schliessen bekommt die vorher vordere App den Fokus
/// zurueck, sonst stuende man in einer App ohne Fenster.
///
/// Genau ein Fenster: nochmal oeffnen holt das bestehende nach vorne.
/// Schliessen versteckt es nur (`isReleasedWhenClosed = false`); die App
/// laeuft weiter, denn eine Accessory-App endet nicht mit ihrem letzten Fenster.
@MainActor
final class Nexus: NSObject, NSWindowDelegate {
    private static let frameName = "Nexus"
    private static let defaultSize = NSSize(width: 980, height: 680)

    private let state = NexusState()
    private let settings: ShellSettingsStore
    private let pinned: NexusPinnedModel
    private let weather: NexusWeatherModel
    private let providers = NexusProvidersModel()
    private var shell: NexusShellParts
    private var window: NexusWindow?
    /// Wer vor dem Oeffnen vorne war - bekommt beim Schliessen den Fokus zurueck.
    private var previousApp: NSRunningApplication?

    /// "Einführung zeigen" auf der Seite Über. Vor dem ersten Oeffnen setzen.
    var onShowOnboarding: @MainActor () -> Void {
        get { shell.showOnboarding }
        set { shell.showOnboarding = newValue }
    }

    init(settings: ShellSettingsStore, hotKeys: HotKeyCenter, autostart: OnboardingAutostartModel,
         permissions: OnboardingPermissions, updates: UpdateController, themes: ThemeStore?,
         paths: NexusPaths = .live) {
        self.settings = settings
        pinned = NexusPinnedModel(url: paths.pinned)
        weather = NexusWeatherModel(url: paths.weather)
        shell = NexusShellParts(hotKeys: hotKeys, autostart: autostart, permissions: permissions,
                                updates: updates, themes: themes)
        super.init()
    }

    func close() {
        window?.close()
    }

    func show(target: String?) {
        show()
        guard let t = target else { return }
        if let d = SettingsIndex.find(t) {
            state.show(d)
        } else if let p = NexusPage(rawValue: t) {
            state.go(p)
        } else {
            state.search = t
        }
    }

    func show(page: NexusPage? = nil) {
        if let page { state.page = page }
        let window = self.window ?? makeWindow()
        if !window.isVisible {
            // Frisch lesen: pinned.json und weather.json koennen seit dem
            // letzten Mal von Hand geaendert worden sein.
            pinned.reload()
            weather.reload()
            // Apps fuer "Other App…" (Dateimanager): neu installierte zaehlen.
            providers.reload()
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        }
        fit(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        state.focus += 1
    }

    private func makeWindow() -> NexusWindow {
        let vf = NSScreen.main?.visibleFrame.size ?? Self.defaultSize
        let size = NSSize(width: min(Self.defaultSize.width, vf.width - 24), height: min(Self.defaultSize.height, vf.height - 24))
        let window = NexusWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Nexus"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        window.onKey = { [weak self] k in self?.key(k) ?? false }

        state.peek = { [weak self] on in self?.peek(on) }
        let root = NexusView(state: state, settings: settings, pinned: pinned, weather: weather,
                             providers: providers, system: .read(), shell: shell)
            .shellTheme()
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setContentSize(size)

        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
        fit(window)
        self.window = window
        return window
    }

    private func fit(_ w: NSWindow) {
        guard let vf = (w.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = w.frame
        f.size.width = min(f.width, vf.width)
        f.size.height = min(f.height, vf.height)
        f.origin.x = min(max(f.minX, vf.minX), vf.maxX - f.width)
        f.origin.y = min(max(f.minY, vf.minY), vf.maxY - f.height)
        if f != w.frame { w.setFrame(f, display: false) }
    }

    private func key(_ k: String) -> Bool {
        switch k {
        case "f":
            state.focus += 1
            return true
        case "p":
            peek(true)
            return true
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            state.pick(Int(k)! - 1)
            return true
        case "0":
            state.pick(9)
            return true
        default:
            return false
        }
    }

    private var peekMon: Any?

    private func peek(_ on: Bool) {
        guard let w = window else { return }
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.12
            w.animator().alphaValue = on ? 0.05 : 1
        }
        if on, peekMon == nil {
            peekMon = NSEvent.addLocalMonitorForEvents(matching: [.keyUp, .flagsChanged]) { [weak self] e in
                let up = e.type == .keyUp || !e.modifierFlags.contains(.command)
                if up { MainActor.assumeIsolated { self?.peek(false) } }
                return e
            }
        } else if !on, let m = peekMon {
            NSEvent.removeMonitor(m)
            peekMon = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        peek(false)
        state.search = ""
        weather.cancelSearch()
        // Versteckte Seiten melden kein onDisappear: Aufnahme und das
        // Nachsehen der Freigabe hier beenden.
        shell.hotKeys.cancelRecording()
        shell.permissions.watch(false, by: NexusGeneralPage.watcher)
        previousApp?.activate()
        previousApp = nil
    }
}

/// Normales Fenster, das die ueblichen Bearbeitungs-Kuerzel selbst kennt.
///
/// Die App hat keine Menueleiste (Accessory). Cmd+C/V/X/A/Z und Cmd+W laufen
/// in macOS aber ueber die Menue-Eintraege - ohne Menue taete Cmd+V im
/// Suchfeld nichts. Statt einem unsichtbaren Hauptmenue fuer die ganze App
/// (das auch Launcher und Panels betraefe) erledigt das nur dieses Fenster:
/// dieselben Aktionen die Responder-Kette hinauf. Cmd+Q absichtlich nicht -
/// das beendete die ganze Shell samt Leiste.
final class NexusWindow: NSWindow {
    var onKey: ((String) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let k = event.charactersIgnoringModifiers?.lowercased(), onKey?(k) == true { return true }
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
