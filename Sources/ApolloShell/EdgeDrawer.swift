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
}

/// Glas-Panel, das an einer Bildschirmkante klebt und wie bei Caelestia aus
/// ihr herausgleitet: 500 ms, Caelestias "DefaultSpatial"-Kurve
/// cubic-bezier(0.38, 1.21, 0.22, 1) mit leichtem Ueberschiessen, dazu
/// Einblenden. Gemeinsamer Baustein fuer Dashboard, Utilities, OSD.
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
///
/// Das Sitzungsmenue benutzt diesen Baustein (noch) nicht; es war vorher da
/// und funktioniert.
@MainActor
final class EdgeDrawer<Content: View>: NSObject, NSWindowDelegate {
    private static var slideDuration: TimeInterval { 0.5 }
    private static var slideCurve: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.38, 1.21, 0.22, 1)
    }

    let edge: DrawerEdge
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
    /// Glas und SwiftUI-Inhalt darin; `resize(to:)` setzt ihre Rahmen neu.
    private var glass: NSGlassEffectView?
    private var hosting: NSView?
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

    init(edge: DrawerEdge, size: NSSize, cornerRadius: CGFloat, takesKeyboard: Bool = true, rootView: Content) {
        self.edge = edge
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

    /// Hoehe der Menueleiste bzw. der Notch, je nachdem was groesser ist
    /// (Menueleiste ausgeblendet: dann zaehlt nur die Notch). Bildschirme
    /// ohne Menueleiste ergeben 0.
    private static func menuBarInset(_ screen: NSScreen?) -> CGFloat {
        guard let screen else { return 0 }
        return max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
    }

    func toggle() {
        isOpen ? close() : open()
    }

    /// Per Tastenkombination oder Symbol.
    func open() {
        open(byHover: false)
    }

    /// Per Maus geoeffnet nimmt es keinen Fokus: die App darunter behaelt die
    /// Tastatur, man faehrt ja nur vorbei.
    private func open(byHover: Bool) {
        // Dort, wo der Zeiger steht.
        guard !isOpen, let screen = ShellScreens.underPointer() else { return }
        isOpen = true
        generation += 1
        afterClose = nil
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
        if takesKeyboard && !byHover {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        setSlide(closed: false, animated: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.slideDuration
            context.timingFunction = Self.slideCurve
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
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.slideDuration
            context.timingFunction = Self.slideCurve
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
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
    func close(then: @escaping @MainActor () -> Void) {
        guard isOpen else { return then() }
        close()
        afterClose = then
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
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hoverMoved() }
        }
    }

    private func hoverMoved() {
        guard opensOnHover else { return }
        // Offen: der Bildschirm, auf dem das Fenster steht - sonst risse ein
        // Zeiger, der hinueberwandert, es sofort wieder zu. Zu: der unter dem
        // Zeiger, damit die Kante jedes Bildschirms oeffnet.
        let target = isOpen ? currentScreen : ShellScreens.underPointer()
        guard let target, !suspendedScreens.contains(target.displayID),
              let area = hoverArea(on: target, open: isOpen)
        else { return }
        let next = hoverState.moved(inArea: area.contains(NSEvent.mouseLocation))
        if next.visible && !isOpen {
            open(byHover: true)
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
        case .right:
            return nil
        }
    }

    // MARK: - Bildschirme wechseln

    /// Umgesteckt oder anders aufgeloest: ist der Bildschirm des offenen
    /// Fensters weg, geht es zu - sonst stuende es auf einem Rahmen, den es
    /// nicht mehr gibt. Ist er noch da, wird neu vermessen.
    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isOpen, let current = self.currentScreen else { return }
                guard let same = ShellScreens.current().first(where: { $0.displayID == current.displayID }) else {
                    self.close()
                    return
                }
                self.applyGeometry(on: same)
                self.builtPanel?.setFrame(self.windowFrame(on: same), display: true)
            }
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
        }
    }

    /// Wo der sichtbare Teil im Fenster liegt (AppKit-Koordinaten, y nach oben).
    private var visibleRectInWindow: NSRect {
        switch edge {
        case .top: NSRect(x: 0, y: 0, width: size.width, height: size.height)
        case .right: NSRect(x: 0, y: 0, width: size.width, height: size.height)
        case .bottomRight: NSRect(x: 0, y: cornerRadius, width: size.width, height: size.height)
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
        }
    }

    // MARK: - Bewegung

    /// Geschlossen: um die eigene Groesse (+5, wie Caelestia) in die Kante
    /// zurueckgeschoben. Ueber die sublayerTransform, also auf der GPU, und
    /// immer ab dem sichtbaren Wert, damit Umdrehen nicht springt.
    private var closedTransform: CATransform3D {
        switch edge {
        case .top: CATransform3DMakeTranslation(0, size.height + topInset + 5, 0)
        case .right: CATransform3DMakeTranslation(size.width + 5, 0, 0)
        case .bottomRight: CATransform3DMakeTranslation(0, -(size.height + 5), 0)
        }
    }

    private func setSlide(closed: Bool, animated: Bool) {
        guard let layer = container.layer else { return }
        let target = closed ? closedTransform : CATransform3DIdentity
        let current = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = target
        CATransaction.commit()

        guard animated else {
            layer.removeAnimation(forKey: "drawer.slide")
            return
        }
        let animation = CABasicAnimation(keyPath: "sublayerTransform")
        animation.fromValue = NSValue(caTransform3D: current)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = Self.slideDuration
        animation.timingFunction = Self.slideCurve
        layer.add(animation, forKey: "drawer.slide")
    }

    // MARK: - Fenster

    private func makePanel() -> DrawerPanel {
        let panel = DrawerPanel(size: container.frame.size, edge: edge, takesKeyboard: takesKeyboard)
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }

        let glass = NSGlassEffectView(frame: container.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.cornerRadius = cornerRadius

        let content = NSView(frame: container.bounds)
        let hosting = FirstMouseHostingView(rootView: rootView)
        hosting.sizingOptions = []
        hosting.frame = visibleRectInWindow
        content.addSubview(hosting)
        glass.contentView = content
        self.glass = glass
        self.hosting = hosting

        container.wantsLayer = true
        container.addSubview(glass)
        panel.contentView = container
        return panel
    }

    func windowDidResignKey(_ notification: Notification) {
        if closesOnResignKey { close() }
    }
}

/// Randloses Panel fuer Kantenfenster. Ebene ueber allem wie das
/// Sitzungsmenue - oben auch ueber der Menueleiste, damit das Glas bis an
/// die Kante reicht. Darf ueber den Bildschirmrand ragen.
final class DrawerPanel: NSPanel {
    var onEscape: () -> Void = {}
    private let takesKeyboard: Bool

    init(size: NSSize, edge: DrawerEdge, takesKeyboard: Bool) {
        self.takesKeyboard = takesKeyboard
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        // Kein Fensterschatten: gab beim Launcher einen zweiten Rahmen ums Glas.
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { takesKeyboard }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }
}
