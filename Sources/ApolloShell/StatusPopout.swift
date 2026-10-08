import AppKit
import ApolloShellCore
import SwiftUI

/// Detailfenster fuer WLAN, Bluetooth und Akku, das aus der Leiste
/// herauswaechst (Caelestia: modules/bar/popouts).
///
/// Leiste und Popout sind eine einzige Glasflaeche: Das Popout lebt im
/// Fenster der Leiste, im selben `GlassEffectContainer` (`SidebarRoot`), und
/// verschmilzt dort mit ihr. Ein eigenes Fenster daneben ginge nicht - Glas
/// aus zwei Fenstern bleibt zwei Flaechen mit einer Kante dazwischen.
///
/// Beim Oeffnen wird das Leistenfenster breiter (`setExpanded`). Der neue
/// Platz ist durchsichtig, also springt nichts. Dann waechst das Glas in
/// SwiftUI heraus (`StatusPopoutStage`). Nach der Schliessbewegung wird das
/// Fenster wieder so schmal wie die Leiste.
///
/// Fokus: das Fenster wird nie Schluesselfenster, die App des Nutzers behaelt
/// die Tastatur. Deshalb schliessen Klicks ausserhalb ueber Maus-Monitore
/// (fuer die Maus braucht es keine Freigabe) und Esc ueber einen Carbon-
/// Hotkey, der nur gilt, solange das Popout offen ist - wie bei einem Menue
/// geht Esc dann ans Popout und nicht an die App darunter.
@MainActor
final class StatusPopout {
    let model = StatusPopoutModel()

    /// Rechnet einen Symbolrahmen aus der Leisten-Ansicht (oben = 0) in
    /// Bildschirmkoordinaten um; setzt die Leiste, der die Ansicht gehoert.
    var screenRect: (CGRect) -> NSRect? = { _ in nil }
    /// Fenster der Leiste, in dem das Popout liegt.
    weak var hostWindow: NSWindow?
    /// Leistenfenster verbreitern (`true`) oder wieder schmal machen.
    var setExpanded: (Bool) -> Void = { _ in }
    /// Dieses Popout geht gerade auf. Der Verwalter der Leisten schliesst
    /// darauf ein Popout, das auf einem anderen Bildschirm noch offen steht -
    /// es ist immer nur eines offen.
    var onOpen: () -> Void = {}

    /// Breite des Leistenfensters mit offenem Popout: Leiste, breitestes
    /// Popout und Luft fuer das Ueberschiessen der Kurve (~1,5 %).
    static var expandedWidth: CGFloat {
        Sidebar.width + StatusPopoutKind.allCases.map(StatusPopoutContent.width).max()! + 24
    }

    /// Esc, solange das Popout offen ist. Jede Anmeldung bekommt in
    /// `GlobalHotKey` eine eigene Kennung - bei mehreren Leisten landet der
    /// Druck so beim offenen Popout und nicht bei dem, das zuletzt gebaut wurde.
    private var escapeKey: GlobalHotKey?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var generation = 0

    private var hoverOpen: DispatchWorkItem?
    private var hoverClose: DispatchWorkItem?
    private var overIcon = false
    private var overPanel = false
    private var byHover = false

    init() {
        model.onIconClick = { [weak self] kind in self?.iconClicked(kind) }
        model.onOpenedSettings = { [weak self] in self?.close() }
        model.onStackHover = { [weak self] st, fr, inside in self?.stackHover(st, fr, inside) }
        model.onStackToggle = { [weak self] st, fr in self?.stackToggle(st, fr) }
        model.onPanelHover = { [weak self] inside in self?.panelHover(inside) }
        model.onIconHover = { [weak self] kind, inside in self?.iconHover(kind, inside) }
    }

    private func stackHover(_ st: DockStack, _ fr: CGRect, _ inside: Bool) {
        overIcon = inside
        hoverOpen?.cancel()
        if inside {
            hoverClose?.cancel()
            if model.isOpen, model.shown == .stack, model.stack?.id == st.id { return }
            let fast = model.isOpen && model.shown == .stack
            let w = DispatchWorkItem { [weak self] in
                guard let self, self.overIcon else { return }
                self.byHover = true
                self.showStack(st, fr)
            }
            hoverOpen = w
            DispatchQueue.main.asyncAfter(deadline: .now() + (fast ? 0.05 : (st.windows ? 0.5 : 0.15)), execute: w)
        } else {
            scheduleHoverClose()
        }
    }

    private func iconHover(_ kind: StatusPopoutKind, _ inside: Bool) {
        overIcon = inside
        hoverOpen?.cancel()
        guard inside else { scheduleHoverClose(); return }
        hoverClose?.cancel()
        if model.isOpen, model.shown == kind { return }
        let fast = model.isOpen
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.overIcon, let anchor = self.model.iconFrames[kind]?.midY else { return }
            if self.model.isOpen {
                withAnimation(StatusPopoutMotion.spatial) { self.model.show(kind, anchorY: anchor) }
            } else {
                self.open(kind, anchorY: anchor)
            }
            self.byHover = true
        }
        hoverOpen = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (fast ? 0.05 : 0.15), execute: w)
    }

    private func panelHover(_ inside: Bool) {
        overPanel = inside
        if inside { hoverClose?.cancel() } else { scheduleHoverClose() }
    }

    private func scheduleHoverClose() {
        guard model.isOpen, byHover else { return }
        hoverClose?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.overIcon, !self.overPanel else { return }
            self.close()
        }
        hoverClose = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
    }

    private func stackToggle(_ st: DockStack, _ fr: CGRect) {
        hoverOpen?.cancel()
        if model.isOpen, model.shown == .stack, model.stack?.id == st.id {
            if byHover { byHover = false } else { close() }
            return
        }
        byHover = false
        showStack(st, fr)
    }

    private func showStack(_ st: DockStack, _ fr: CGRect) {
        model.setStack(DockStack.shots?.id == st.id && DockStack.shots?.items.map(\.id) == st.items.map(\.id) ? DockStack.shots : st)
        if model.isOpen {
            withAnimation(StatusPopoutMotion.spatial) { model.show(.stack, anchorY: fr.midY) }
        } else {
            open(.stack, anchorY: fr.midY)
        }
    }

    var isOpen: Bool { model.isOpen }

    // MARK: - Klicks auf die Statussymbole

    /// Gleiches Symbol: zu. Anderes Symbol bei offenem Popout: Inhalt an Ort
    /// und Stelle wechseln. Sonst: oeffnen.
    private func iconClicked(_ kind: StatusPopoutKind) {
        // Symbol und Buehne liegen in derselben Ansicht, oben = 0: die Mitte
        // des Symbols ist direkt der Anker.
        guard let anchor = model.iconFrames[kind]?.midY else { return }
        hoverOpen?.cancel()
        if model.isOpen {
            if model.shown == kind {
                if byHover { byHover = false } else { close() }
            } else {
                byHover = false
                withAnimation(StatusPopoutMotion.spatial) { model.show(kind, anchorY: anchor) }
            }
            return
        }
        open(kind, anchorY: anchor)
    }

    private func open(_ kind: StatusPopoutKind, anchorY: CGFloat) {
        generation += 1
        // Zuerst: ein offenes Popout auf einer anderen Leiste geht zu, bevor
        // dieses sein Fenster verbreitert.
        onOpen()
        setExpanded(true)
        // Keim ohne Bewegung zum angeklickten Symbol, dann herauswachsen.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { model.prepare(kind, anchorY: anchorY) }
        withAnimation(StatusPopoutMotion.spatial) { model.show(kind, anchorY: anchorY) }
        installMonitors()
        registerEscape()
    }

    func close() {
        guard model.isOpen else { return }
        hoverOpen?.cancel()
        hoverClose?.cancel()
        overPanel = false
        byHover = false
        generation += 1
        let current = generation
        withAnimation(StatusPopoutMotion.spatial) { model.hide() }
        removeMonitors()
        escapeKey?.unregister()
        escapeKey = nil
        // Erst nach der Schliessbewegung schmal; oeffnet man vorher neu, bleibt es breit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.generation == current else { return }
            self.setExpanded(false)
        }
    }

    /// Esc gehoert dem Popout nur, solange es offen ist - dauerhaft belegt
    /// wuerde es jeder App fehlen. Hat eine andere App Esc schon global
    /// belegt, schliessen Klick daneben und das Symbol weiterhin.
    private func registerEscape() {
        guard escapeKey == nil else { return }
        if case .success(let key) = GlobalHotKey.register(HotKey(keyCode: HotKeyKey.escape), action: { [weak self] in self?.close() }) {
            escapeKey = key
        }
    }

    // MARK: - Klicks ausserhalb

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        // Klicks in andere Apps: immer ausserhalb.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        // Klicks in eigene Fenster (Leiste, Dashboard, ...). Die sieht der
        // globale Monitor nicht. Das Ereignis geht immer weiter.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.localClick(event) }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func localClick(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        if let window = hostWindow, event.window === window {
            // Im Glas des Popouts: bleibt offen. `panelFrame` zaehlt ab der
            // rechten Leistenkante, oben = 0.
            let frame = window.frame
            let inStage = CGPoint(x: point.x - frame.minX - Sidebar.width, y: frame.maxY - point.y)
            if model.panelFrame.contains(inStage) { return }
        }
        // Auf ein Statussymbol: das erledigt dessen Knopf (zu oder wechseln).
        // Sonst, auch im durchsichtigen Teil des breiten Fensters: zu.
        let onIcon = model.iconFrames.values.contains { screenRect($0)?.contains(point) == true }
        if !onIcon, !(model.shown == .stack && overIcon) { close() }
    }
}
