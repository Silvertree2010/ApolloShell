import AppKit
import ApolloShellCore
import QuartzCore
import SwiftUI
import os

/// The session menu as in Caelestia (modules/session): the screen dims, and on
/// the right in the middle a panel with log out / shut down / emblem / sleep /
/// restart glides out of the edge. The look is Apple (Liquid Glass, SF
/// Symbols), the build and the motion Caelestia - the values out of its source
/// (research 13.09.2026).
@MainActor
final class SessionMenu {
    // The measurements out of Caelestia: buttons 80 px, gap 16, inner padding
    // 16, towards the edge only 6 (padding - borderThickness), corner 25.
    static let buttonSize: CGFloat = 80
    static let spacing: CGFloat = 16
    static let padding: CGFloat = 16
    static let edgePadding: CGFloat = 6
    static let cornerRadius: CGFloat = 25
    /// The visible width. The window is `cornerRadius` wider and therefore
    /// sticks out over the screen on the right (`EdgeDrawer`).
    static let visibleWidth = padding + buttonSize + edgePadding
    /// Four buttons plus the emblem in the same grid.
    static let height = 2 * padding + 5 * buttonSize + 4 * spacing

    /// The dimming, deliberately light (10-20 %), so that the desktop stays
    /// recognisable; Caelestia itself takes 50 %. Plus Caelestia's
    /// "SlowEffects": 300 ms.
    private static let scrim = DrawerScrim(
        amount: 0.15, duration: 0.3, curve: CAMediaTimingFunction(controlPoints: 0.34, 0.88, 0.34, 1)
    )

    private let model = SessionMenuModel()
    private let log = Logger(category: "session")
    /// On the right in the middle, glides out of the edge like the other edge
    /// windows ("DefaultSpatial", 500 ms), in front of a dimmed screen.
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
        // Only now, so that the emblem goes on running while it leaves.
        drawer.onHidden = { [model] in model.isVisible = false }
        model.onPerform = { [weak self] action in self?.perform(action) }
        model.onClose = { [weak self] in self?.close() }
    }

    var isOpen: Bool { drawer.isOpen }

    func toggle() {
        drawer.toggle()
    }

    /// Where the pointer stands: the panel and the dimming on the same screen.
    ///
    func open() {
        drawer.open()
    }

    func close() {
        drawer.close()
    }

    /// Let the menu leave first, then set it off - otherwise sleep would
    /// freeze a half-open panel.
    private func perform(_ action: SessionAction) {
        // A held Enter or a second click while it leaves: only the first
        // command counts.
        guard isOpen else { return }
        log.notice("Sitzung: \(action.rawValue, privacy: .public)")
        close()
        let command = action.command
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrim.duration) {
            MainActor.assumeIsolated { _ = Subprocess.launch(command.executable, command.arguments) }
        }
    }
}

/// The state of the buttons and the emblem.
@MainActor
@Observable
final class SessionMenuModel {
    /// The keyboard selection (a colored fill).
    private(set) var selection = SessionSelection()
    /// The button under the mouse (only a shimmer, no selection).
    private(set) var hovered: SessionAction?
    /// The running reaction of the emblem together with its start time.
    private(set) var emblem = EmblemTimeline(.idle, at: 0)
    /// The clock of the emblem only runs while the menu is visible - closed it
    /// costs no computing time.
    var isVisible = false
    /// A fixed point in time (timeIntervalSinceReferenceDate) for image
    /// samples; `nil` = the real clock.
    var fixedTime: TimeInterval?
    /// Counts up on every opening, so that the view sets the keyboard focus
    /// anew (the panel stays, and onAppear runs only once).
    private(set) var openCount = 0

    @ObservationIgnored var onPerform: (SessionAction) -> Void = { _ in }
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored private var emblemEnd: Task<Void, Never>?

    /// The menu opens: no selection, no hover, and the emblem greets.
    func reset() {
        selection = SessionSelection()
        hovered = nil
        emblem = EmblemTimeline(.greet, at: now)
        scheduleEmblemEnd()
        openCount += 1
    }

    /// The mouse in and out. The emblem reacts to the button under the mouse;
    /// when it leaves, it falls back to the keyboard selection.
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

    /// What the emblem is reacting to right now: mouse before keyboard;
    /// without either, to nothing (then it rests).
    private var activeAction: SessionAction? {
        hovered ?? selection.action
    }

    private var now: TimeInterval { Date().timeIntervalSinceReferenceDate }

    /// Reacts to mouse and keyboard right away, without a delay; the switch is
    /// made soft by the cross-fade in SessionMenuView.
    private func updateEmblem() {
        showEmblem(EmblemReaction.reacting(to: activeAction))
    }

    private func showEmblem(_ reaction: EmblemReaction) {
        guard reaction != emblem.reaction else { return }
        emblem.show(reaction, at: now)
        scheduleEmblemEnd()
    }

    /// One-off motions (the greeting, the farewell) go over into the resting
    /// reaction at their end without a wait: a natural ending, not a hectic
    /// switch.
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

    /// Enter: only with a selection. Without one nothing happens.
    func performSelected() {
        if let action = selection.action { onPerform(action) }
    }

    func perform(_ action: SessionAction) {
        select(action)
        onPerform(action)
    }

    /// Which button maps to which reaction stands in `EmblemReaction`
    /// (ApolloShellCore, tested).
    private func choose(_ next: SessionSelection) {
        guard next != selection else { return }
        selection = next
        updateEmblem()
    }
}
