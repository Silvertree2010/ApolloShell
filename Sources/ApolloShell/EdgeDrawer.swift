import AppKit
import ApolloShellCore
import QuartzCore
import SwiftUI

/// Wo ein Kantenfenster sitzt.
enum DrawerEdge {
    /// Oben mittig, direkt unter der Menueleiste (Caelestia: Dashboard).
    case top
    /// Rechts, vertikal mittig (Caelestia: Sitzungsmenue, OSD).
    case right
    /// Ecke rechts unten (Caelestia: Utilities).
    case bottomRight
    /// Unten mittig, wo frueher Apples Dock sass (Launcher).
    case bottom
}

/// Wie ein Kantenfenster auf- und zugeht. Bewegt wird der Inhalt ueber die
/// sublayerTransform des Containers - das rechnet Core Animation auf der
/// GPU, anders als ein animiertes setFrame, das AppKit Bild fuer Bild auf
/// dem Hauptthread setzt und das Glas jedes Mal neu rendern laesst. Dazu
/// blendet das Fenster ein und aus.
enum DrawerMotion {
    /// Caelestia: um die eigene Groesse (+5) aus der Kante gleiten, 500 ms
    /// auf `MotionCurve.spatial` mit leichtem Ueberschiessen, Einblenden auf
    /// derselben Kurve.
    case slide
    /// Launcher: waechst aus der Mitte der Unterkante heraus (etwas kleiner
    /// und tiefer) und geht denselben Weg zurueck. Federn statt fester Dauer,
    /// kritisch gedaempft wie bei Apple: schnell los, weich auslaufen, kein
    /// Nachwippen (das gehoert zu Wisch-Gesten, nicht zu einem Tastendruck).
    /// Die erste Fassung (28 pt, nur Verschieben) war kaum wahrnehmbar.
    case grow

    /// Zu-Zustand der sublayerTransform.
    @MainActor
    func closedTransform(edge: DrawerEdge, size: NSSize, topInset: CGFloat, container: NSView) -> CATransform3D {
        switch self {
        case .slide:
            switch edge {
            case .top: CATransform3DMakeTranslation(0, size.height + topInset + 5, 0)
            case .right: CATransform3DMakeTranslation(size.width + 5, 0, 0)
            case .bottomRight, .bottom: CATransform3DMakeTranslation(0, -(size.height + 5), 0)
            }
        case .grow:
            Grow.closedTransform(for: container)
        }
    }

    /// Die Bewegung der sublayerTransform; `from`/`to` setzt der Aufrufer.
    func transformAnimation(opening: Bool) -> CABasicAnimation {
        switch self {
        case .slide:
            let animation = CABasicAnimation(keyPath: "sublayerTransform")
            animation.duration = MotionCurve.spatialDuration
            animation.timingFunction = .shellSpatial
            return animation
        case .grow:
            return Grow.spring(response: opening ? Grow.openResponse : Grow.closeResponse)
        }
    }

    /// Dauer und Kurve des Ein- bzw. Ausblendens. Beim Wachsen kuerzer als
    /// die Feder, damit das Glas sofort da ist.
    func fade(opening: Bool) -> (duration: TimeInterval, curve: CAMediaTimingFunction) {
        switch self {
        case .slide: (MotionCurve.spatialDuration, .shellSpatial)
        case .grow: (opening ? Grow.fadeIn : Grow.fadeOut, Grow.easeOut)
        }
    }

    private enum Grow {
        /// Federantwort in Sekunden (Apples "response"): wie schnell das Ziel
        /// erreicht wird. Oeffnen etwas ruhiger, Schliessen knapper.
        static let openResponse: CGFloat = 0.42
        static let closeResponse: CGFloat = 0.28
        static let fadeIn: TimeInterval = 0.16
        static let fadeOut: TimeInterval = 0.14
        /// Zu-Zustand: um `travel` Punkte tiefer und auf `closedScale` verkleinert.
        static let travel: CGFloat = 40
        static let closedScale: CGFloat = 0.92
        static var easeOut: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) }

        /// Bei "Bewegung reduzieren" die Identitaet, dann bleibt nur die Blende.
        ///
        /// Die sublayerTransform dreht um den anchorPoint des Layers. Offline
        /// gemessen: bei View-Layern ist der (0,0), also unten links, und y
        /// zeigt nach oben. Damit das Panel aus dem Dock waechst statt aus der
        /// Ecke, wird der Drehpunkt auf die Mitte der Unterkante verlegt:
        /// dorthin schieben, skalieren, zurueckschieben, dann nach unten
        /// versetzen.
        @MainActor
        static func closedTransform(for view: NSView) -> CATransform3D {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                return CATransform3DIdentity
            }
            guard let layer = view.layer else { return CATransform3DIdentity }
            let size = layer.bounds.size
            let flipped = layer.isGeometryFlipped
            let pivot = CGPoint(x: layer.anchorPoint.x * size.width, y: layer.anchorPoint.y * size.height)
            let bottomCenter = CGPoint(x: size.width / 2, y: flipped ? size.height : 0)
            let dx = bottomCenter.x - pivot.x
            let dy = bottomCenter.y - pivot.y
            let down: CGFloat = flipped ? 1 : -1

            var transform = CATransform3DMakeTranslation(-dx, -dy, 0)
            transform = CATransform3DConcat(transform, CATransform3DMakeScale(closedScale, closedScale, 1))
            transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(dx, dy + down * travel, 0))
            return transform
        }

        /// Kritisch gedaempfte Feder aus Apples "response" (Masse 1):
        /// Steifigkeit (2π/response)², Daempfung 4π·ζ/response mit ζ = 1.
        static func spring(response: CGFloat) -> CASpringAnimation {
            let spring = CASpringAnimation(keyPath: "sublayerTransform")
            spring.mass = 1
            spring.stiffness = pow(2 * .pi / response, 2)
            spring.damping = 4 * .pi / response
            spring.initialVelocity = 0
            spring.duration = spring.settlingDuration
            return spring
        }
    }
}

/// Abdunkelung des ganzen Bildschirms hinter dem Fenster; ein Klick darauf
/// schliesst es (Caelestia: Sitzungsmenue).
struct DrawerScrim {
    /// Wie dunkel, 0...1.
    let amount: CGFloat
    let duration: TimeInterval
    let curve: CAMediaTimingFunction
}

/// Glas-Panel, das an einer Bildschirmkante klebt und aus ihr herauskommt
/// (`DrawerMotion`), auf Wunsch vor abgedunkeltem Bildschirm
/// (`DrawerScrim`). Gemeinsamer Baustein fuer Dashboard, Utilities, OSD,
/// Sitzungsmenue und Launcher.
///
/// Es geht dort auf, wo der Zeiger steht, und die Maus oeffnet es an der
/// Kante JEDES Bildschirms - nicht nur am Hauptbildschirm. Solange es offen
/// ist, bleibt es auf seinem Bildschirm stehen, auch wenn der Zeiger
/// hinueberwandert.
///
/// Das Fenster ist um den Eckenradius groesser als sichtbar und ragt damit
/// ueber die Bildschirmkante(n): so liegen die Glasecken an der Kante
/// ausserhalb, und das Panel wirkt, als wuechse es aus ihr. Der Inhalt liegt
/// nur im sichtbaren Teil. Oben liegt das Glas ueber der Menueleiste bis an
/// die Kante; der Inhalt beginnt unter Menueleiste und Notch.
@MainActor
final class EdgeDrawer<Content: View>: NSObject, NSWindowDelegate {
    let edge: DrawerEdge
    let motion: DrawerMotion
    let scrim: DrawerScrim?
    /// Sichtbare Groesse (ohne den Teil, der ueber die Kante ragt). Aendert
    /// sich nur ueber `resize(to:)` (Utilities: Karten an/aus, mehr Reihen).
    private(set) var size: NSSize
    let cornerRadius: CGFloat
    /// Klick in eine andere App schliesst (Standard). Fuer rein anzeigende
    /// Fenster wie das OSD aus.
    var closesOnResignKey = true
    /// Tastatur annehmen (Esc schliesst). Fuer das OSD aus, damit es nie
    /// Fokus nimmt.
    let takesKeyboard: Bool
    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}
    /// Vor `applyGeometry`, sobald der Zielbildschirm feststeht - fuer den
    /// Massstab des Dashboards (`Dashboard.prepareForScreen`). Andere
    /// Kantenfenster lassen es `nil`.
    var prepareForScreen: ((NSScreen) -> Void)?
    /// Nach der Schliessbewegung, wenn das Fenster weg ist - nicht, wenn es
    /// vorher wieder aufging.
    var onHidden: () -> Void = {}

    /// Caelestia: erscheint, wenn die Maus an die Kante stoesst, und geht,
    /// wenn sie den Bereich verlaesst (Regeln in ApolloShellCore/EdgeHover).
    /// Oben (Dashboard) und unten rechts (Utilities).
    var opensOnHover = false {
        didSet { updateHoverMonitor() }
    }
    /// Bildschirme, auf denen eine Vollbild-App steht: dort oeffnet die Maus
    /// an der Kante nichts (Caelestia ebenso). Auf den uebrigen Bildschirmen
    /// geht es weiter.
    var suspendedScreens: Set<CGDirectDisplayID> = []
    /// Waehrend einer Bearbeitung (Dashboard, Bento-Seiten): haelt das Fenster
    /// offen, egal wo die Maus steht - Hover schliesst nicht, `Esc` schliesst
    /// nicht, ein Klick in eine andere App (Nexus) schliesst nicht, und
    /// `toggle()`/`open()`/`close()` von aussen wirken nicht. Entpinnen
    /// schliesst von selbst, ausser der Zeiger steht noch im Aufklapp-Bereich
    /// - dann uebernimmt von dort das uebliche Hover-Verhalten; sonst bliebe
    /// das Fenster sonst unbegrenzt offen stehen (`unpin()`).
    ///
    /// Waehrend `isPinned` gilt zusaetzlich (Spec Abschnitt 4,
    /// "window-manager-safe"): `.stationary` statt `.transient` (Fenstermanager
    /// wie AeroSpace/yabai/Amethyst kacheln oder verschieben ein `.transient`-
    /// Fenster sonst mit, sobald es laenger als einen Wisch offen bleibt),
    /// nicht-Standard-Bedienungshilfen-Subrolle und aus dem Fenstermenue
    /// ausgeschlossen - wie `EditModePanel`, aber nur, solange gepinnt (ein
    /// nicht angepinntes Kantenfenster bleibt `.transient`: es soll ein
    /// Fenstermanager-Tastenkuerzel weiterhin schliessen duerfen). Der Wert
    /// wirkt auf `builtPanel`, falls es schon gebaut ist, und auf jedes neu
    /// gebaute (`makePanel()`).
    var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            builtPanel?.setPinned(isPinned)
            guard oldValue, !isPinned else { return }
            unpin()
        }
    }
    private var hoverState = EdgeHoverState.hidden
    private var hoverMonitor: Any?
    /// Solange offen: Mausposition selbst nachsehen. Der globale Monitor
    /// sieht keine Bewegungen ueber eigenen Fenstern (Panel, Leiste).
    private var hoverTimer: Timer?

    private let rootView: Content
    /// Erst beim ersten Oeffnen gebaut. Nicht als `lazy var`: deren
    /// Initialisierer sieht Swift 6.3.3 nicht als MainActor an und warnt,
    /// dass die View-Konformanz von `Content` dorthin nicht mitdarf.
    private var builtPanel: DrawerPanel?
    private var panel: DrawerPanel {
        if let builtPanel { return builtPanel }
        let panel = makePanel()
        builtPanel = panel
        return panel
    }
    private let container: NSView
    private var builtScrim: ScrimWindow?
    /// Glas und SwiftUI-Inhalt darin; `resize(to:)` setzt ihre Rahmen neu.
    private var glass: NSGlassEffectView?
    private var hosting: NSView?
    /// Die eingefaerbte Flaeche unter dem Glas, wenn ein Theme gilt.
    private var panelLayer: CAGradientLayer?
    private(set) var isOpen = false
    private var generation = 0

    /// Auf welchem Bildschirm das Fenster gerade steht bzw. zuletzt stand.
    private(set) var currentScreen: ShellScreen?

    /// Nur oben: Streifen unter Menueleiste und Kamera-Notch. Das Glas reicht
    /// bis an die Bildschirmkante (wie Utilities unten rechts), der Inhalt
    /// beginnt erst darunter - in der Notch waere er abgeschnitten.
    ///
    /// Kein fester Wert mehr: nicht jeder Bildschirm hat eine Menueleiste,
    /// und eine Notch hat ohnehin nur der eingebaute. Beim Oeffnen wird er
    /// fuer den Zielbildschirm neu bestimmt (`applyGeometry`).
    private var topInset: CGFloat

    init(edge: DrawerEdge, size: NSSize, cornerRadius: CGFloat, takesKeyboard: Bool = true,
         motion: DrawerMotion = .slide, scrim: DrawerScrim? = nil, rootView: Content) {
        self.edge = edge
        self.motion = motion
        self.scrim = scrim
        self.size = size
        self.cornerRadius = cornerRadius
        self.takesKeyboard = takesKeyboard
        self.rootView = rootView
        topInset = edge == .top ? Self.menuBarInset(NSScreen.screens.first) : 0
        container = NSView(frame: NSRect(
            origin: .zero,
            size: Self.windowSize(for: edge, size: size, radius: cornerRadius, topInset: topInset)
        ))
        super.init()
        observeScreenChanges()
    }

    /// Faerbt das Glas des Kantenfensters nach dem Theme: Panelfarbe als
    /// Toenung, Panelradius als Ecke. Ohne Theme bleibt alles, wie es war.
    /// Wird beim Bauen und bei jedem Oeffnen gesetzt, damit ein Wechsel im
    /// Theme spaetestens beim naechsten Oeffnen ankommt.
    /// Faerbt das Kantenfenster nach dem Theme (siehe `ThemedGlass`).
    private func applyTheme() {
        panelLayer = ThemedGlass.apply(to: glass, fallbackRadius: cornerRadius, previous: panelLayer)
    }

    /// Hoehe der Menueleiste bzw. der Notch, je nachdem was groesser ist
    /// (Menueleiste ausgeblendet: dann zaehlt nur die Notch). Bildschirme
    /// ohne Menueleiste ergeben 0.
    private static func menuBarInset(_ screen: NSScreen?) -> CGFloat {
        guard let screen else { return 0 }
        return max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
    }

    /// Waehrend einer Bearbeitung (`isPinned`) wirkt weder Symbol noch
    /// Tastenkombination - das Fenster bleibt, bis die Bearbeitung endet.
    func toggle() {
        guard !isPinned else { return }
        isOpen ? close() : open()
    }

    /// Rahmen des Fensters auf dem Bildschirm, solange offen - fuer Fenster,
    /// die ihm ausweichen muessen (Werkzeugleiste und Galerie des
    /// Bearbeitungsmodus). Enthaelt den Ueberhang an der Kante; fuer das
    /// Ausweichen reicht das.
    var openFrame: NSRect? { isOpen ? builtPanel?.frame : nil }

    /// Tastatur holen, solange offen - z. B. fuer das Umbenennen einer Seite
    /// im Bearbeitungsmodus, wenn inzwischen ein anderes Kantenfenster
    /// (Kontrollzentrum) Schluesselfenster ist. Nur fuer Fenster, die
    /// ueberhaupt Tastatur annehmen (`takesKeyboard`).
    func takeKeyboard() {
        guard isOpen, takesKeyboard else { return }
        panel.makeKey()
    }

    /// Per Tastenkombination oder Symbol.
    func open() {
        guard !isPinned else { return }
        guard let screen = ShellScreens.underPointer() else { return }
        open(byHover: false, on: screen)
    }

    /// Auf einem bestimmten Bildschirm statt dem unter dem Zeiger - fuer eine
    /// Bearbeitung, die von Nexus aus beginnt (`isPinned`).
    func open(on screen: NSScreen) {
        // Ueber die Display-Kennung; findet sie nichts (Bildschirm gerade
        // weg), dann dort, wo der Zeiger steht - ein angepinntes Fenster, das
        // stumm gar nicht aufgeht, liesse die Bearbeitung ohne Panel stehen.
        guard let target = ShellScreens.matching(screen) ?? ShellScreens.underPointer() else { return }
        open(byHover: false, on: target)
    }

    /// Per Maus geoeffnet nimmt es keinen Fokus: die App darunter behaelt die
    /// Tastatur, man faehrt ja nur vorbei.
    private func open(byHover: Bool, on screen: ShellScreen) {
        guard !isOpen else { return }
        applyTheme()
        isOpen = true
        generation += 1
        afterClose = nil
        prepareForScreen?(screen.screen)
        // Vor dem ersten Zugriff auf `panel`: der baut sein Fenster aus der
        // Groesse des Containers, und die haengt am Bildschirm.
        applyGeometry(on: screen)
        if byHover {
            hoverState = EdgeHoverState(visible: true, shortcutActive: false)
        } else {
            let inArea = hoverArea(on: screen, open: true)?.contains(NSEvent.mouseLocation) ?? false
            hoverState = .openedByShortcut(mouseInArea: inArea)
        }
        startHoverTimer()
        onOpen()

        panel.setFrame(windowFrame(on: screen), display: false)
        if !panel.isVisible {
            setSlide(closed: true, animated: false)
            panel.alphaValue = 0
        }
        if let scrim, let scrimWindow = scrimWindow() {
            scrimWindow.setFrame(screen.frame, display: false)
            if !scrimWindow.isVisible { scrimWindow.alphaValue = 0 }
            scrimWindow.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = scrim.duration
                context.timingFunction = scrim.curve
                scrimWindow.animator().alphaValue = scrim.amount
            }
        }
        if takesKeyboard && !byHover {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        setSlide(closed: false, animated: true)
        let fade = motion.fade(opening: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fade.duration
            context.timingFunction = fade.curve
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        generation += 1
        let current = generation
        hoverState = .hidden
        hoverTimer?.invalidate()
        hoverTimer = nil
        onClose()

        setSlide(closed: true, animated: true)
        if let scrim, let scrimWindow = builtScrim {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = scrim.duration
                context.timingFunction = scrim.curve
                scrimWindow.animator().alphaValue = 0
            }
        }
        let fade = motion.fade(opening: false)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fade.duration
            context.timingFunction = fade.curve
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
                self.builtScrim?.orderOut(nil)
                self.onHidden()
                let action = self.afterClose
                self.afterClose = nil
                action?()
            }
        })
    }

    /// Schliessen und `then` erst ausfuehren, wenn das Panel ganz vom
    /// Bildschirm ist. Fuer Aktionen, die sonst mit dem Panel kollidieren:
    /// Solange es Schluesselfenster ist, landen gepostete Tasten (⌃⌘Q) bei
    /// uns statt bei der App vorne, und Pipette oder Bildschirmfoto saehen
    /// das halb ausgeblendete Glas. Geht es vorher wieder auf, entfaellt
    /// `then` - man hat es sich anders ueberlegt.
    ///
    /// Waehrend des Ausblendens ist das Panel noch klickbar. Ein Klick in
    /// dieser Zeit wartet ebenfalls, ein zweiter (Doppelklick) entfaellt
    /// (`DrawerCloseStep`).
    func close(then: @escaping @MainActor () -> Void) {
        let step = DrawerCloseStep(
            isOpen: isOpen,
            isVisible: builtPanel?.isVisible ?? false,
            hasPendingAction: afterClose != nil
        )
        switch step {
        case .closeThenRun:
            close()
            afterClose = then
        case .runAfterFade:
            afterClose = then
        case .drop:
            break
        case .runNow:
            then()
        }
    }

    private var afterClose: (@MainActor () -> Void)?

    // MARK: - Groesse aendern

    /// Masse fuer diesen Bildschirm uebernehmen. Oben haengt die Fensterhoehe
    /// an der Menueleiste, und die ist nicht auf jedem Bildschirm gleich hoch
    /// (ein zweiter Bildschirm hat je nach Einstellung gar keine).
    private func applyGeometry(on screen: ShellScreen) {
        currentScreen = screen
        let inset = edge == .top ? Self.menuBarInset(screen.screen) : 0
        let wanted = Self.windowSize(for: edge, size: size, radius: cornerRadius, topInset: inset)
        guard inset != topInset || container.frame.size != wanted else { return }
        topInset = inset
        container.setFrameSize(wanted)
        // Wie in `resize(to:)`: die Inhaltsflaeche ausdruecklich setzen, nicht
        // per autoresizing.
        if let glass {
            glass.frame = container.bounds
            glass.contentView?.frame = glass.bounds
        }
        hosting?.frame = visibleRectInWindow
    }

    /// Neue sichtbare Groesse, sofort und ohne Animation.
    ///
    /// Warum ohne: offen aendert sich im selben Durchgang auch der Inhalt
    /// (Karte weg, Reihe dazu) - er springt ohnehin, ein gleitender Rahmen
    /// liefe ihm nur hinterher und zeigte fuer ein paar Bilder zu wenig oder
    /// zu viel Glas. Zu merkt man nichts: das Fenster ist nicht auf dem
    /// Bildschirm, und `open()` schiebt es mit der neuen Groesse aus der Kante.
    ///
    /// Die Kante haelt: unten rechts waechst das Fenster nach oben, oben
    /// nach unten, rechts in beide Richtungen um die Mitte.
    func resize(to newSize: NSSize) {
        guard newSize != size else { return }
        size = newSize
        container.setFrameSize(Self.windowSize(for: edge, size: newSize, radius: cornerRadius, topInset: topInset))
        guard let builtPanel else { return }
        if let screen = currentScreen ?? ShellScreens.underPointer() {
            builtPanel.setFrame(windowFrame(on: screen), display: builtPanel.isVisible)
        }
        // Das Glas waechst per autoresizing mit dem Container. Seine
        // Inhaltsflaeche NICHT: mit autoresizing kam sie in der Bildprobe
        // (14.09.) verzerrt heraus (451 -> 162 ergab 10, danach 852) - also
        // ausdruecklich auf die Glasgroesse. Der SwiftUI-Inhalt liegt nur im
        // sichtbaren Teil.
        if let glass {
            glass.frame = container.bounds
            glass.contentView?.frame = glass.bounds
        }
        hosting?.frame = visibleRectInWindow
    }

    /// Fuer Bildproben und Pruefungen: wo Fenster, Glas und Inhalt gerade
    /// liegen. Baut das Fenster, zeigt es aber nicht.
    func probeGeometry() -> (window: NSRect, container: NSRect, glass: NSRect, content: NSRect, hosting: NSRect) {
        _ = panel
        return (panel.frame, container.frame, glass?.frame ?? .zero, glass?.contentView?.frame ?? .zero,
                hosting?.frame ?? .zero)
    }

    // MARK: - Maus an der Kante

    /// Globaler Monitor nur fuer Mausbewegung: braucht keine Freigabe (nur
    /// Tastatur-Monitore brauchen die Bedienungshilfen). Die Pruefung pro
    /// Bewegung ist ein Rechteck-Vergleich.
    private func updateHoverMonitor() {
        if opensOnHover, hoverMonitor == nil {
            hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                MainActor.assumeIsolated { self?.hoverMoved() }
            }
        } else if !opensOnHover, let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
            hoverMonitor = nil
        }
    }

    private func startHoverTimer() {
        guard opensOnHover, hoverTimer == nil else { return }
        hoverTimer = .repeating(every: 0.05, owner: self) { $0.hoverMoved() }
    }

    /// Entpinnen (Bearbeitung fertig/abgebrochen): ohne das wuerde das
    /// Fenster unbegrenzt offen bleiben, da `hoverMoved()` waehrend `isPinned`
    /// nichts pruefte und `hoverState` seither veraltet ist. Steht der Zeiger
    /// noch im Aufklapp-Bereich, uebernimmt von dort das uebliche
    /// Hover-Verhalten (offen bleiben, bis er hinausgeht); sonst gleich zu.
    private func unpin() {
        guard isOpen else { return }
        guard opensOnHover, let target = currentScreen, !suspendedScreens.contains(target.displayID),
              let area = hoverArea(on: target, open: true), area.contains(NSEvent.mouseLocation)
        else {
            close()
            return
        }
        hoverState = EdgeHoverState(visible: true, shortcutActive: false)
    }

    private func hoverMoved() {
        guard opensOnHover else { return }
        // Waehrend einer Bearbeitung bleibt es offen auf seinem Bildschirm,
        // egal wo die Maus steht.
        if isOpen && isPinned { return }
        // Offen: der Bildschirm, auf dem das Fenster steht - sonst risse ein
        // Zeiger, der hinueberwandert, es sofort wieder zu. Zu: der unter dem
        // Zeiger, damit die Kante jedes Bildschirms oeffnet.
        let target = isOpen ? currentScreen : ShellScreens.underPointer()
        guard let target, !suspendedScreens.contains(target.displayID),
              let area = hoverArea(on: target, open: isOpen)
        else { return }
        let next = hoverState.moved(inArea: area.contains(NSEvent.mouseLocation))
        if next.visible && !isOpen {
            open(byHover: true, on: target)
        } else if !next.visible && isOpen {
            close()
        } else {
            hoverState = next
        }
    }

    private func hoverArea(on screen: ShellScreen, open: Bool) -> NSRect? {
        switch edge {
        case .top:
            let inset = Self.menuBarInset(screen.screen)
            return EdgeHoverArea.top(screen: screen.frame, width: size.width, depth: inset + size.height,
                                     margin: cornerRadius, open: open)
        case .bottomRight:
            return EdgeHoverArea.bottomRight(screen: screen.frame, width: size.width, height: size.height,
                                             margin: cornerRadius, open: open)
        case .right, .bottom:
            return nil
        }
    }

    // MARK: - Bildschirme wechseln

    /// Umgesteckt oder anders aufgeloest: ist der Bildschirm des offenen
    /// Fensters weg, geht es zu - sonst stuende es auf einem Rahmen, den es
    /// nicht mehr gibt. Ist er noch da, wird neu vermessen.
    private func observeScreenChanges() {
        ShellScreens.onChange { [weak self] in
            guard let self, self.isOpen, let current = self.currentScreen else { return }
            guard let same = ShellScreens.current().first(where: { $0.displayID == current.displayID }) else {
                self.close()
                return
            }
            self.applyGeometry(on: same)
            self.builtPanel?.setFrame(self.windowFrame(on: same), display: true)
            self.builtScrim?.setFrame(same.frame, display: true)
        }
    }

    // MARK: - Geometrie

    /// Fenster = sichtbar + Radius an jeder Kante, an der es klebt (oben
    /// zusaetzlich der Menueleisten-Streifen).
    private static func windowSize(for edge: DrawerEdge, size: NSSize, radius: CGFloat, topInset: CGFloat) -> NSSize {
        switch edge {
        case .top: NSSize(width: size.width, height: size.height + topInset + radius)
        case .right: NSSize(width: size.width + radius, height: size.height)
        case .bottomRight: NSSize(width: size.width + radius, height: size.height + radius)
        case .bottom: NSSize(width: size.width, height: size.height + radius)
        }
    }

    /// Wo der sichtbare Teil im Fenster liegt (AppKit-Koordinaten, y nach oben).
    private var visibleRectInWindow: NSRect {
        switch edge {
        case .top: NSRect(x: 0, y: 0, width: size.width, height: size.height)
        case .right: NSRect(x: 0, y: 0, width: size.width, height: size.height)
        case .bottomRight, .bottom: NSRect(x: 0, y: cornerRadius, width: size.width, height: size.height)
        }
    }

    private func windowFrame(on screen: ShellScreen) -> NSRect {
        let frame = screen.frame
        let windowSize = container.frame.size
        switch edge {
        case .top:
            // Glas buendig an der Oberkante (ueber der Menueleiste), der
            // Radius-Streifen ragt ueber den Bildschirm hinaus. Frueher
            // endete es unter der Menueleiste - mit der durchsichtigen
            // Menueleiste von macOS 26 sah das aus wie ein schwebendes
            // Fenster mit Abstand.
            return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - topInset - size.height,
                          width: windowSize.width, height: windowSize.height)
        case .right:
            return NSRect(x: frame.maxX - size.width, y: frame.midY - size.height / 2,
                          width: windowSize.width, height: windowSize.height)
        case .bottomRight:
            return NSRect(x: frame.maxX - size.width, y: frame.minY - cornerRadius,
                          width: windowSize.width, height: windowSize.height)
        case .bottom:
            // Buendig an der Unterkante; die unteren Ecken ragen hinaus.
            return NSRect(x: frame.midX - size.width / 2, y: frame.minY - cornerRadius,
                          width: windowSize.width, height: windowSize.height)
        }
    }

    // MARK: - Bewegung

    /// Setzt die Inhaltsverschiebung, bewegt oder sofort. Startet immer beim
    /// sichtbaren Wert, damit ein Umdrehen mitten in der Bewegung nicht
    /// springt.
    private func setSlide(closed: Bool, animated: Bool) {
        guard let layer = container.layer else { return }
        let target = closed
            ? motion.closedTransform(edge: edge, size: size, topInset: topInset, container: container)
            : CATransform3DIdentity
        let current = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = target
        CATransaction.commit()

        guard animated else {
            layer.removeAnimation(forKey: "drawer.slide")
            return
        }
        let animation = motion.transformAnimation(opening: !closed)
        animation.fromValue = NSValue(caTransform3D: current)
        animation.toValue = NSValue(caTransform3D: target)
        layer.add(animation, forKey: "drawer.slide")
    }

    // MARK: - Fenster

    private func makePanel() -> DrawerPanel {
        // Mit Abdunkelung eine Ebene darueber.
        let level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + (scrim == nil ? 0 : 1))
        let panel = DrawerPanel(size: container.frame.size, level: level, takesKeyboard: takesKeyboard)
        panel.delegate = self
        panel.setPinned(isPinned)
        panel.onEscape = { [weak self] in
            guard let self, !self.isPinned else { return }
            self.close()
        }

        let glass = NSGlassEffectView(frame: container.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.cornerRadius = cornerRadius

        let content = NSView(frame: container.bounds)
        let hosting = FirstMouseHostingView(rootView: rootView.shellTheme())
        hosting.sizingOptions = []
        hosting.frame = visibleRectInWindow
        content.addSubview(hosting)
        glass.contentView = content
        self.glass = glass
        applyTheme()
        self.hosting = hosting

        container.wantsLayer = true
        container.addSubview(glass)
        panel.contentView = container
        return panel
    }

    private func scrimWindow() -> ScrimWindow? {
        guard scrim != nil else { return nil }
        if let builtScrim { return builtScrim }
        let window = ScrimWindow()
        window.onClick = { [weak self] in self?.close() }
        builtScrim = window
        return window
    }

    func windowDidResignKey(_ notification: Notification) {
        if closesOnResignKey && !isPinned { close() }
    }
}

/// Randloses Panel fuer Kantenfenster. Ebene ueber allem wie das
/// Sitzungsmenue - oben auch ueber der Menueleiste, damit das Glas bis an
/// die Kante reicht. Darf ueber den Bildschirmrand ragen.
final class DrawerPanel: ShellPanel {
    var onEscape: () -> Void = {}

    /// Verhalten/Subrolle/Fenstermenue ausserhalb einer Bearbeitung - was
    /// `setPinned(false)` wiederherstellt.
    private static let unpinnedBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
    /// Waehrend `EdgeDrawer.isPinned` (Spec Abschnitt 4): wie `EditModePanel`,
    /// aber nur so lange - siehe `isPinned`.
    private static let pinnedBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

    init(size: NSSize, level: NSWindow.Level, takesKeyboard: Bool) {
        super.init(size: size, level: level,
                   behavior: Self.unpinnedBehavior,
                   takesKeyboard: takesKeyboard, mayLeaveScreen: true)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }

    /// Task 7 (Spec Abschnitt 4, "window-manager-safe"): waehrend einer
    /// Bearbeitung soll ein Fenstermanager das angepinnte Kantenfenster genau
    /// so unberuehrt lassen wie die Fenster des Bearbeitungsmodus selbst
    /// (`EditModePanel`) - `.stationary` statt `.transient`, eine
    /// Nicht-Standard-Subrolle und raus aus dem Fenstermenue. Entpinnt stellt
    /// die drei Werte von vorher wieder her.
    func setPinned(_ pinned: Bool) {
        collectionBehavior = pinned ? Self.pinnedBehavior : Self.unpinnedBehavior
        setAccessibilitySubrole(pinned ? .unknown : nil)
        isExcludedFromWindowsMenu = pinned
    }
}

/// Vollbild-Abdunkelung hinter einem Kantenfenster (`DrawerScrim`). Liegt
/// ueber Menueleiste und Dock, faengt Klicks ab und schliesst dann das Fenster.
final class ScrimWindow: ShellPanel {
    var onClick: () -> Void = {}

    init() {
        super.init(level: .popUpMenu, behavior: [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary])
        backgroundColor = .black
        contentView = ClickView { [weak self] in self?.onClick() }
    }
}

/// Nimmt schon den ersten Klick an, auch wenn die App nicht aktiv ist.
private final class ClickView: NSView {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("nicht benutzt") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { action() }
}
