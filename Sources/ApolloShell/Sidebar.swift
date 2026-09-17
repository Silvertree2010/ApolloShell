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
    /// einer Stelle. Eine Aenderung am Theme wirkt beim naechsten Aufbau der
    /// Fenster (Bildschirmwechsel, Neustart).
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

/// Die Leiste EINES Bildschirms: ihr Fenster, ihre Ansicht und ihr
/// Statuspopout. Die Modelle darin gehoeren dem Verwalter und sind geteilt.
@MainActor
final class SidebarScreen {
    private let panel = SidebarPanel()
    private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "sidebar")
    /// Detailfenster der Statuskapsel (WLAN, Bluetooth, Akku). Liegt im
    /// Fenster dieser Leiste und macht es breiter, solange es offen ist.
    private let popout = StatusPopout()
    /// Welcher Bildschirm das ist - wird bei jedem Umbau aufgefrischt.
    private(set) var info: ScreenInfo
    private var frame: NSRect
    private var visibleTop: CGFloat
    /// Letzter gueltiger Rahmen. Ohne ihn zeigt sich die Leiste nicht.
    private var lastFrame: NSRect?
    private var expanded = false
    /// Vordergrund-App ist auf DIESEM Bildschirm im Vollbild.
    private(set) var isHiddenForFullscreen = false
    /// Dieses Popout geht auf - der Verwalter schliesst die anderen.
    var onPopoutOpen: (ObjectIdentifier) -> Void = { _ in }

    init(screen: ShellScreen, settings: ShellSettingsStore, context: BarModuleContext) {
        info = screen.info
        frame = screen.frame
        visibleTop = screen.visibleFrame.maxY

        // Glas zeichnet SwiftUI (`SidebarRoot`), nicht NSGlassEffectView:
        // nur im selben GlassEffectContainer verschmilzt das Popout mit der
        // Leiste.
        let hosting = FirstMouseHostingView(
            rootView: SidebarRoot(settings: settings, context: context, popout: popout.model).shellTheme()
        )
        // Ohne das bestimmt die Ansicht die Fenstergroesse mit und kaempft mit
        // `layout()`, sobald das Fenster fuer ein Popout breiter wird.
        hosting.sizingOptions = []
        // Der durchsichtige Teil des breiten Fensters muss geleert werden,
        // sonst bleibt dort stehen, was vorher auf dem Bildschirm war.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        panel.contentView = hosting
        popout.hostWindow = panel
        popout.setExpanded = { [weak self] in self?.setExpanded($0) }
        popout.onOpen = { [weak self] in
            guard let self else { return }
            self.onPopoutOpen(ObjectIdentifier(self))
        }
        // SwiftUI meldet Symbolrahmen in Koordinaten der Ansicht (oben = 0,
        // NSHostingView ist geflippt); AppKit rechnet sie ueber das Fenster
        // auf den Bildschirm um.
        popout.screenRect = { [weak hosting] rect in
            guard let hosting, let window = hosting.window else { return nil }
            return window.convertToScreen(hosting.convert(rect, to: nil))
        }

        layout()
        showIfNeeded()
    }

    /// Derselbe Bildschirm, aber vielleicht mit neuen Massen oder an einer
    /// neuen Stelle.
    func update(screen: ShellScreen) {
        info = screen.info
        frame = screen.frame
        visibleTop = screen.visibleFrame.maxY
        layout()
        showIfNeeded()
    }

    /// Bildschirm weg oder abgewaehlt: Popout zu, Fenster weg.
    func tearDown() {
        popout.close()
        panel.orderOut(nil)
        lastFrame = nil
    }

    func closePopout() {
        popout.close()
    }

    /// Vollbild an: weg. Vollbild aus: wieder her. `.canJoinAllSpaces` holt
    /// das Panel sonst auch in Vollbild-Spaces (siehe `SidebarPanel`).
    ///
    /// Unsichtbar und klickdurchlaessig statt `orderOut`: Die Meldung "kein
    /// Vollbild mehr" kommt mitten in der Wisch-Animation zurueck zum
    /// Schreibtisch. Ein dann wieder eingeblendetes Panel hing gemessen nur
    /// noch an diesem einen Space und fehlte auf allen anderen. Bleibt es
    /// eingeblendet, behaelt es alle Spaces.
    func setHiddenForFullscreen(_ hidden: Bool) {
        guard hidden != isHiddenForFullscreen else { return }
        isHiddenForFullscreen = hidden
        log.notice("Sidebar \(hidden ? "weg (Vollbild)" : "wieder da", privacy: .public)")
        if hidden {
            // Ohne Leiste haette das Popout nichts, woran es haengt.
            popout.close()
        }
        panel.alphaValue = hidden ? 0 : 1
        panel.ignoresMouseEvents = hidden
        if !hidden { showIfNeeded() }
    }

    /// Nur nach vorne holen, wenn sie sichtbar sein soll und es gerade nicht
    /// ist. Ein bedingungsloses orderFrontRegardless bei jedem Space-Wechsel
    /// kann waehrend Mission Control flackern. (Die erste Fassung tat das,
    /// weil Overlay-Panels nach Space-Wechseln gelegentlich verloren gingen;
    /// geht sie trotz `isVisible` verloren, ist hier die Stelle dafuer.)
    private func showIfNeeded() {
        guard lastFrame != nil, !panel.isVisible else { return }
        panel.orderFrontRegardless()
    }

    /// Popout offen: Fenster breiter, die Leiste bleibt links 44 breit, der
    /// Rest ist durchsichtig, bis das Glas hineinwaechst.
    private func setExpanded(_ expanded: Bool) {
        guard expanded != self.expanded else { return }
        self.expanded = expanded
        layout()
    }

    /// Am linken Rand dieses Bildschirms: unten bis zum Rand, oben bis zur
    /// Unterkante der Menueleiste. Bildschirme ohne Menueleiste haben dort
    /// keinen Abzug, dann reicht die Leiste bis ganz nach oben.
    private func layout() {
        let width = expanded ? StatusPopout.expandedWidth : Sidebar.width
        let rect = NSRect(x: frame.minX, y: frame.minY, width: width, height: visibleTop - frame.minY)
        lastFrame = rect
        // Mit dem echten Panelrahmen vergleichen, nicht mit `lastFrame`: beim
        // Umstecken verschiebt macOS Fenster auch selbst.
        guard panel.frame != rect else { return }
        panel.setFrame(rect, display: true)
    }
}

/// Wurzel des Leistenfensters: EIN Glas, darauf die Leiste und der Inhalt
/// des Statuspopouts.
///
/// Das Glas ist eine einzige Form (`SidebarGlassShape`): der Streifen der
/// Leiste plus die Beule des offenen Popouts. Zwei getrennte Glaeser
/// nebeneinander faerben sich verschieden ein und zeigen an der Naht eine
/// Kante; eine Form hat ueberall dieselbe Farbe und keinen Uebergang.
///
/// Beim Oeffnen waechst die Beule aus der Hoehe des angeklickten Symbols
/// heraus. Der Inhalt steht dabei still und wird von ihr aufgedeckt
/// (Caelestia: ClipWrapper + Wrapper + Content).
struct SidebarRoot: View {
    let settings: ShellSettingsStore
    let context: BarModuleContext
    let popout: StatusPopoutModel
    /// Gemessene Groesse jedes Inhalts: so steht die Zielgroesse schon fest,
    /// bevor die Beule losgeht, und ein spaeter geladener Inhalt (Bluetooth
    /// liest erst nach dem Oeffnen) gleitet auf seine neue Hoehe.
    @State private var sizes: [StatusPopoutKind: CGSize] = [:]

    var body: some View {
        GeometryReader { geometry in
            let size = sizes[popout.shown] ?? CGSize(width: StatusPopoutContent.width(popout.shown), height: 200)
            let open = popout.isOpen
            let top = StatusPopoutPlacement.top(
                anchorY: popout.anchorY, height: size.height, containerHeight: geometry.size.height
            )
            // Geschlossen: Breite 0 auf Hoehe des Symbols, also nur Leiste.
            let bulge = CGRect(
                x: Sidebar.width,
                y: open ? top : popout.anchorY - StatusPopoutLayout.seedHeight / 2,
                width: open ? size.width : 0,
                height: open ? size.height : StatusPopoutLayout.seedHeight
            )
            ZStack(alignment: .topLeading) {
                Color.clear
                    .modifier(SidebarGlass(shape: SidebarGlassShape(barWidth: Sidebar.width, bulge: bulge),
                                           background: settings.settings.bar.background))
                SidebarContent(settings: settings, context: context)
                    .frame(width: Sidebar.width)
                    .frame(maxHeight: .infinity)
                popoutContent(size: size, top: top, bulge: bulge, open: open)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .animation(StatusPopoutMotion.spatial, value: size)
            // Sichtbarer Teil der Beule ab der rechten Leistenkante, fuer den
            // Klicktest "ausserhalb" in `StatusPopout`.
            .onGeometryChange(for: CGRect.self) { _ in
                CGRect(x: 0, y: bulge.minY, width: bulge.width, height: bulge.height)
            } action: { popout.panelFrame = $0 }
        }
        // Das Popout-Modell kommt ueber die Umgebung zur Statuskapsel.
        .environment(popout)
    }

    /// Alle drei Inhalte sind immer aufgebaut (nur unsichtbar): so ist die
    /// Groesse des naechsten schon gemessen, bevor man wechselt. Sichtbar ist
    /// nur, was die Beule freigibt.
    private func popoutContent(size: CGSize, top: CGFloat, bulge: CGRect, open: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(StatusPopoutKind.allCases, id: \.self) { kind in
                let active = open && popout.shown == kind
                StatusPopoutContent(model: popout, kind: kind)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { sizes[kind] = $0 }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .offset(x: Sidebar.width, y: top)
                    .opacity(active ? 1 : 0)
                    .animation(active ? StatusPopoutMotion.fadeIn : StatusPopoutMotion.fadeOut, value: active)
                    .allowsHitTesting(active)
                    .accessibilityHidden(!active)
            }
        }
        .mask(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: StatusPopoutLayout.cornerRadius)
                .frame(width: bulge.width, height: bulge.height)
                .offset(x: bulge.minX, y: bulge.minY)
        }
    }
}

/// Hintergrund der Leiste in ihrer Form, in Bildproben durch eine feste
/// Flaeche ersetzt (Glas zeichnet ausserhalb des Bildschirms nur weiss).
///
/// Welcher Hintergrund, sagt Nexus > Leiste > Hintergrund; warum es die Wahl
/// gibt und was die einzelnen Eintraege sollen, steht bei `BarBackground`.
private struct SidebarGlass<S: Shape>: ViewModifier {
    let shape: S
    let background: BarBackground
    @Environment(\.statusPopoutGlassStandIn) private var standIn
    @Environment(\.colorScheme) private var colorScheme

    /// Fensterfarbe, halb deckend: zieht das Glas in Richtung Fensterfarbe,
    /// laesst es aber noch Glas sein. Ganz aufhalten kann eine Toenung das
    /// Umfaerben ohnehin nicht (siehe `BarBackground`) - dafuer ist
    /// `fixedGlass` da.
    private static var tint: Color { Color(nsColor: .windowBackgroundColor).opacity(0.7) }

    /// Mit Theme faerbt das Theme die Leiste: die Farbe (oder der Verlauf)
    /// aus `--apollo-bar-color` beziehungsweise `--apollo-bar-gradient`, mit
    /// `--apollo-bar-opacity`. Die Wahl in Nexus > Leiste bleibt darunter
    /// sichtbar, solange das Theme durchscheinen laesst und Glas erlaubt -
    /// sonst waere eine halb deckende Leiste eine Leiste vor dem Schreibtisch.
    func body(content: Content) -> some View {
        let style = ShellTheme.style(colorScheme)
        if standIn {
            content.background(colorScheme == .dark ? Color(white: 0.17) : Color(white: 0.95), in: shape)
        } else if style.isThemed {
            let opaque = style.barIsOpaque
            content
                .background(style.barFill, in: shape)
                .background {
                    if !opaque, style.glass {
                        Color.clear.glassEffect(.regular, in: shape)
                    }
                }
        } else {
            switch background {
            case .material:
                content.background(.regularMaterial, in: shape)
            case .glass:
                content.glassEffect(.regular, in: shape)
            case .tintedGlass:
                content.glassEffect(.regular.tint(Self.tint), in: shape)
            case .fixedGlass:
                // Reihenfolge: erst das Glas hinter den Inhalt, dann die
                // deckende Flaeche hinter das Glas. Das Glas hat damit
                // ueberall dieselbe Flaeche vor sich statt des Schreibtischs
                // und der Fenster, seine Anpassung hat also nichts mehr zum
                // Anpassen. `clear` statt `regular`, weil nur diese Fassung
                // laut Apple gar nicht anpasst; die deckende Flaeche ist die
                // Schicht, die `clear` dafuer braucht.
                content
                    .glassEffect(.clear, in: shape)
                    .background(Color(nsColor: .windowBackgroundColor), in: shape)
            }
        }
    }
}

/// Umriss der Leiste samt Beule: ein durchgehender Pfad, keine zwei
/// uebereinandergelegten Formen (die fuellt SwiftUI je nach Regel mit einem
/// Loch in der Ueberlappung).
///
/// Am Uebergang zur Beule zwei einwaertsgekruemmte Ecken, damit sie aus der
/// Leiste zu wachsen scheint statt angeklebt zu wirken.
struct SidebarGlassShape: Shape {
    var barWidth: CGFloat
    var bulge: CGRect

    /// Lage und Groesse der Beule animieren: so gleitet die Form beim
    /// Oeffnen, Wechseln und Schliessen.
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(bulge.origin.x, bulge.origin.y),
                           AnimatablePair(bulge.size.width, bulge.size.height))
        }
        set {
            bulge = CGRect(x: newValue.first.first, y: newValue.first.second,
                           width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard bulge.width > 0.5, bulge.height > 0.5 else {
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: barWidth, height: rect.height))
            return path
        }
        let r = min(StatusPopoutLayout.cornerRadius, bulge.width / 2, bulge.height / 2)
        let j = min(StatusPopoutLayout.join, bulge.width, max(0, (rect.height - bulge.height) / 2))
        let x = rect.minX
        let edge = x + barWidth
        let top = max(rect.minY, bulge.minY)
        let bottom = min(rect.maxY, bulge.maxY)
        let right = edge + bulge.width

        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: edge, y: rect.minY))
        // Rechte Leistenkante hinunter bis zur Beule, dann einwaerts gekruemmt
        // hinein.
        path.addLine(to: CGPoint(x: edge, y: top - j))
        path.addQuadCurve(to: CGPoint(x: edge + j, y: top),
                          control: CGPoint(x: edge, y: top))
        path.addLine(to: CGPoint(x: right - r, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + r), control: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: bottom - r))
        path.addQuadCurve(to: CGPoint(x: right - r, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: edge + j, y: bottom))
        path.addQuadCurve(to: CGPoint(x: edge, y: bottom + j), control: CGPoint(x: edge, y: bottom))
        // Weiter die Leistenkante hinunter und um die Leiste herum zurueck.
        path.addLine(to: CGPoint(x: edge, y: rect.maxY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        path.closeSubpath()
        return path
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
///   und collectionBehavior schafft das; deshalb erkennt `FullscreenMonitor`
///   Vollbild selbst, und die Leiste wird dort unsichtbar und
///   klickdurchlaessig (siehe `setHiddenForFullscreen`).
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
