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
final class SessionMenu {
    // Masse aus Caelestia: Knoepfe 80 px, Abstand 16, Innenabstand 16, zur
    // Kante hin nur 6 (padding - borderThickness), Rundung 25.
    static let buttonSize: CGFloat = 80
    static let spacing: CGFloat = 16
    static let padding: CGFloat = 16
    static let edgePadding: CGFloat = 6
    static let cornerRadius: CGFloat = 25
    /// Sichtbare Breite. Das Fenster ist um `cornerRadius` breiter und ragt
    /// damit rechts ueber den Bildschirm (`EdgeDrawer`).
    static let visibleWidth = padding + buttonSize + edgePadding
    /// Vier Knoepfe plus das Emblem im selben Raster.
    static let height = 2 * padding + 5 * buttonSize + 4 * spacing

    /// Abdunkelung, bewusst leicht (10-20 %), damit der Schreibtisch
    /// erkennbar bleibt; Caelestia selbst nimmt 50 %. Dazu Caelestias
    /// "SlowEffects": 300 ms.
    private static let scrim = DrawerScrim(
        amount: 0.15, duration: 0.3, curve: CAMediaTimingFunction(controlPoints: 0.34, 0.88, 0.34, 1)
    )

    private let model = SessionMenuModel()
    private let log = Logger(category: "session")
    /// Rechts mittig, gleitet wie die anderen Kantenfenster aus der Kante
    /// ("DefaultSpatial", 500 ms), vor abgedunkeltem Bildschirm.
    private let drawer: EdgeDrawer<SessionMenuView>

    init() {
        drawer = EdgeDrawer(
            edge: .right, size: NSSize(width: Self.visibleWidth, height: Self.height),
            cornerRadius: Self.cornerRadius, scrim: Self.scrim, rootView: SessionMenuView(model: model)
        )
        drawer.onOpen = { [model] in
            model.reset()
            model.isVisible = true
        }
        // Erst jetzt, damit das Emblem beim Wegfahren weiterlaeuft.
        drawer.onHidden = { [model] in model.isVisible = false }
        model.onPerform = { [weak self] action in self?.perform(action) }
        model.onClose = { [weak self] in self?.close() }
    }

    var isOpen: Bool { drawer.isOpen }

    func toggle() {
        drawer.toggle()
    }

    /// Dort, wo der Zeiger steht: Panel und Abdunkelung auf demselben
    /// Bildschirm.
    func open() {
        drawer.open()
    }

    func close() {
        drawer.close()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrim.duration) {
            MainActor.assumeIsolated { _ = Subprocess.launch(command.executable, command.arguments) }
        }
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
