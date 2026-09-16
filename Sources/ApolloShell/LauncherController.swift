import AppKit
import ApolloShellCore
import QuartzCore
import SwiftUI
import os

/// Oeffnet und schliesst den Launcher: Panel unten mittig, dort wo frueher
/// der Dock sass. Apples Dock laesst der Launcher in Ruhe: frueher liess er
/// ihn beim Oeffnen wegfahren - einen dauerhaft ausgeblendeten Dock wuerde
/// das beim Schliessen wieder hervorholen.
@MainActor
final class LauncherController: NSObject, NSWindowDelegate {
    /// Sichtbare Groesse.
    static let size = NSSize(width: 560, height: 520)
    /// Buendig an der Unterkante wie die Kantenfenster (frueher schwebte er
    /// 12 pt ueber dem Rand - ohne sichtbaren Apple-Dock wirkte das
    /// losgeloest): das Fenster ist um den Eckenradius hoeher und ragt damit
    /// unter den Bildschirm - die unteren Ecken liegen ausserhalb.
    static let cornerRadius: CGFloat = 26
    static var windowSize: NSSize { NSSize(width: size.width, height: size.height + cornerRadius) }

    /// Startet der Launcher selbst eine App, meldet macOS das kurz danach
    /// noch einmal als Programmstart. Innerhalb dieses Fensters nicht doppelt
    /// zaehlen.
    private static let ownLaunchWindow: TimeInterval = 10

    private let model = LauncherModel()
    private let catalog = AppCatalog()
    private let usage = UsageStore()
    private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "controller")
    private lazy var panel = makePanel()
    /// Traeger der Bewegung. Das Fenster selbst bleibt stehen; verschoben
    /// wird nur der Inhalt ueber die sublayerTransform dieses Views. Das
    /// rechnet Core Animation auf der GPU - anders als ein animiertes
    /// Fensterrahmen-setFrame, das AppKit Bild fuer Bild auf dem Hauptthread
    /// setzt und das Glas dabei jedes Mal neu rendern laesst.
    private let container = NSView(frame: NSRect(origin: .zero, size: LauncherController.windowSize))
    private(set) var isOpen = false
    /// Verhindert, dass eine alte Schliess-Animation ein neu geoeffnetes
    /// Panel am Ende noch ausblendet.
    private var animationGeneration = 0
    private var ownLaunches: [String: Date] = [:]

    override init() {
        super.init()
        model.onLaunch = { [weak self] app in self?.launch(app) }
        model.onClose = { [weak self] in self?.close() }
        observeAppLaunches()
    }

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        animationGeneration += 1
        model.reload(catalog.scan(), usage: usage.stats, pinned: PinnedApps.load())

        panel.setFrame(targetFrame(), display: false)
        if !panel.isVisible {
            // Frisch aus dem Nichts: im Zu-Zustand beginnen.
            setContentTransform(Motion.closedTransform(for: container), springResponse: nil)
            panel.alphaValue = 0
        }

        panel.makeKeyAndOrderFront(nil)

        setContentTransform(CATransform3DIdentity, springResponse: Motion.openResponse)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.fadeIn
            context.timingFunction = Motion.easeOut
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        animationGeneration += 1
        let generation = animationGeneration

        setContentTransform(Motion.closedTransform(for: container), springResponse: Motion.closeResponse)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.fadeOut
            context.timingFunction = Motion.easeOut
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.animationGeneration == generation else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    /// Setzt die Inhaltsverschiebung, mit Feder oder sofort (`nil`).
    /// Startet immer beim aktuell sichtbaren Wert, damit ein Umdrehen mitten
    /// in der Bewegung nicht springt.
    private func setContentTransform(_ target: CATransform3D, springResponse: CGFloat?) {
        guard let layer = container.layer else { return }
        let current = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = target
        CATransaction.commit()

        guard let response = springResponse else {
            layer.removeAnimation(forKey: Motion.key)
            return
        }
        let spring = Motion.spring(response: response)
        spring.fromValue = NSValue(caTransform3D: current)
        spring.toValue = NSValue(caTransform3D: target)
        layer.add(spring, forKey: Motion.key)
    }

    private func launch(_ app: AppEntry) {
        close()
        usage.record(app.usageKey)
        ownLaunches[app.usageKey] = Date()
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init()) { [log] _, error in
            if let error {
                log.error("Start fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Nutzung auch ausserhalb des Launchers zaehlen

    /// Starts ueber Dock, Finder oder Spotlight zaehlen fuer die Sortierung
    /// genauso. Nur echte Apps mit Fenster, keine Hintergrunddienste.
    private func observeAppLaunches() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let app, app.activationPolicy == .regular,
                  let key = app.bundleIdentifier ?? app.bundleURL?.path
            else { return }
            MainActor.assumeIsolated { self?.recordExternalLaunch(key) }
        }
    }

    private func recordExternalLaunch(_ key: String) {
        if let own = ownLaunches[key], Date().timeIntervalSince(own) < Self.ownLaunchWindow {
            return
        }
        usage.record(key)
    }

    // MARK: - Fenster

    private func targetFrame() -> NSRect {
        // Dort, wo der Zeiger steht - nicht immer auf dem Hauptbildschirm.
        let screen = ShellScreens.underPointer()?.frame ?? NSScreen.main?.frame ?? .zero
        let origin = NSPoint(
            x: screen.midX - Self.size.width / 2,
            y: screen.minY - Self.cornerRadius
        )
        return NSRect(origin: origin, size: Self.windowSize)
    }

    private func makePanel() -> LauncherPanel {
        let panel = LauncherPanel(size: Self.windowSize)
        panel.delegate = self

        let hosting = NSHostingView(rootView: LauncherView(model: model))
        // Das Panel hat eine feste Groesse; SwiftUI soll sie nicht verstellen.
        hosting.sizingOptions = []
        // Inhalt nur im sichtbaren Teil, ueber dem Streifen unter dem Rand.
        hosting.frame = NSRect(x: 0, y: Self.cornerRadius, width: Self.size.width, height: Self.size.height)
        let content = NSView(frame: container.bounds)
        content.addSubview(hosting)

        // Natives Liquid Glass von macOS 26.
        let glass = NSGlassEffectView(frame: container.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.cornerRadius = Self.cornerRadius
        glass.contentView = content

        container.wantsLayer = true
        container.addSubview(glass)
        panel.contentView = container
        return panel
    }

    // Klick daneben schliesst den Launcher.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// Bewegung beim Oeffnen und Schliessen.
///
/// Das Panel waechst aus der Dock-Position heraus (etwas kleiner und tiefer,
/// skaliert um die Mitte der Unterkante) und geht denselben Weg zurueck.
/// Federn statt fester Dauer, kritisch gedaempft wie bei Apple: schnell los,
/// weich auslaufen, kein Nachwippen (das gehoert zu Wisch-Gesten, nicht zu
/// einem Tastendruck).
///
/// Erste Fassung (28 pt, nur Verschieben) war zu zaghaft - kaum
/// wahrnehmbar. Deshalb jetzt deutlicher.
@MainActor
private enum Motion {
    static let key = "launcher.motion"
    /// Federantwort in Sekunden (Apples "response"): wie schnell das Ziel
    /// erreicht wird. Oeffnen etwas ruhiger, Schliessen knapper.
    static let openResponse: CGFloat = 0.42
    static let closeResponse: CGFloat = 0.28
    /// Das Einblenden ist kuerzer als die Feder, damit das Glas sofort da ist.
    static let fadeIn: TimeInterval = 0.16
    static let fadeOut: TimeInterval = 0.14
    /// Zu-Zustand: um `travel` Punkte tiefer und auf `closedScale` verkleinert.
    static let travel: CGFloat = 40
    static let closedScale: CGFloat = 0.92
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)

    /// Zu-Zustand der sublayerTransform. Bei "Bewegung reduzieren" die
    /// Identitaet, dann bleibt nur die Blende.
    ///
    /// Die sublayerTransform dreht um den anchorPoint des Layers. Offline
    /// gemessen: bei View-Layern ist der (0,0), also unten links, und y zeigt
    /// nach oben. Damit das Panel aus dem Dock waechst statt aus der Ecke,
    /// wird der Drehpunkt auf die Mitte der Unterkante verlegt: dorthin
    /// schieben, skalieren, zurueckschieben, dann nach unten versetzen.
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

/// Randloses, durchsichtiges Panel, das Tastatureingaben annimmt, ohne die
/// App in den Vordergrund zu holen (wie Spotlight).
final class LauncherPanel: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // Kein Fensterschatten: den berechnet macOS aus der Fensterform, und
        // weil das Glas vom Fenstermanager selbst gerendert wird, entstand
        // ein fast eckiger zweiter Rahmen um das runde Glas. Kante und Tiefe
        // bringt NSGlassEffectView selbst mit.
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        // Eigene Animation in LauncherController, keine vom System dazu.
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Darf unter den Bildschirmrand ragen (die unteren Glasecken).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
