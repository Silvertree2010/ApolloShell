import AppKit
import Carbon.HIToolbox
import ApolloShellCore
import SwiftUI

/// Detailfenster fuer WLAN, Bluetooth und Akku direkt rechts neben der
/// Leiste (Caelestia: modules/bar/popouts).
///
/// Buendig an der Leiste, ohne Abstand: bei Caelestia sind Leiste und Popout
/// eine einzige Flaeche (gemeinsamer Rahmen), das Popout waechst aus der
/// Leiste heraus. Unsere anderen Kantenfenster machen es an der
/// Bildschirmkante genauso - die Ecken an der Kante liegen ausserhalb.
/// Ein Abstand wuerde daraus ein schwebendes Menue machen.
///
/// Das Fenster ist so hoch wie die Leiste und so breit wie das breiteste
/// Popout. Es bewegt sich nie; nur das Glas darin waechst, gleitet und
/// wechselt die Groesse (`StatusPopoutStage`). So laeuft jede Bewegung in
/// SwiftUI, ohne Fensterrahmen, die mitten in der Animation springen.
///
/// Fokus: das Panel wird nie Schluesselfenster, die App des Nutzers behaelt
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

    private let panel = StatusPopoutPanel()
    private let escapeKey = StatusPopoutEscapeKey()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var generation = 0

    /// Breitestes Popout plus Luft fuer das Ueberschiessen der Kurve (~1,5 %).
    private static var windowWidth: CGFloat {
        StatusPopoutKind.allCases.map(StatusPopoutContent.width).max()! + 24
    }

    init() {
        let hosting = FirstMouseHostingView(rootView: StatusPopoutRoot(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        escapeKey.onPress = { [weak self] in self?.close() }
        model.onIconClick = { [weak self] kind in self?.iconClicked(kind) }
        model.onOpenedSettings = { [weak self] in self?.close() }
    }

    var isOpen: Bool { model.isOpen }

    // MARK: - Klicks auf die Statussymbole

    /// Gleiches Symbol: zu. Anderes Symbol bei offenem Popout: Inhalt an Ort
    /// und Stelle wechseln. Sonst: oeffnen.
    private func iconClicked(_ kind: StatusPopoutKind) {
        guard let screen = NSScreen.screens.first, let anchor = anchorY(for: kind, on: screen) else { return }
        if model.isOpen {
            if model.shown == kind {
                close()
            } else {
                withAnimation(StatusPopoutMotion.spatial) { model.show(kind, anchorY: anchor) }
            }
            return
        }
        open(kind, anchorY: anchor, on: screen)
    }

    private func open(_ kind: StatusPopoutKind, anchorY: CGFloat, on screen: NSScreen) {
        generation += 1
        panel.setFrame(Self.frame(on: screen), display: false)
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { model.prepare(kind, anchorY: anchorY) }
        panel.orderFrontRegardless()
        withAnimation(StatusPopoutMotion.spatial) { model.show(kind, anchorY: anchorY) }
        installMonitors()
        escapeKey.register()
    }

    func close() {
        guard model.isOpen else { return }
        generation += 1
        let current = generation
        withAnimation(StatusPopoutMotion.spatial) { model.hide() }
        removeMonitors()
        escapeKey.unregister()
        // Erst nach der Schliessbewegung weg; oeffnet man vorher neu, bleibt es.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.generation == current else { return }
            self.panel.orderOut(nil)
        }
    }

    // MARK: - Geometrie

    /// Rechts an der Leiste, gleiche Hoehe wie sie: unten bis zum Rand,
    /// oben bis unter die Menueleiste.
    private static func frame(on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        return NSRect(x: frame.minX + Sidebar.width, y: frame.minY,
                      width: windowWidth, height: screen.visibleFrame.maxY - frame.minY)
    }

    private func anchorY(for kind: StatusPopoutKind, on screen: NSScreen) -> CGFloat? {
        guard let icon = model.iconFrames[kind], let rect = screenRect(icon) else { return nil }
        return Self.frame(on: screen).maxY - rect.midY
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
        if event.window === panel {
            // Im Glas: bleibt offen. Daneben im durchsichtigen Teil (falls der
            // Klick nicht ohnehin durchfaellt): wie ausserhalb.
            let frame = panel.frame
            let inWindow = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
            if !model.panelFrame.contains(inWindow) { close() }
            return
        }
        // Auf ein Statussymbol: das erledigt dessen Knopf (zu oder wechseln).
        let onIcon = model.iconFrames.values.contains { screenRect($0)?.contains(point) == true }
        if !onIcon { close() }
    }
}

/// Wurzel der Ansicht im Popout-Fenster.
struct StatusPopoutRoot: View {
    let model: StatusPopoutModel

    var body: some View {
        StatusPopoutStage(model: model, anchorY: model.anchorY)
    }
}

/// Randloses Panel, das nie Fokus nimmt. Ebene ueber allem wie die anderen
/// Kantenfenster; Fensterschatten aus, sonst zweiter Rahmen ums Glas.
final class StatusPopoutPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        canHide = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Nicht von AppKit unter die Menueleiste o. ae. schieben lassen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Esc als Carbon-Hotkey, nur solange das Popout offen ist.
///
/// Warum nicht `GlobalHotKey`: der meldet sich nie wieder ab, und ein
/// dauerhaft belegtes Esc wuerde es jeder App wegnehmen. Hier: Handler
/// einmal, Hotkey bei `register()` an, bei `unregister()` wieder frei.
/// Braucht wie alle Carbon-Hotkeys keine Bedienungshilfen-Freigabe.
@MainActor
final class StatusPopoutEscapeKey {
    var onPress: () -> Void = {}

    private static let signature = OSType(0x4C_4E_50_4F) // "LNPO"
    private static let id: UInt32 = 1
    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
            )
            guard status == noErr, pressed.signature == StatusPopoutEscapeKey.signature,
                  pressed.id == StatusPopoutEscapeKey.id
            else { return OSStatus(eventNotHandledErr) }
            // Carbon liefert Hotkeys auf dem Main-Thread.
            let key = Unmanaged<StatusPopoutEscapeKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { key.onPress() }
            return noErr
        }, 1, &spec, context, &handlerRef)
    }

    /// `true`, wenn Esc jetzt belegt ist.
    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape), 0, EventHotKeyID(signature: Self.signature, id: Self.id),
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        return status == noErr
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }
}
