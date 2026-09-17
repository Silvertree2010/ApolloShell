import AppKit
import ApolloShellCore
import QuartzCore
import SwiftUI
import os

/// Sitzungsmenue wie bei Caelestia (modules/session): der Bildschirm dunkelt
/// ab, rechts mittig gleitet ein Panel mit Abmelden / Ausschalten /
/// Emblem / Ruhezustand / Neustart aus der Kante. Optik Apple (Liquid
/// Glass, SF Symbols), Aufbau und Bewegung Caelestia - Werte aus dessen
/// Quellcode (Recherche 13.09.2026).
@MainActor
final class SessionMenu: NSObject, NSWindowDelegate {
    // Masse aus Caelestia: Knoepfe 80 px, Abstand 16, Innenabstand 16, zur
    // Kante hin nur 6 (padding - borderThickness), Rundung 25.
    static let buttonSize: CGFloat = 80
    static let spacing: CGFloat = 16
    static let padding: CGFloat = 16
    static let edgePadding: CGFloat = 6
    static let cornerRadius: CGFloat = 25
    /// Sichtbare Breite. Das Fenster ist um `cornerRadius` breiter und ragt
    /// damit rechts ueber den Bildschirm: so liegen die rechten Glasecken
    /// ausserhalb, und das Panel wirkt, als wuechse es aus der Kante.
    static let visibleWidth = padding + buttonSize + edgePadding
    /// Vier Knoepfe plus das Emblem im selben Raster.
    static let height = 2 * padding + 5 * buttonSize + 4 * spacing

    /// Abdunkelung, bewusst leicht (10-20 %), damit der Schreibtisch
    /// erkennbar bleibt; Caelestia selbst nimmt 50 %.
    static let dimAmount: CGFloat = 0.15

    // Bewegung aus Caelestia: Panel "DefaultSpatial" 500 ms mit leicht
    // ueberschiessender Kurve, Abdunkelung "SlowEffects" 300 ms.
    private static let slideDuration: TimeInterval = 0.5
    private static let slideCurve = CAMediaTimingFunction(controlPoints: 0.38, 1.21, 0.22, 1)
    private static let dimDuration: TimeInterval = 0.3
    private static let dimCurve = CAMediaTimingFunction(controlPoints: 0.34, 0.88, 0.34, 1)
    /// Wie weit das Panel geschlossen nach rechts versetzt ist (Caelestia:
    /// Breite + 5).
    private static var slideDistance: CGFloat { visibleWidth + 5 }

    private let model = SessionMenuModel()
    private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "session")
    private lazy var scrim = makeScrim()
    private lazy var panel = makePanel()
    private let container = NSView(frame: NSRect(
        x: 0, y: 0,
        width: SessionMenu.visibleWidth + SessionMenu.cornerRadius,
        height: SessionMenu.height
    ))
    private(set) var isOpen = false
    private var generation = 0

    override init() {
        super.init()
        model.onPerform = { [weak self] action in self?.perform(action) }
        model.onClose = { [weak self] in self?.close() }
    }

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        // Dort, wo der Zeiger steht: Panel und Abdunkelung auf demselben
        // Bildschirm.
        guard !isOpen, let screen = ShellScreens.underPointer() else { return }
        isOpen = true
        generation += 1
        model.reset()
        model.isVisible = true

        scrim.setFrame(screen.frame, display: false)
        panel.setFrame(panelFrame(on: screen), display: false)
        if !panel.isVisible {
            setSlide(closed: true, animated: false)
            panel.alphaValue = 0
            scrim.alphaValue = 0
        }

        scrim.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)

        setSlide(closed: false, animated: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.slideDuration
            context.timingFunction = Self.slideCurve
            panel.animator().alphaValue = 1
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.dimDuration
            context.timingFunction = Self.dimCurve
            scrim.animator().alphaValue = Self.dimAmount
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        generation += 1
        let current = generation

        setSlide(closed: true, animated: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.dimDuration
            context.timingFunction = Self.dimCurve
            scrim.animator().alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.slideDuration
            context.timingFunction = Self.slideCurve
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
                self.scrim.orderOut(nil)
                // Erst jetzt, damit das Emblem beim Wegfahren weiterlaeuft.
                self.model.isVisible = false
            }
        })
    }

    /// Erst das Menue wegfahren lassen, dann ausloesen - sonst friert der
    /// Ruhezustand ein halb offenes Panel ein.
    private func perform(_ action: SessionAction) {
        // Gedrueckt gehaltenes Enter oder ein zweiter Klick waehrend des
        // Wegfahrens: nur der erste Befehl zaehlt.
        guard isOpen else { return }
        log.notice("Sitzung: \(action.rawValue, privacy: .public)")
        close()
        let command = action.command
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dimDuration) { [log] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            do {
                try process.run()
            } catch {
                log.error("Sitzungsbefehl fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Bewegung

    /// Waagrechte Verschiebung ueber die sublayerTransform (GPU, wie beim
    /// Launcher). Startet beim sichtbaren Wert, damit ein Umdrehen mitten in
    /// der Bewegung nicht springt.
    private func setSlide(closed: Bool, animated: Bool) {
        guard let layer = container.layer else { return }
        let target = closed
            ? CATransform3DMakeTranslation(Self.slideDistance, 0, 0)
            : CATransform3DIdentity
        let current = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = target
        CATransaction.commit()

        guard animated else {
            layer.removeAnimation(forKey: "session.slide")
            return
        }
        let animation = CABasicAnimation(keyPath: "sublayerTransform")
        animation.fromValue = NSValue(caTransform3D: current)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = Self.slideDuration
        animation.timingFunction = Self.slideCurve
        layer.add(animation, forKey: "session.slide")
    }

    // MARK: - Fenster

    /// Rechts mittig; ragt um die Rundung ueber den Bildschirmrand hinaus.
    private func panelFrame(on screen: ShellScreen) -> NSRect {
        let frame = screen.frame
        return NSRect(
            x: frame.maxX - Self.visibleWidth,
            y: frame.midY - Self.height / 2,
            width: Self.visibleWidth + Self.cornerRadius,
            height: Self.height
        )
    }

    private func makeScrim() -> ScrimWindow {
        let scrim = ScrimWindow()
        scrim.onClick = { [weak self] in self?.close() }
        return scrim
    }

    private func makePanel() -> SessionPanel {
        let panel = SessionPanel(size: container.frame.size)
        panel.delegate = self

        let hosting = NSHostingView(rootView: SessionMenuView(model: model).shellTheme())
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]

        let glass = NSGlassEffectView(frame: container.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.cornerRadius = Self.cornerRadius
        glass.contentView = hosting

        container.wantsLayer = true
        container.addSubview(glass)
        panel.contentView = container
        return panel
    }

    // Klick in eine andere App schliesst das Menue.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// Zustand der Knoepfe und des Emblems.
@MainActor
@Observable
final class SessionMenuModel {
    /// Tastatur-Auswahl (farbige Fuellung).
    private(set) var selection = SessionSelection()
    /// Knopf unter der Maus (nur Schimmer, keine Auswahl).
    private(set) var hovered: SessionAction?
    /// Laufende Reaktion des Emblems samt Startzeit.
    private(set) var emblem = EmblemTimeline(.idle, at: 0)
    /// Nur solange das Menue sichtbar ist, laeuft die Uhr des Emblems -
    /// geschlossen kostet es keine Rechenzeit.
    var isVisible = false
    /// Fester Zeitpunkt (timeIntervalSinceReferenceDate) fuer Bildproben;
    /// `nil` = echte Uhr.
    var fixedTime: TimeInterval?
    /// Zaehlt bei jedem Oeffnen hoch, damit die Ansicht den Tastaturfokus neu
    /// setzt (das Panel bleibt bestehen, onAppear laeuft nur einmal).
    private(set) var openCount = 0

    @ObservationIgnored var onPerform: (SessionAction) -> Void = { _ in }
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored private var emblemEnd: Task<Void, Never>?

    /// Menue geht auf: keine Auswahl, kein Hover, das Emblem begruesst.
    func reset() {
        selection = SessionSelection()
        hovered = nil
        emblem = EmblemTimeline(.greet, at: now)
        scheduleEmblemEnd()
        openCount += 1
    }

    /// Maus rein/raus. Das Emblem reagiert auf den Knopf unter der Maus;
    /// geht sie weg, faellt es auf die Tastatur-Auswahl zurueck.
    func hover(_ action: SessionAction, inside: Bool) {
        if inside {
            hovered = action
        } else if hovered == action {
            hovered = nil
        } else {
            return
        }
        updateEmblem()
    }

    /// Worauf das Emblem gerade reagiert: Maus vor Tastatur; ohne beides
    /// auf nichts (dann ruht es).
    private var activeAction: SessionAction? {
        hovered ?? selection.action
    }

    private var now: TimeInterval { Date().timeIntervalSinceReferenceDate }

    /// Reagiert sofort auf Maus/Tastatur, ohne Verzoegerung; weich wird der
    /// Wechsel durch die Ueberblendung in SessionMenuView.
    private func updateEmblem() {
        showEmblem(EmblemReaction.reacting(to: activeAction))
    }

    private func showEmblem(_ reaction: EmblemReaction) {
        guard reaction != emblem.reaction else { return }
        emblem.show(reaction, at: now)
        scheduleEmblemEnd()
    }

    /// Einmal-Bewegungen (Begruessung, Abschied) gehen an ihrem Ende ohne
    /// Wartezeit in die Ruhe-Reaktion ueber: ein natuerliches Ende, kein
    /// hektischer Wechsel.
    private func scheduleEmblemEnd() {
        emblemEnd?.cancel()
        guard let duration = emblem.reaction.duration else { return }
        let reaction = emblem.reaction
        emblemEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, self.emblem.reaction == reaction else { return }
            self.showEmblem(EmblemReaction.resting(for: self.activeAction))
        }
    }

    func move(by delta: Int) {
        var next = selection
        next.move(by: delta)
        choose(next)
    }

    func select(_ action: SessionAction) {
        var next = selection
        next.select(action)
        choose(next)
    }

    /// Enter: nur mit Auswahl. Ohne Auswahl passiert nichts.
    func performSelected() {
        if let action = selection.action { onPerform(action) }
    }

    func perform(_ action: SessionAction) {
        select(action)
        onPerform(action)
    }

    /// Die Zuordnung Knopf -> Reaktion steht in `EmblemReaction`
    /// (ApolloShellCore, getestet).
    private func choose(_ next: SessionSelection) {
        guard next != selection else { return }
        selection = next
        updateEmblem()
    }
}

/// Vollbild-Abdunkelung. Liegt ueber Menueleiste und Dock, fing Klicks ab
/// und schliesst dann das Menue.
final class ScrimWindow: NSPanel {
    var onClick: () -> Void = {}

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        backgroundColor = .black
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = ClickView { [weak self] in self?.onClick() }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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

/// Panel ueber der Abdunkelung. Nimmt Tastatur an, ohne die App zu
/// aktivieren (wie der Launcher), und darf ueber den Bildschirmrand ragen.
final class SessionPanel: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// macOS schiebt Fenster sonst zurueck auf den Bildschirm; die rechten
    /// Ecken sollen aber draussen liegen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
