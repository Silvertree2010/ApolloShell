import AppKit
import ApolloShellCore
import SwiftUI

/// Das Fenster fuer den Stapel der Kurzmeldungen, unten rechts 12 vom Rand
/// (Caelestia: Toasts in modules/drawers/Panels.qml, `anchors.margins:
/// padding.medium`). Ist das Utilities-Panel offen, sitzt der Stapel 12
/// darueber und gleitet mit ihm (Caelestia haengt ihn an `utilities.top`).
///
/// Warum ein festes, hohes Fenster statt eines, das mit dem Stapel waechst:
/// Alle Bewegungen (Einblenden, Nachruecken, Ausweichen vor dem Panel)
/// laufen so in SwiftUI auf Caelestias Kurven. Ein Fenster mitwachsen zu
/// lassen hiesse, Fensterrahmen und Inhalt im selben Bild zu verschieben -
/// das ruckelt, und ausblendende Meldungen wuerden abgeschnitten.
///
/// Damit das Fenster trotzdem nichts blockiert, laesst es Mausereignisse
/// durch (`ignoresMouseEvents`) und nimmt sie nur, solange der Zeiger ueber
/// einer Meldung liegt. Das prueft ein Timer mit 30 Hz, und nur solange
/// Meldungen da sind (hoechstens ein paar Sekunden). Nie Fokus: Panel, das
/// kein Schluesselfenster werden kann und die App nicht aktiviert.
@MainActor
final class ToastWindow {
    /// Rand um den Stapel im Fenster: Platz fuer das Ueberschiessen der
    /// Einblendkurve (gerechnet: hoechstens 1.4 % Groesse, ~3 pt bei 406).
    static let overscan: CGFloat = 8
    /// Nach der letzten Meldung noch so lange da, bis die Ausblendung
    /// (500 ms) fertig ist.
    private static let hideDelay: TimeInterval = 0.6
    private static let pollInterval: TimeInterval = 1.0 / 30

    private let toaster: Toaster
    private let panel = ToastPanel()
    private var pollTimer: Timer?
    private var hideTimer: Timer?
    private var utilitiesOpen = false
    /// Auf welchem Bildschirm der Stapel steht. Festgelegt, wenn die erste
    /// Meldung aufgeht - er wandert danach nicht mit dem Zeiger, sonst
    /// spraenge er beim Lesen davon.
    private var currentScreen: ShellScreen?

    /// Sichtbare Hoehe des Utilities-Panels - so hoch muss das Fenster
    /// zusaetzlich sein, damit der Stapel darueber passt. Folgt dem Panel,
    /// wenn in Nexus Karten oder Reihen dazukommen oder wegfallen: offen
    /// gleitet der Stapel mit (`lift`), und ein sichtbares Fenster waechst
    /// nach oben - der Stapel klebt unten, springt also nicht.
    var utilitiesHeight: CGFloat {
        didSet {
            guard utilitiesHeight != oldValue else { return }
            if utilitiesOpen { toaster.lift = utilitiesHeight }
            if panel.isVisible, let screen = currentScreen {
                panel.setFrame(frame(on: screen), display: true)
            }
        }
    }

    init(toaster: Toaster, utilitiesHeight: CGFloat) {
        self.toaster = toaster
        self.utilitiesHeight = utilitiesHeight
        let hosting = FirstMouseHostingView(rootView: ToastStackView(toaster: toaster, overscan: Self.overscan))
        hosting.sizingOptions = []
        panel.contentView = hosting
        toaster.onChange = { [weak self] in self?.update() }
    }

    /// Das Utilities-Panel geht auf oder zu.
    func utilitiesChanged(open: Bool) {
        utilitiesOpen = open
        toaster.lift = open ? utilitiesHeight : 0
    }

    private func update() {
        if toaster.visible.isEmpty {
            // Erst weg, wenn die letzte fertig ausgeblendet ist.
            guard panel.isVisible, hideTimer == nil else { return }
            hideTimer = Timer.scheduledTimer(withTimeInterval: Self.hideDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
            return
        }
        hideTimer?.invalidate()
        hideTimer = nil
        // Geht der Stapel neu auf: dort, wo der Zeiger gerade steht.
        if !panel.isVisible, let screen = ShellScreens.underPointer() {
            currentScreen = screen
            panel.setFrame(frame(on: screen), display: false)
            panel.ignoresMouseEvents = true
        }
        // Jedes Mal nach vorne: ging das Utilities-Panel danach auf, liegt es
        // sonst auf gleicher Ebene darueber. Aktiviert die App nicht.
        panel.orderFrontRegardless()
        startPolling()
    }

    private func hide() {
        hideTimer = nil
        guard toaster.visible.isEmpty else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        // Der naechste Stapel sucht sich seinen Bildschirm neu.
        currentScreen = nil
    }

    // MARK: - Geometrie

    /// Rechts und unten 12 vom Bildschirmrand (wie das Utilities-Panel am
    /// ganzen Bildschirm, nicht am sichtbaren Bereich), hoch genug fuer 4
    /// Meldungen ueber dem offenen Panel.
    private func frame(on screen: ShellScreen) -> NSRect {
        let s = screen.frame
        let margin = CGFloat(ToastLayout.margin)
        let width = CGFloat(ToastLayout.width)
        let stack = CGFloat(ToastLayout.stackHeight(count: ToastQueue.maxVisible))
        return NSRect(
            x: s.maxX - margin - width - Self.overscan,
            y: s.minY + margin - Self.overscan,
            width: width + 2 * Self.overscan,
            height: utilitiesHeight + stack + 2 * Self.overscan
        )
    }

    /// Wo die sichtbaren Meldungen liegen, in Bildschirmkoordinaten. Die
    /// Luecken zwischen ihnen (8 pt) zaehlen mit - das ist verschmerzbar.
    private var hitRect: NSRect {
        let count = toaster.visible.count
        guard count > 0 else { return .zero }
        let f = panel.frame
        return NSRect(
            x: f.minX + Self.overscan,
            y: f.minY + Self.overscan + toaster.lift,
            width: CGFloat(ToastLayout.width),
            height: CGFloat(ToastLayout.stackHeight(count: count))
        )
    }

    // MARK: - Maus

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        poll()
    }

    /// Ueber einer Meldung: Klicks annehmen. Sonst durchlassen.
    private func poll() {
        let inside = hitRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
    }
}

/// Randloses Panel fuer die Kurzmeldungen: gleiche Ebene wie die
/// Kantenfenster, nie Schluesselfenster, kein Fensterschatten (sonst ein
/// zweiter Rahmen um das Glas). Ohne `.fullScreenAuxiliary`: in
/// Vollbild-Spaces bleibt es draussen, wie Caelestias Vorgabe "off".
final class ToastPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Darf ein paar Punkte ueber den Bildschirmrand ragen (Rand fuers
    /// Ueberschiessen).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
