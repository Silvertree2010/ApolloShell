import AppKit
import ApolloShellCore
import os
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
        // ihrer Fensterverwaltung ausnehmen. AppKit setzt dabei selbst
        // `self.level = .floating` (gemessen 19.09.: Scrim/Werkzeugleiste/
        // Galerie landeten dadurch unter Menueleiste, Dock und den
        // angepinnten Kantenfenstern) - die gewuenschte Ebene darum danach
        // noch einmal setzen.
        isFloatingPanel = true
        self.level = level
        // Keine Werkzeugpalette im Fenstermenue - dort sollen nur Dokumente
        // der Nutzer-Apps stehen, nicht die eigene Bearbeitungsflaeche.
        isExcludedFromWindowsMenu = true
        // Nicht-Standard-Subrolle: Skripte/Erweiterungen, die per
        // Bedienungshilfen nach "normalen" Fenstern suchen (viele
        // Fenstermanager tun das), uebergehen es damit zusaetzlich zu Ebene
        // und `collectionBehavior`.
        setAccessibilitySubrole(.unknown)
        Self.logCreation(level: self.level, behavior: collectionBehavior, subrole: accessibilitySubrole())
    }

    /// Task 6: fuer den Live-Test mit AeroSpace/yabai/Amethyst - die
    /// tatsaechlichen Werte, nicht nur die Absicht im Code. Nur DEBUG, nicht
    /// mitausgeliefertes Verhalten (nur ein Log-Eintrag, `Logger` faellt in
    /// Release-Bauten ohnehin weg). `level` ist hier immer `self.level` nach
    /// `isFloatingPanel`, nie der Parameter aus `init` - sonst haette das Log
    /// den fehlerhaften Stand vor der Korrektur oben gezeigt.
    #if DEBUG
    private static let log = Logger(category: "edit-mode-windows")
    private static func logCreation(level: NSWindow.Level, behavior: NSWindow.CollectionBehavior, subrole: NSAccessibility.Subrole?) {
        log.debug("Fenster des Bearbeitungsmodus: Ebene \(level.rawValue, privacy: .public), Verhalten \(behavior.rawValue, privacy: .public), Subrolle \(subrole?.rawValue ?? "-", privacy: .public)")
    }
    #else
    private static func logCreation(level: NSWindow.Level, behavior: NSWindow.CollectionBehavior, subrole: NSAccessibility.Subrole?) {}
    #endif
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
    private let hosting: FirstMouseHostingView<AnyView>
    private var panelLayer: CAGradientLayer?
    /// Wie `EdgeDrawer.generation`: ein schnelles Aus-dann-wieder-Ein (Modus
    /// verlassen, sofort neu begonnen) darf das verspaetete `orderOut` des
    /// alten `hide()` nicht mehr treffen - sonst verschwindet das gerade neu
    /// gezeigte Panel wieder, sobald die alte Ausblend-Animation fertig wird.
    private var generation = 0

    init(cornerRadius: CGFloat, takesKeyboard: Bool, level: NSWindow.Level, @ViewBuilder content: @escaping () -> Content) {
        panel = EditModePanel(level: level, takesKeyboard: takesKeyboard)
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        // `FirstMouseHostingView` wie Leiste, Toasts und Kantenfenster: das
        // Panel wird nie Schluesselfenster (`takesKeyboard: false`), und ein
        // normales `NSHostingView` verschluckt dann den ersten Klick - bei
        // einem Fenster, das nie Schluessel wird, praktisch jeden. Knoepfe
        // der Werkzeugleiste und das Ziehen aus der Galerie reagierten sonst
        // nicht (Live-Test 19.09.).
        let hosting = FirstMouseHostingView(rootView: AnyView(content().shellTheme()))
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
        generation += 1
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
        generation += 1
        let current = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = MotionCurve.spatialDuration
            context.timingFunction = .shellSpatial
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, panel] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                panel.orderOut(nil)
            }
        })
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }
    var level: Int { panel.level.rawValue }

    /// Gemessene Groesse des Inhalts (fuer das Platzieren vor dem Zeigen).
    var size: NSSize {
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }
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
    /// Siehe `FloatingGlassPanel.generation`.
    private var generation = 0

    var onClick: () -> Void {
        get { view.onClick }
        set { view.onClick = newValue }
    }

    init() {
        panel = EditModePanel(level: EditModeLevel.scrim)
        view = EditModeScrimView(frame: .zero)
        panel.contentView = view
    }

    var isVisible: Bool { panel.isVisible }
    var level: Int { panel.level.rawValue }

    func show(on screen: NSScreen) {
        generation += 1
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
        generation += 1
        let current = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = MotionCurve.spatialDuration
            context.timingFunction = .shellSpatial
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, panel] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                panel.orderOut(nil)
            }
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
    /// Rahmen der angepinnten Panels auf dem Bearbeitungs-Bildschirm (`nil`,
    /// solange zu). Werkzeugleiste und Galerie richten sich danach: die
    /// Galerie unter dem Dashboard statt mitten darueber, die Werkzeugleiste
    /// ueber dem Kontrollzentrum nur, wenn sie es waagrecht wirklich
    /// ueberdecken wuerde. Vorher: Galerie immer in der Bildschirmmitte (auf
    /// 14 Zoll ueber dem unteren Drittel des Dashboards) und Werkzeugleiste
    /// immer um die ganze Panelhoehe hoch (bis an das Dashboard heran),
    /// obwohl das Kontrollzentrum rechts sitzt.
    var dashboardFrame: () -> NSRect? = { nil }
    var utilitiesFrame: () -> NSRect? = { nil }
    private var galleryObservation: Task<Void, Never>?
    /// Werkzeugleiste ("Änderungen verwerfen?" statt der drei Knoepfe) und
    /// Galerie (Hinweis "Kein Platz auf dieser Seite") aendern ihre Groesse,
    /// ohne ein-/auszublenden - ohne eigene Neuvermessung blieb der Text
    /// abgeschnitten (gemessen 19.09.).
    private var toolbarSizeObservation: Task<Void, Never>?
    private var galleryNoticeObservation: Task<Void, Never>?

    init(editor: ShellEditor) {
        self.editor = editor
        editor.addBeginHandler { [weak self] screen in self?.begin(on: screen) }
        editor.addEndHandler { [weak self] in self?.end() }
    }

    /// Task 6: die vorgesehene Reihenfolge der Ebenen als DEBUG-Pruefung, nicht
    /// nur als Kommentar - normale Fenster < Seitenleiste (`.floating`) <
    /// Scrim < angepinnte Kantenfenster (`EdgeDrawer`, `.popUpMenu`/+1) <
    /// Werkzeugleiste/Galerie, und der Scrim ueber Menueleiste und Dock.
    /// Bricht in Debug-Bauten sofort, statt das erst im Live-Test mit
    /// AeroSpace/yabai/Amethyst zu bemerken.
    #if DEBUG
    private static let stackingLog = Logger(category: "edit-mode-windows")
    private static func assertStackingOrder() {
        assert(EditModeLevel.scrim.rawValue > NSWindow.Level.mainMenu.rawValue,
               "Scrim muss ueber Menueleiste und Dock liegen")
        assert(EditModeLevel.scrim.rawValue < NSWindow.Level.popUpMenu.rawValue,
               "Scrim muss unter den angepinnten Kantenfenstern liegen")
        assert(EditModeLevel.controls.rawValue > NSWindow.Level.popUpMenu.rawValue + 1,
               "Werkzeugleiste/Galerie muessen ueber den angepinnten Kantenfenstern liegen")
        stackingLog.debug("""
            Ebenen des Bearbeitungsmodus: Seitenleiste \(NSWindow.Level.floating.rawValue, privacy: .public), \
            Scrim \(EditModeLevel.scrim.rawValue, privacy: .public), \
            Kantenfenster \(NSWindow.Level.popUpMenu.rawValue, privacy: .public)/+1, \
            Werkzeugleiste/Galerie \(EditModeLevel.controls.rawValue, privacy: .public)
            """)
    }
    #else
    private static func assertStackingOrder() {}
    #endif

    private func begin(on screen: NSScreen) {
        Self.assertStackingOrder()
        editScreen = screen
        for candidate in NSScreen.screens {
            let scrim = scrims[ObjectIdentifier(candidate)] ?? {
                let panel = EditModeScrimPanel()
                panel.onClick = { [weak self] in
                    // Klick daneben: jede Auswahl (und damit jedes offene
                    // Optionen-Popover) weg, in beiden Panels.
                    self?.editor.dashboard.selectedWidgetID = nil
                    self?.editor.selectedToggleID = nil
                    self?.editor.dashboard.renamingPageID = nil
                }
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
        // Die Hoerer von Dashboard und Kontrollzentrum laufen im selben
        // `begin` - je nach Reihenfolge erst nach diesem hier. Ihre Rahmen
        // stehen nach dem Oeffnen sofort fest (die Bewegung ist nur eine
        // Ebenen-Verschiebung), also einen Umlauf spaeter neu platzieren.
        DispatchQueue.main.async { [weak self] in
            self?.repositionToolbar()
            self?.repositionGallery()
        }
        if editor.galleryVisible { gallery.show(on: screen, centeredAt: galleryCenter(on: screen)) }
        observeGallery()
        observeToolbarSize()
        observeGalleryNotice()
    }

    private func end() {
        for scrim in scrims.values { scrim.hide() }
        toolbar?.hide()
        gallery?.hide()
        galleryObservation?.cancel()
        galleryObservation = nil
        toolbarSizeObservation?.cancel()
        toolbarSizeObservation = nil
        galleryNoticeObservation?.cancel()
        galleryNoticeObservation = nil
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

    /// Werkzeugleiste neu vermessen, sobald `editor.pendingCancelConfirmation`
    /// kippt (Task 6: "Änderungen verwerfen?" statt der drei Knoepfe ist
    /// breiter/anders hoch).
    private func observeToolbarSize() {
        toolbarSizeObservation?.cancel()
        toolbarSizeObservation = Task { [weak self] in
            guard let self else { return }
            for await _ in Observations({ self.editor.pendingCancelConfirmation }) {
                self.repositionToolbar()
            }
        }
    }

    /// Galerie neu vermessen, sobald `editor.galleryNotice` erscheint oder
    /// verschwindet (Task 3: der Hinweis "Kein Platz auf dieser Seite"
    /// braucht mehr Hoehe als das Raster allein).
    private func observeGalleryNotice() {
        galleryNoticeObservation?.cancel()
        galleryNoticeObservation = Task { [weak self] in
            guard let self else { return }
            for await _ in Observations({ self.editor.galleryNotice }) {
                self.repositionGallery()
            }
        }
    }

    private func repositionToolbar() {
        guard let screen = editScreen, let toolbar else { return }
        toolbar.reposition(on: screen, centeredAt: toolbarCenter(on: screen, size: toolbar.size))
    }

    private func repositionGallery() {
        guard let screen = editScreen, let gallery else { return }
        gallery.reposition(on: screen, centeredAt: galleryCenter(on: screen))
    }

    /// Unten mittig; ueberdeckt das Kontrollzentrum sie dort (schmaler
    /// Bildschirm), dann knapp ueber dessen Oberkante.
    private func toolbarCenter(on screen: NSScreen, size: NSSize) -> NSPoint {
        let bottom = screen.visibleFrame.minY + 20
        var center = NSPoint(x: screen.frame.midX, y: bottom + size.height / 2)
        let rect = NSRect(x: center.x - size.width / 2, y: bottom, width: size.width, height: size.height)
        if let utilities = utilitiesFrame(), utilities.intersects(rect.insetBy(dx: -8, dy: -8)) {
            center.y = utilities.maxY + 16 + size.height / 2
        }
        return center
    }

    /// Vom Kontrollzentrum-Panel (`UtilitiesPanel.onHeightChange`): waechst
    /// oder schrumpft es waehrend der Bearbeitung (Karte aus/an, Knopf
    /// hinzu/weg), weicht die Werkzeugleiste sofort neu aus statt erst beim
    /// naechsten Bildschirmwechsel.
    func utilitiesHeightChanged() {
        guard editor.isEditing else { return }
        repositionToolbar()
    }

    private func placeToolbar(_ toolbar: FloatingGlassPanel<EditToolbarView>, on screen: NSScreen) {
        toolbar.show(on: screen, centeredAt: toolbarCenter(on: screen, size: toolbar.size))
    }

    /// Nur messen/platzieren, nicht einblenden - das uebernimmt
    /// `editor.galleryVisible` ueber `observeGallery()`.
    private func placeGallery(_ gallery: FloatingGlassPanel<EditGalleryView>, on screen: NSScreen) {
        gallery.reposition(on: screen, centeredAt: galleryCenter(on: screen))
    }

    /// Mittig zwischen Unterkante des Dashboards und Werkzeugleiste; ohne
    /// offenes Dashboard in der Bildschirmmitte. Passt sie dort nicht ganz
    /// hin (kleiner Bildschirm), bleibt sie wenigstens unter dem Dashboard.
    #if DEBUG
    /// Fuer `EditModeSelfTest`: was gerade wirklich auf dem Bildschirm steht.
    var debugVisibleScrims: Int { scrims.values.filter(\.isVisible).count }
    var debugToolbarFrame: NSRect? { toolbar.flatMap { $0.isVisible ? $0.frame : nil } }
    var debugGalleryFrame: NSRect? { gallery.flatMap { $0.isVisible ? $0.frame : nil } }
    var debugLevels: (scrim: Int, controls: Int) { (EditModeLevel.scrim.rawValue, EditModeLevel.controls.rawValue) }
    var debugPanelLevels: [Int] {
        scrims.values.map(\.level) + [toolbar?.level, gallery?.level].compactMap { $0 }
    }
    #endif

    private func galleryCenter(on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        guard let dashboard = dashboardFrame(), dashboard.intersects(screen.frame) else {
            return NSPoint(x: visible.midX, y: visible.midY)
        }
        let top = min(dashboard.minY, visible.maxY) - 16
        let bottom = visible.minY + 20 + (toolbar?.size.height ?? 56) + 16
        let height = gallery?.size.height ?? 380
        let centerY = top - height / 2 >= bottom + height / 2 ? (top + bottom) / 2 : top - height / 2
        return NSPoint(x: visible.midX, y: centerY)
    }
}
