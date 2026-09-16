import AppKit
import ApolloShellCore
import os
import SwiftUI

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
    /// Detailfenster der Statuskapsel (WLAN, Bluetooth, Akku). Liegt im
    /// Fenster der Leiste und macht es breiter, solange es offen ist.
    private let popout = StatusPopout()
    private var expanded = false

    /// `settings`: welche Bausteine in welcher Reihenfolge (Nexus > Leiste).
    /// SwiftUI beobachtet sie und baut die Leiste bei jeder Aenderung sofort um.
    init(settings: ShellSettingsStore) {
        // Der Dateimanager oben kommt aus den Einstellungen (Nexus > Anbieter).
        dock = SidebarDockModel(settings: settings)
        // Wetteranbieter ebenfalls aus den Einstellungen, wie im Dashboard.
        weather = BarWeatherFeed(settings: settings)
        let context = BarModuleContext(
            status: status, spaces: spaces, dock: dock, clock: clock, cpu: cpu, weather: weather,
            onDashboard: { [weak self] in self?.onDashboard() },
            onDashboardTab: { [weak self] in self?.onDashboardTab($0) },
            onUtilities: { [weak self] in self?.onUtilities() },
            onPower: { [weak self] in self?.onPower() },
            onSelectSpace: { [spaces] in spaces.switchTo($0) },
            onOpenApp: { BarApps.open($0) }
        )
        // Glas zeichnet SwiftUI (`SidebarRoot`), nicht mehr NSGlassEffectView:
        // nur im selben GlassEffectContainer verschmilzt das Popout mit der
        // Leiste.
        let hosting = FirstMouseHostingView(
            rootView: SidebarRoot(settings: settings, context: context, popout: popout.model)
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

    /// Popout offen: Fenster breiter, die Leiste bleibt links 44 breit, der
    /// Rest ist durchsichtig, bis das Glas hineinwaechst.
    private func setExpanded(_ expanded: Bool) {
        guard expanded != self.expanded else { return }
        self.expanded = expanded
        layout()
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
        let width = expanded ? StatusPopout.expandedWidth : Self.width
        let rect = NSRect(x: frame.minX, y: frame.minY, width: width, height: top - frame.minY)
        lastFrame = rect
        // Mit dem echten Panelrahmen vergleichen, nicht mit `lastFrame`: beim
        // Umstecken verschiebt macOS Fenster auch selbst.
        guard panel.frame != rect else { return }
        panel.setFrame(rect, display: true)
        if !expanded {
            log.notice("Sidebar \(Self.width, privacy: .public) x \(rect.height, privacy: .public) pt")
        }
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
                    .modifier(SidebarGlass(shape: SidebarGlassShape(barWidth: Sidebar.width, bulge: bulge)))
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

/// Liquid Glass in der Form der Leiste, in Bildproben durch eine feste
/// Flaeche ersetzt (Glas zeichnet ausserhalb des Bildschirms nur weiss).
private struct SidebarGlass<S: Shape>: ViewModifier {
    /// Feste Tönung statt reinem Glas: Ohne sie nimmt Liquid Glass die Farbe
    /// dessen an, was gerade dahinter liegt - die Leiste wechselte je nach
    /// Fenster darunter. `windowBackgroundColor` ist dynamisch, hell im
    /// hellen Erscheinungsbild und dunkel im dunklen, wie bei den anderen
    /// Fenstern.
    /// 0.85 statt 0.55: Bei 0.55 schlug die Farbe eines Fensters hinter der
    /// Leiste noch durch, die ganze Leiste wechselte beim Oeffnen die Farbe.
    private static var tint: Color { Color(nsColor: .windowBackgroundColor).opacity(0.85) }

    let shape: S
    @Environment(\.statusPopoutGlassStandIn) private var standIn
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if standIn {
            content.background(colorScheme == .dark ? Color(white: 0.17) : Color(white: 0.95), in: shape)
        } else {
            content.glassEffect(.regular.tint(Self.tint), in: shape)
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
