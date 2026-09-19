import AppKit
import ApolloShellCore
import SwiftUI

// Die Fenster des globalen Bearbeitungsmodus (design/2026-09-18-bento-
// dashboard.md Abschnitt 4, design/2026-09-19-shell-edit-plan.md Task 3):
// Scrim ueber jedem Bildschirm, eine schwebende Werkzeugleiste und eine
// schwebende Galerie auf dem Bildschirm, auf dem der Modus begann. Dashboard
// und Kontrollzentrum bleiben eigene Kantenfenster (`Dashboard`,
// `UtilitiesPanel`) und pinnen sich ueber `ShellEditor.addBeginHandler`.

/// Ebenen der Modus-Fenster relativ zu den angepinnten Kantenfenstern
/// (`EdgeDrawer` nutzt `.popUpMenu`, mit eigenem Scrim `.popUpMenu + 1` -
/// nur das Sitzungsmenue hat einen). Der Scrim des Modus liegt knapp
/// darunter, damit er Dashboard und Kontrollzentrum nicht abdunkelt;
/// Werkzeugleiste und Galerie liegen darueber, damit sie ueber allem stehen.
enum EditModeLevel {
    static let scrim = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
    static let controls = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
}

/// Grundlage jedes Fensters des Bearbeitungsmodus: randlos, nicht
/// aktivierend, auf allen Spaces, nicht im Fenstermenue, mit einer
/// Nicht-Standard-Bedienungshilfen-Subrolle - so lassen Fenstermanager wie
/// AeroSpace, yabai oder Amethyst es unberuehrt (sie kacheln, verschieben
/// oder verstecken es nicht), siehe Abschnitt "Robustheit" der Spec und
/// Task 6 (Debug-Log der tatsaechlichen Werte).
class EditModePanel: ShellPanel {
    init(size: NSSize = .zero, level: NSWindow.Level, takesKeyboard: Bool = false) {
        super.init(
            size: size, level: level,
            // Auf jedem Space, auch im Vollbild einer anderen App auf einem
            // zweiten Bildschirm; `stationary` haelt es beim Wechsel des
            // Space unter dem Zeiger stehen statt mitzuwandern;
            // `ignoresCycle` nimmt es aus Cmd+Tab/Cmd+`.
            behavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle],
            takesKeyboard: takesKeyboard, mayLeaveScreen: true
        )
        // "Schwebendes Fenster" statt normales Dokumentfenster: die eigene
        // Kategorie von Werkzeugpaletten, die die meisten Fenstermanager von
        // ihrer Fensterverwaltung ausnehmen.
        isFloatingPanel = true
        // Keine Werkzeugpalette im Fenstermenue - dort sollen nur Dokumente
        // der Nutzer-Apps stehen, nicht die eigene Bearbeitungsflaeche.
        isExcludedFromWindowsMenu = true
        // Nicht-Standard-Subrolle: Skripte/Erweiterungen, die per
        // Bedienungshilfen nach "normalen" Fenstern suchen (viele
        // Fenstermanager tun das), uebergehen es damit zusaetzlich zu Ebene
        // und `collectionBehavior`.
        setAccessibilitySubrole(.unknown)
    }
}

/// Baut ein Glas-Panel mit SwiftUI-Inhalt, mittig ueber einem Punkt auf dem
/// Bildschirm platziert, und blendet es ein/aus. Gemeinsamer Code fuer
/// Werkzeugleiste und Galerie - beide sind reine Inhalts-Panels ohne Kante,
/// anders als `EdgeDrawer` (der klebt an einer Bildschirmkante und hat einen
/// Radius-Ueberhang).
@MainActor
final class FloatingGlassPanel<Content: View> {
    private let panel: EditModePanel
    private let glass: NSGlassEffectView
    private let hosting: NSHostingView<AnyView>
    private var panelLayer: CAGradientLayer?

    init(cornerRadius: CGFloat, takesKeyboard: Bool, level: NSWindow.Level, @ViewBuilder content: @escaping () -> Content) {
        panel = EditModePanel(level: level, takesKeyboard: takesKeyboard)
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        let hosting = NSHostingView(rootView: AnyView(content().shellTheme()))
        hosting.sizingOptions = [.intrinsicContentSize]
        glass.contentView = hosting
        panel.contentView = glass
        self.glass = glass
        self.hosting = hosting
        panelLayer = ThemedGlass.apply(to: glass, fallbackRadius: cornerRadius)
    }

    /// Zeigt das Panel mittig ueber `point` auf `screen` (Fenster-Koordinaten,
    /// y nach oben), nach oben verschoben um `raise` (die Werkzeugleiste
    /// weicht so dem Kontrollzentrum-Panel aus).
    func show(on screen: NSScreen, centeredAt point: NSPoint, raise: CGFloat = 0) {
        panelLayer = ThemedGlass.apply(to: glass, fallbackRadius: panel.contentView == nil ? 0 : glass.cornerRadius, previous: panelLayer)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2 + raise))
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionCurve.spatialDuration
            context.timingFunction = .shellSpatial
            panel.animator().alphaValue = 1
        }
    }

    /// Erneut messen und platzieren, wenn sich der Inhalt geaendert hat
    /// (Galerie-Reiter gewechselt, Werkzeugleiste soll dem Kontrollzentrum
    /// ausweichen) - ohne Ein-/Ausblenden.
    func reposition(on screen: NSScreen, centeredAt point: NSPoint, raise: CGFloat = 0) {
        guard panel.isVisible else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2 + raise))
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = MotionCurve.spatialDuration
            context.timingFunction = .shellSpatial
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    var isVisible: Bool { panel.isVisible }
}

/// Abdunkelung eines einzelnen Bildschirms waehrend der Bearbeitung: knapp
/// 35% Schwarz vor leichter Weichzeichnung (`.hudWindow`, dunkel und dezent
/// wie macOS' eigene HUD-Paletten). Ein Klick waehlt nur ab - anders als
/// `ScrimWindow` (Kantenfenster) beendet er den Modus nie, siehe Abschnitt 4:
/// "clicks on the scrim only clear the selection".
final class EditModeScrimView: NSView {
    var onClick: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let effect = NSVisualEffectView(frame: bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        addSubview(effect)
        let dim = NSView(frame: bounds)
        dim.autoresizingMask = [.width, .height]
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        addSubview(dim)
    }

    required init?(coder: NSCoder) { fatalError("nicht benutzt") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }
}

@MainActor
final class EditModeScrimPanel {
    private let panel: EditModePanel
    private let view: EditModeScrimView

    var onClick: () -> Void {
        get { view.onClick }
        set { view.onClick = newValue }
    }

    init() {
        panel = EditModePanel(level: EditModeLevel.scrim)
        view = EditModeScrimView(frame: .zero)
        panel.contentView = view
    }

    func show(on screen: NSScreen) {
        panel.setFrame(screen.frame, display: true)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionCurve.spatialDuration
            context.timingFunction = .shellSpatial
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = MotionCurve.spatialDuration
            context.timingFunction = .shellSpatial
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}

/// Haelt fuer jeden Bildschirm ein `EditModeScrimPanel`, eine Werkzeugleiste
/// und eine Galerie auf dem Bildschirm, auf dem der Modus begann. Meldet sich
/// bei `ShellEditor` an (`addBeginHandler`/`addEndHandler`) und beobachtet
/// `editor.galleryVisible`, um die Galerie ohne eigenen Rueckruf zu zeigen
/// oder zu verstecken.
@MainActor
final class EditModeWindows {
    private let editor: ShellEditor
    private var scrims: [ObjectIdentifier: EditModeScrimPanel] = [:]
    private var toolbar: FloatingGlassPanel<EditToolbarView>?
    private var gallery: FloatingGlassPanel<EditGalleryView>?
    private var editScreen: NSScreen?
    /// Hoehe des Kontrollzentrum-Panels auf dem Bearbeitungs-Bildschirm - die
    /// Werkzeugleiste weicht ihm nach oben aus (Task 3: "never overlapping").
    var utilitiesPanelHeight: () -> CGFloat = { 0 }
    private var galleryObservation: Task<Void, Never>?

    init(editor: ShellEditor) {
        self.editor = editor
        editor.addBeginHandler { [weak self] screen in self?.begin(on: screen) }
        editor.addEndHandler { [weak self] in self?.end() }
    }

    private func begin(on screen: NSScreen) {
        editScreen = screen
        for candidate in NSScreen.screens {
            let scrim = scrims[ObjectIdentifier(candidate)] ?? {
                let panel = EditModeScrimPanel()
                panel.onClick = { [weak self] in self?.editor.dashboard.selectedWidgetID = nil }
                scrims[ObjectIdentifier(candidate)] = panel
                return panel
            }()
            scrim.show(on: candidate)
        }
        let toolbar = self.toolbar ?? {
            let panel = FloatingGlassPanel(cornerRadius: 26, takesKeyboard: false, level: EditModeLevel.controls) {
                EditToolbarView(editor: self.editor)
            }
            self.toolbar = panel
            return panel
        }()
        let gallery = self.gallery ?? {
            let panel = FloatingGlassPanel(cornerRadius: 22, takesKeyboard: false, level: EditModeLevel.controls) {
                EditGalleryView(editor: self.editor)
            }
            self.gallery = panel
            return panel
        }()
        placeToolbar(toolbar, on: screen)
        placeGallery(gallery, on: screen)
        if editor.galleryVisible { gallery.show(on: screen, centeredAt: galleryCenter(on: screen)) }
        observeGallery()
    }

    private func end() {
        for scrim in scrims.values { scrim.hide() }
        toolbar?.hide()
        gallery?.hide()
        galleryObservation?.cancel()
        galleryObservation = nil
        editScreen = nil
    }

    /// Reagiert auf `editor.galleryVisible` (Werkzeugleiste, Task 4-Popover-
    /// Esc), ohne dass jeder Aufrufer die Fenster selbst kennen muss.
    private func observeGallery() {
        galleryObservation?.cancel()
        galleryObservation = Task { [weak self] in
            guard let self else { return }
            for await visible in Observations({ self.editor.galleryVisible }) {
                guard let screen = self.editScreen, let gallery = self.gallery else { continue }
                if visible {
                    gallery.show(on: screen, centeredAt: self.galleryCenter(on: screen))
                } else {
                    gallery.hide()
                }
            }
        }
    }

    /// Vom Kontrollzentrum-Panel (`UtilitiesPanel.onHeightChange`): waechst
    /// oder schrumpft es waehrend der Bearbeitung (Karte aus/an, Knopf
    /// hinzu/weg), weicht die Werkzeugleiste sofort neu aus statt erst beim
    /// naechsten Bildschirmwechsel.
    func utilitiesHeightChanged() {
        guard editor.isEditing, let screen = editScreen, let toolbar else { return }
        let raise = utilitiesPanelHeight() + 24
        let point = NSPoint(x: screen.frame.midX, y: screen.frame.minY + 48)
        toolbar.reposition(on: screen, centeredAt: point, raise: raise)
    }

    private func placeToolbar(_ toolbar: FloatingGlassPanel<EditToolbarView>, on screen: NSScreen) {
        // Unten mittig, um `utilitiesPanelHeight()` plus etwas Luft nach
        // oben verschoben, damit sie nie ueber dem Kontrollzentrum-Panel
        // liegt (das sitzt unten rechts).
        let raise = utilitiesPanelHeight() + 24
        let point = NSPoint(x: screen.frame.midX, y: screen.frame.minY + 48)
        toolbar.show(on: screen, centeredAt: point, raise: raise)
    }

    /// Nur messen/platzieren, nicht einblenden - das uebernimmt
    /// `editor.galleryVisible` ueber `observeGallery()`.
    private func placeGallery(_ gallery: FloatingGlassPanel<EditGalleryView>, on screen: NSScreen) {
        gallery.reposition(on: screen, centeredAt: galleryCenter(on: screen))
    }

    private func galleryCenter(on screen: NSScreen) -> NSPoint {
        NSPoint(x: screen.frame.midX, y: screen.frame.midY)
    }
}
