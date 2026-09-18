import AppKit
import ApolloShellCore
import os
import SwiftUI

/// Die Leiste EINES Bildschirms: ihr Fenster, ihre Ansicht und ihr
/// Statuspopout. Die Modelle darin gehoeren dem Verwalter und sind geteilt.
@MainActor
final class SidebarScreen {
    private let panel = SidebarPanel()
    private let log = Logger(category: "sidebar")
    /// Detailfenster der Statuskapsel (WLAN, Bluetooth, Akku). Liegt im
    /// Fenster dieser Leiste und macht es breiter, solange es offen ist.
    private let popout = StatusPopout()
    /// Welcher Bildschirm das ist - wird bei jedem Umbau aufgefrischt.
    private(set) var info: ScreenInfo
    private var frame: NSRect
    private var visibleTop: CGFloat
    /// Letzter gueltiger Rahmen. Ohne ihn zeigt sich die Leiste nicht.
    private var lastFrame: NSRect?
    private var expanded = false
    /// Vordergrund-App ist auf DIESEM Bildschirm im Vollbild.
    private(set) var isHiddenForFullscreen = false
    /// Dieses Popout geht auf - der Verwalter schliesst die anderen.
    var onPopoutOpen: (ObjectIdentifier) -> Void = { _ in }

    init(screen: ShellScreen, settings: ShellSettingsStore, context: BarModuleContext) {
        info = screen.info
        frame = screen.frame
        visibleTop = screen.visibleFrame.maxY

        // Glas zeichnet SwiftUI (`SidebarRoot`), nicht NSGlassEffectView:
        // nur im selben GlassEffectContainer verschmilzt das Popout mit der
        // Leiste.
        let hosting = FirstMouseHostingView(
            rootView: SidebarRoot(settings: settings, context: context, popout: popout.model).shellTheme()
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
        popout.onOpen = { [weak self] in
            guard let self else { return }
            self.onPopoutOpen(ObjectIdentifier(self))
        }
        // SwiftUI meldet Symbolrahmen in Koordinaten der Ansicht (oben = 0,
        // NSHostingView ist geflippt); AppKit rechnet sie ueber das Fenster
        // auf den Bildschirm um.
        popout.screenRect = { [weak hosting] rect in
            guard let hosting, let window = hosting.window else { return nil }
            return window.convertToScreen(hosting.convert(rect, to: nil))
        }

        layout()
        showIfNeeded()
    }

    /// Derselbe Bildschirm, aber vielleicht mit neuen Massen oder an einer
    /// neuen Stelle.
    func update(screen: ShellScreen) {
        info = screen.info
        frame = screen.frame
        visibleTop = screen.visibleFrame.maxY
        layout()
        showIfNeeded()
    }

    /// Bildschirm weg oder abgewaehlt: Popout zu, Fenster weg.
    func tearDown() {
        popout.close()
        panel.orderOut(nil)
        lastFrame = nil
    }

    func closePopout() {
        popout.close()
    }

    /// Vollbild an: weg. Vollbild aus: wieder her. `.canJoinAllSpaces` holt
    /// das Panel sonst auch in Vollbild-Spaces (siehe `SidebarPanel`).
    ///
    /// Unsichtbar und klickdurchlaessig statt `orderOut`: Die Meldung "kein
    /// Vollbild mehr" kommt mitten in der Wisch-Animation zurueck zum
    /// Schreibtisch. Ein dann wieder eingeblendetes Panel hing gemessen nur
    /// noch an diesem einen Space und fehlte auf allen anderen. Bleibt es
    /// eingeblendet, behaelt es alle Spaces.
    func setHiddenForFullscreen(_ hidden: Bool) {
        guard hidden != isHiddenForFullscreen else { return }
        isHiddenForFullscreen = hidden
        log.notice("Sidebar \(hidden ? "weg (Vollbild)" : "wieder da", privacy: .public)")
        if hidden {
            // Ohne Leiste haette das Popout nichts, woran es haengt.
            popout.close()
        }
        panel.alphaValue = hidden ? 0 : 1
        panel.ignoresMouseEvents = hidden
        if !hidden { showIfNeeded() }
    }

    /// Nur nach vorne holen, wenn sie sichtbar sein soll und es gerade nicht
    /// ist. Ein bedingungsloses orderFrontRegardless bei jedem Space-Wechsel
    /// kann waehrend Mission Control flackern. (Die erste Fassung tat das,
    /// weil Overlay-Panels nach Space-Wechseln gelegentlich verloren gingen;
    /// geht sie trotz `isVisible` verloren, ist hier die Stelle dafuer.)
    private func showIfNeeded() {
        guard lastFrame != nil, !panel.isVisible else { return }
        panel.orderFrontRegardless()
    }

    /// Popout offen: Fenster breiter, die Leiste bleibt links 44 breit, der
    /// Rest ist durchsichtig, bis das Glas hineinwaechst.
    private func setExpanded(_ expanded: Bool) {
        guard expanded != self.expanded else { return }
        self.expanded = expanded
        layout()
    }

    /// Am linken Rand dieses Bildschirms: unten bis zum Rand, oben bis zur
    /// Unterkante der Menueleiste. Bildschirme ohne Menueleiste haben dort
    /// keinen Abzug, dann reicht die Leiste bis ganz nach oben.
    private func layout() {
        let width = expanded ? StatusPopout.expandedWidth : Sidebar.width
        let rect = NSRect(x: frame.minX, y: frame.minY, width: width, height: visibleTop - frame.minY)
        lastFrame = rect
        // Mit dem echten Panelrahmen vergleichen, nicht mit `lastFrame`: beim
        // Umstecken verschiebt macOS Fenster auch selbst.
        guard panel.frame != rect else { return }
        panel.setFrame(rect, display: true)
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
///   und collectionBehavior schafft das; deshalb erkennt `FullscreenMonitor`
///   Vollbild selbst, und die Leiste wird dort unsichtbar und
///   klickdurchlaessig (siehe `setHiddenForFullscreen`).
/// - Kein Fensterschatten: gab beim Launcher einen zweiten, fast eckigen
///   Rahmen um das Glas.
/// - `canHide = false`: "Andere ausblenden" soll sie nicht verschwinden lassen.
final class SidebarPanel: ShellPanel {
    init() {
        super.init(level: .floating, behavior: [.canJoinAllSpaces, .stationary, .ignoresCycle], deferred: false)
        canHide = false
        becomesKeyOnlyIfNeeded = true
    }
}
