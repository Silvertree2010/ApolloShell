import AppKit
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
    private static let defaultSize = NSSize(width: 820, height: 600)

    private let state = NexusState()
    private let settings: ShellSettingsStore
    private let pinned: NexusPinnedModel
    private let weather: NexusWeatherModel
    private let providers = NexusProvidersModel()
    private let shellEditor: ShellEditor
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
         shellEditor: ShellEditor, paths: NexusPaths = .live) {
        self.settings = settings
        self.shellEditor = shellEditor
        pinned = NexusPinnedModel(url: paths.pinned)
        weather = NexusWeatherModel.file(url: paths.weather)
        shell = NexusShellParts(hotKeys: hotKeys, autostart: autostart, permissions: permissions,
                                updates: updates, themes: themes)
        super.init()
        // Kommt zurueck, sobald der globale Bearbeitungsmodus endet (Fertig,
        // Abbrechen, Esc) - auf derselben Seite, wie sie beim Start stand.
        // `NSApp.activate()` zuerst: ohne das kam das Fenster nach vorne, aber
        // ohne Fokus zurueck, wenn zwischendurch eine andere App aktiv wurde
        // (Scrim/Werkzeugleiste/Galerie nehmen selbst nie die Tastatur an) -
        // es stand dann sichtbar, aber hinter der wirklich aktiven App.
        shellEditor.addEndHandler { [weak self] in
            NSApp.activate()
            self?.window?.makeKeyAndOrderFront(nil)
        }
        shell.beginEditing = { [weak self] in self?.beginEditing() }
    }

    /// Knopf „Oberfläche bearbeiten“ (jede Nexus-Seite, Spec Abschnitt 4):
    /// startet den globalen Bearbeitungsmodus auf dem Bildschirm dieses
    /// Fensters und tritt selbst ab, bis er endet.
    func beginEditing() {
        guard let window, window.isVisible else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }
        shellEditor.begin(screen: screen)
        window.orderOut(nil)
    }

    func show(page: NexusPage? = nil) {
        if let page { state.page = page }
        let window = self.window ?? makeWindow()
        if !window.isVisible {
            // Frisch lesen: pinned.json und weather.json koennen seit dem
            // letzten Mal von Hand geaendert worden sein.
            pinned.reload()
            weather.reload()
            // Apps fuer "Andere App …" (Dateimanager): neu installierte zaehlen.
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
        // Per SUPER+, aus einem anderen Space: Fenster kommt dorthin, statt
        // dass macOS zum Space des Fensters springt.
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self

        // `shellTheme` setzt den Farbton der Steuerelemente nach dem Theme.
        let root = NexusView(state: state, settings: settings, pinned: pinned, weather: weather,
                             providers: providers, system: .read(), shell: shell)
            .shellTheme()
        let hosting = NSHostingController(rootView: root)
        // Titel und Werkzeugleiste der SwiftUI-Seiten ins Fenster, wie bei
        // einer SwiftUI-Szene. Groesse: nur die Mindestgroesse aus dem
        // Inhalt, sonst liesse sich das Fenster nicht frei ziehen.
        hosting.sceneBridgingOptions = [.title, .toolbars]
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setContentSize(Self.defaultSize)

        // Rahmen merken (UserDefaults der App). Erstes Mal: mittig.
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        weather.cancelSearch()
        // Versteckte Seiten melden kein onDisappear: Aufnahme und das
        // Nachsehen der Freigabe hier beenden.
        shell.hotKeys.cancelRecording()
        shell.permissions.watch(false, by: NexusGeneralPage.watcher)
        // Nexus zu waehrend einer Bearbeitung zaehlt wie "Abbrechen" - sonst
        // bliebe Dashboard und Kontrollzentrum angepinnt offen, ohne dass man
        // es beenden kann. Spec Abschnitt 4: nur der Knopf „Fertig“ schreibt
        // die Arbeitskopie, jeder andere Ausstieg (Esc, Schliessen) verwirft
        // sie - `done()` haette hier ungefragt gespeichert. In der Praxis
        // kommt das kaum vor: Nexus steht waehrend der Bearbeitung beiseite
        // (`beginEditing` ordnet es aus), dieser Pfad faengt nur ab, falls
        // das Fenster mittendrin doch noch geschlossen wird.
        if shellEditor.isEditing { shellEditor.cancel() }
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
