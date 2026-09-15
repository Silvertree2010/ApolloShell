import AppKit
import ApolloShellCore
import os

/// Linke Leiste ("neues Dock"), vorerst leer.
///
/// Liquid-Glass-Streifen direkt am linken Rand: durchgehend von der
/// Bildschirm-Unterkante bis unter die Menueleiste, ohne Abstand und ohne
/// runde Ecken (so gestaltet Apple angedockte Flaechen; rund sind nur
/// schwebende). Die Menueleiste bleibt frei, damit Apple-Menue und
/// App-Menues oben links erreichbar sind.
///
/// Platz halten wie der Dock macht die Fensterwache (WindowGuard.swift):
/// macOS hat dafuer keine Schnittstelle, sie schiebt Fenster per
/// Bedienungshilfen aus dem Streifen. Sie meldet auch, wann die
/// Vordergrund-App im Vollbild ist; dann tritt die Leiste ab. Ohne
/// Bedienungshilfen-Freigabe bleibt die Leiste einfach immer sichtbar und
/// maximierte Fenster laufen darunter durch.
@MainActor
final class Sidebar {
    static let width: CGFloat = 44

    private let panel = SidebarPanel()
    private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "sidebar")
    /// Letzter gueltiger Rahmen. Verschwinden die Bildschirme kurz (Kabel
    /// mitten im Umstecken, NSScreen.screens leer), bleibt die Leiste dort
    /// stehen, statt auf einem Nullrahmen zu landen.
    private var lastFrame: NSRect?
    /// Von der Fensterwache: Vordergrund-App ist im Vollbild auf dem
    /// Hauptbildschirm.
    private var hiddenForFullscreen = false
    /// Klick auf das Ausschalt-Symbol unten (oeffnet das Sitzungsmenue).
    var onPower: () -> Void = {}
    /// Klick auf das Dashboard-Symbol oben.
    var onDashboard: () -> Void = {}
    /// Klick auf das Utilities-Symbol ueber der Statuskapsel.
    var onUtilities: () -> Void = {}
    /// Klick auf Medien, Wetter, CPU oder Akku: Dashboard beim passenden Reiter.
    var onDashboardTab: (DashboardTab) -> Void = { _ in }
    /// CPU- und Wetter-Baustein: messen bzw. abrufen nur, solange einer in
    /// der Leiste steht und sie zu sehen ist.
    private let cpu = BarCPUModel()
    private let weather: BarWeatherFeed
    /// WLAN, Bluetooth, Akku fuer die Statuskapsel.
    private let status = StatusModel()
    /// Spaces, Dock und Uhr fuer die Mitte der Leiste.
    private let spaces = SpacesModel()
    private let dock: SidebarDockModel
    private let clock = SidebarClockModel()
    /// Detailfenster der Statuskapsel (WLAN, Bluetooth, Akku).
    private let popout = StatusPopout()

    /// `settings`: welche Bausteine in welcher Reihenfolge (Nexus > Leiste).
    /// SwiftUI beobachtet sie und baut die Leiste bei jeder Aenderung sofort um.
    init(settings: ShellSettingsStore) {
        // Der Dateimanager oben kommt aus den Einstellungen (Nexus > Anbieter).
        dock = SidebarDockModel(settings: settings)
        // Wetteranbieter ebenfalls aus den Einstellungen, wie im Dashboard.
        weather = BarWeatherFeed(settings: settings)
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 0
        let context = BarModuleContext(
            status: status, spaces: spaces, dock: dock, clock: clock, cpu: cpu, weather: weather,
            onDashboard: { [weak self] in self?.onDashboard() },
            onDashboardTab: { [weak self] in self?.onDashboardTab($0) },
            onUtilities: { [weak self] in self?.onUtilities() },
            onPower: { [weak self] in self?.onPower() },
            onSelectSpace: { [spaces] in spaces.switchTo($0) },
            onOpenApp: { BarApps.open($0) }
        )
        // Das Popout-Modell kommt ueber die Umgebung zur Statuskapsel.
        let hosting = FirstMouseHostingView(rootView: SidebarContent(settings: settings, context: context)
            .environment(popout.model))
        glass.contentView = hosting
        panel.contentView = glass
        // SwiftUI meldet Symbolrahmen in Koordinaten der Ansicht (oben = 0,
        // NSHostingView ist geflippt); AppKit rechnet sie ueber das Fenster
        // auf den Bildschirm um.
        popout.screenRect = { [weak hosting] rect in
            guard let hosting, let window = hosting.window else { return nil }
            return window.convertToScreen(hosting.convert(rect, to: nil))
        }

        layout()
        showIfNeeded()
        observeSystemChanges()
    }

    /// Vollbild an: weg. Vollbild aus: wieder her. `.canJoinAllSpaces` holt
    /// das Panel sonst auch in Vollbild-Spaces (siehe `SidebarPanel`).
    func setHiddenForFullscreen(_ hidden: Bool) {
        guard hidden != hiddenForFullscreen else { return }
        hiddenForFullscreen = hidden
        log.notice("Sidebar \(hidden ? "weg (Vollbild)" : "wieder da", privacy: .public)")
        // Unsichtbar braucht niemand CPU-Werte oder Wetter.
        cpu.paused = hidden
        weather.paused = hidden
        if hidden {
            // Ohne Leiste haette das Popout nichts, woran es haengt.
            popout.close()
            panel.orderOut(nil)
        } else {
            showIfNeeded()
        }
    }

    /// Nur nach vorne holen, wenn sie sichtbar sein soll und es gerade nicht
    /// ist. Ein bedingungsloses orderFrontRegardless bei jedem Space-Wechsel
    /// kann waehrend Mission Control flackern. (Die erste Fassung tat das,
    /// weil Overlay-Panels nach Space-Wechseln gelegentlich verloren gingen;
    /// geht sie trotz `isVisible` verloren, ist hier die Stelle dafuer.)
    private func showIfNeeded() {
        guard !hiddenForFullscreen, lastFrame != nil, !panel.isVisible else { return }
        panel.orderFrontRegardless()
    }

    /// Hauptbildschirm (der mit der Menueleiste): unten bis zum Rand, oben bis
    /// zur Unterkante der Menueleiste.
    private func layout() {
        guard let screen = NSScreen.screens.first else {
            // Kommt der Bildschirm zurueck, meldet sich
            // didChangeScreenParametersNotification und es geht hier weiter.
            log.notice("kein Bildschirm, Sidebar behaelt ihren letzten Rahmen")
            return
        }
        let frame = screen.frame
        let top = screen.visibleFrame.maxY
        let rect = NSRect(x: frame.minX, y: frame.minY, width: Self.width, height: top - frame.minY)
        lastFrame = rect
        // Mit dem echten Panelrahmen vergleichen, nicht mit `lastFrame`: beim
        // Umstecken verschiebt macOS Fenster auch selbst.
        guard panel.frame != rect else { return }
        panel.setFrame(rect, display: true)
        log.notice("Sidebar \(Self.width, privacy: .public) x \(rect.height, privacy: .public) pt")
    }

    /// Aufloesung oder Bildschirme geaendert, Aufwachen (ganzer Rechner oder
    /// nur die Bildschirme), Space-Wechsel: neu vermessen und, falls sie
    /// sichtbar sein soll, aber weg ist, wieder nach vorne holen.
    ///
    /// Das Einschlafen der Bildschirme braucht keinen eigenen Beobachter:
    /// solange sie dunkel sind, gibt es nichts zu tun, und das Aufwachen
    /// deckt `screensDidWakeNotification` ab.
    ///
    /// Die Beobachter werden nie entfernt: die Sidebar lebt so lange wie der
    /// Prozess (AppDelegate haelt sie), und die Bloecke halten sie nur schwach.
    private func observeSystemChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Neue Aufloesung: Lage und Hoehe des Popouts stimmen nicht mehr.
                self.popout.close()
                self.layout()
                self.showIfNeeded()
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.layout()
                    self.showIfNeeded()
                }
            }
        }
    }
}

/// Randloses Panel, das nie Fokus nimmt.
///
/// - Ebene `.floating`: ueber normalen Fenstern, unter Dock (20) und
///   Menueleiste (24). Weil die Leiste unter der Menueleiste endet, kommen
///   sich die beiden nicht in die Quere.
/// - Auf allen Spaces, bleibt beim Wischen zwischen Spaces stehen, nicht in
///   Cmd+Tab. Ohne `.fullScreenAuxiliary` - das allein haelt sie auf macOS 26
///   aber NICHT aus Vollbild-Spaces heraus (ein Vollbild-Space ist auch ein
///   Space, `.canJoinAllSpaces` gilt dort mit). Keine Kombination aus Ebene
///   und collectionBehavior schafft das; deshalb erkennt die Fensterwache
///   Vollbild selbst und die Leiste tritt per orderOut ab.
/// - Kein Fensterschatten: gab beim Launcher einen zweiten, fast eckigen
///   Rahmen um das Glas.
/// - `canHide = false`: "Andere ausblenden" soll sie nicht verschwinden lassen.
final class SidebarPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        canHide = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
