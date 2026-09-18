import AppKit
import ApolloShellCore
import os
import SwiftUI

/// Verwalter der Leisten: eine Leiste je Bildschirm.
///
/// Welche Bildschirme eine bekommen, sagt Nexus > Leiste (Alle, nur
/// Hauptbildschirm, ein einzelner); die Rechnung dazu steht in
/// ApolloShellCore/ScreenSelection und ist dort getestet.
///
/// Die Modelle (Dock, Uhr, Spaces, CPU, Wetter, Status) werden hier EINMAL
/// gebaut und an alle Leisten weitergereicht. Sie lesen systemweite Werte -
/// je Bildschirm eigene waeren dieselbe Messung mehrfach und damit mehrfache
/// Last. Eigen je Leiste ist nur, was zum Fenster gehoert: das Panel und sein
/// Statuspopout.
///
/// Platz halten wie der Dock macht die Fensterwache (WindowGuard.swift):
/// macOS hat dafuer keine Schnittstelle, sie schiebt Fenster per
/// Bedienungshilfen aus dem Streifen; ohne Freigabe laufen maximierte
/// Fenster darunter durch. Steht auf einem Bildschirm eine Vollbild-App
/// (`FullscreenMonitor`), tritt die Leiste dieses Bildschirms ab.
@MainActor
final class Sidebar {
    /// Breite der Leiste. Mit Theme entscheidet `--apollo-bar-width`.
    ///
    /// Die Breite steckt nicht nur in der Ansicht, sondern auch im Fenster
    /// und im Streifen, den die Fensterwache freihaelt - deshalb hier an
    /// einer Stelle. Aendert sie sich (anderes Theme, Hell/Dunkel), zieht
    /// `widthChanged()` Fenster und Fensterwache sofort nach.
    static var width: CGFloat {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return ThemeStore.shared?.style(dark: dark).barWidth(44) ?? 44
    }

    private let settings: ShellSettingsStore
    private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "sidebar")

    /// Klick auf das Ausschalt-Symbol unten (oeffnet das Sitzungsmenue).
    var onPower: () -> Void = {}
    /// Klick auf das Dashboard-Symbol oben.
    var onDashboard: () -> Void = {}
    /// Klick auf das Utilities-Symbol ueber der Statuskapsel.
    var onUtilities: () -> Void = {}
    /// Klick auf Medien, Wetter, CPU oder Akku: Dashboard beim passenden Reiter.
    var onDashboardTab: (DashboardTab) -> Void = { _ in }
    /// Nach jedem Umbau: auf diesen Bildschirmen steht jetzt eine Leiste.
    /// Die Fensterwache haelt dort den Streifen frei.
    var onScreensChange: ([ScreenInfo]) -> Void = { _ in }

    /// Geteilte Modelle - einmal fuer alle Leisten.
    /// CPU und Wetter messen bzw. rufen nur ab, solange mindestens eine
    /// Leiste zu sehen ist.
    private let cpu = BarCPUModel()
    private let weather: BarWeatherFeed
    /// WLAN, Bluetooth, Akku fuer die Statuskapsel.
    private let status = StatusModel()
    /// Spaces, Dock und Uhr fuer die Mitte der Leiste.
    private let spaces = SpacesModel()
    private let dock: SidebarDockModel
    private let clock = SidebarClockModel()

    /// Eine Leiste je Bildschirm, nach Display-Kennung.
    private var bars: [CGDirectDisplayID: SidebarScreen] = [:]
    /// Bildschirme, auf denen gerade eine Vollbild-App steht.
    private var fullscreenScreens: Set<CGDirectDisplayID> = []
    private var context: BarModuleContext!
    private var choiceObservation: Task<Void, Never>?
    private var widthObservation: Task<Void, Never>?
    private var appearanceObservation: NSKeyValueObservation?
    /// Breite beim letzten Vermessen der Fenster.
    private var laidOutWidth: CGFloat = 0

    /// `settings`: welche Bausteine in welcher Reihenfolge und auf welchen
    /// Bildschirmen (Nexus > Leiste). SwiftUI beobachtet sie und baut die
    /// Leisten bei jeder Aenderung sofort um.
    init(settings: ShellSettingsStore) {
        self.settings = settings
        // Der Dateimanager oben kommt aus den Einstellungen (Nexus > Anbieter).
        dock = SidebarDockModel(settings: settings)
        // Wetteranbieter ebenfalls aus den Einstellungen, wie im Dashboard.
        weather = BarWeatherFeed(settings: settings)
        context = BarModuleContext(
            status: status, spaces: spaces, dock: dock, clock: clock, cpu: cpu, weather: weather,
            onDashboard: { [weak self] in self?.onDashboard() },
            onDashboardTab: { [weak self] in self?.onDashboardTab($0) },
            onUtilities: { [weak self] in self?.onUtilities() },
            onPower: { [weak self] in self?.onPower() },
            onSelectSpace: { [spaces] in spaces.switchTo($0) },
            onOpenApp: { BarApps.open($0) }
        )

        rebuild()
        observeSystemChanges()
        // Liefert zuerst den aktuellen Wert (nichts zu tun), danach jede
        // Aenderung der Bildschirm-Einstellung aus Nexus.
        choiceObservation = Task { [weak self, settings] in
            for await _ in Observations({ settings.settings.bar.screens }) {
                self?.rebuild()
            }
        }
        // Die Breite haengt am Theme (beobachtbar) und an Hell/Dunkel (nicht
        // beobachtbar, deshalb per KVO).
        widthObservation = Task { [weak self] in
            for await _ in Observations({ Sidebar.width }) {
                self?.widthChanged()
            }
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.widthChanged() }
        }
    }

    /// Neue Leistenbreite: Fenster neu vermessen und die Fensterwache den
    /// Streifen anpassen lassen. Ein offenes Popout geht zu - seine Buehne
    /// haengt an der alten Breite.
    private func widthChanged() {
        guard Sidebar.width != laidOutWidth else { return }
        for bar in bars.values { bar.closePopout() }
        rebuild()
    }

    /// Auf welchen Bildschirmen gerade eine Leiste steht.
    var screens: [ScreenInfo] {
        bars.values.map(\.info)
    }

    /// Von `FullscreenMonitor`: auf diesen Bildschirmen steht eine
    /// Vollbild-App. Nur deren Leiste tritt ab, die anderen bleiben stehen.
    /// Nach Display-Kennung, nicht nach Schluessel: zwei baugleiche
    /// Bildschirme haben denselben Schluessel.
    func setFullscreenScreens(_ ids: Set<CGDirectDisplayID>) {
        guard ids != fullscreenScreens else { return }
        fullscreenScreens = ids
        for (id, bar) in bars {
            bar.setHiddenForFullscreen(ids.contains(id))
        }
        updateModelDemand()
    }

    /// Unsichtbar braucht niemand CPU-Werte oder Wetter: die geteilten
    /// Modelle ruhen, sobald keine Leiste mehr zu sehen ist.
    private func updateModelDemand() {
        let anyVisible = bars.values.contains { !$0.isHiddenForFullscreen }
        cpu.paused = !anyVisible
        weather.paused = !anyVisible
        dock.badgesPaused = !anyVisible
    }

    // MARK: - Leisten verteilen

    /// Leisten anlegen, vermessen und wieder abraeumen, so wie es die
    /// Einstellung und die angeschlossenen Bildschirme gerade verlangen.
    ///
    /// Ohne Bildschirme (Kabel mitten im Umstecken, `NSScreen.screens` leer)
    /// bleibt alles stehen, statt alles abzureissen und gleich wieder
    /// aufzubauen. Kommen sie zurueck, meldet sich
    /// didChangeScreenParametersNotification und es geht hier weiter.
    private func rebuild() {
        let all = ShellScreens.current()
        guard !all.isEmpty else {
            log.notice("kein Bildschirm, die Leisten bleiben stehen")
            return
        }
        let wanted = ShellScreens.targets(for: settings.settings.bar.screens, among: all)
        let keep = Set(wanted.map(\.displayID))

        // Bildschirm weg oder abgewaehlt: Leiste abraeumen. Das schliesst
        // auch ein Popout, das dort noch offen stand.
        for (id, bar) in bars where !keep.contains(id) {
            bar.tearDown()
            bars[id] = nil
        }

        for screen in wanted {
            let hidden = fullscreenScreens.contains(screen.displayID)
            if let bar = bars[screen.displayID] {
                bar.update(screen: screen)
                bar.setHiddenForFullscreen(hidden)
            } else {
                let bar = SidebarScreen(screen: screen, settings: settings, context: context)
                bar.onPopoutOpen = { [weak self] id in self?.closePopouts(except: id) }
                bar.setHiddenForFullscreen(hidden)
                bars[screen.displayID] = bar
            }
        }

        updateModelDemand()
        laidOutWidth = Sidebar.width
        log.notice("Leisten auf \(self.bars.count, privacy: .public) von \(all.count, privacy: .public) Bildschirm(en)")
        onScreensChange(wanted.map(\.info))
    }

    /// Es ist immer nur ein Statuspopout offen: geht eines auf, schliesst
    /// das einer anderen Leiste.
    private func closePopouts(except id: ObjectIdentifier) {
        for bar in bars.values where ObjectIdentifier(bar) != id {
            bar.closePopout()
        }
    }

    /// Aufloesung oder Bildschirme geaendert, Aufwachen (ganzer Rechner oder
    /// nur die Bildschirme), Space-Wechsel: neu verteilen, vermessen und,
    /// falls eine Leiste sichtbar sein soll, aber weg ist, wieder nach vorne
    /// holen.
    ///
    /// Das Einschlafen der Bildschirme braucht keinen eigenen Beobachter:
    /// solange sie dunkel sind, gibt es nichts zu tun, und das Aufwachen
    /// deckt `screensDidWakeNotification` ab.
    ///
    /// Die Beobachter werden nie entfernt: der Verwalter lebt so lange wie
    /// der Prozess (AppDelegate haelt ihn), und die Bloecke halten ihn nur
    /// schwach.
    private func observeSystemChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Neue Aufloesung oder Anordnung: Lage und Hoehe eines
                // offenen Popouts stimmen nicht mehr.
                for bar in self.bars.values { bar.closePopout() }
                self.rebuild()
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild() }
            }
        }
    }
}
