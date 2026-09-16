import AppKit
import ApplicationServices
import ApolloShellCore
import os

/// Fensterwache: haelt fremde Fenster aus dem Streifen der linken Leiste
/// heraus und merkt, wenn die Vordergrund-App im Vollbild ist.
///
/// macOS hat keine Schnittstelle, um Bildschirmplatz zu reservieren; der
/// `visibleFrame` gehoert allein Dock und Menueleiste. Also wie die App
/// "Sidebar": ueber die Bedienungshilfen (AXUIElement/AXObserver) auf die
/// Fensterereignisse aller Apps hoeren und Fenster, die unter die Leiste
/// ragen, nachtraeglich zurechtruecken. Die Rechnung dazu steht in
/// ApolloShellCore/WindowClamp.swift und ist dort getestet.
///
/// Vollbild: Ein Panel mit `.canJoinAllSpaces` erscheint auf macOS 26 auch
/// in Vollbild-Spaces (die sind auch nur Spaces), egal ob mit oder ohne
/// `.fullScreenAuxiliary`. Deshalb wird hier nachgesehen, ob das
/// Fokus-Fenster der Vordergrund-App `AXFullScreen` ist, und die Leiste
/// blendet sich dann selbst aus.
///
/// Braucht die Freigabe "Bedienungshilfen". Einmal pro Start wird darum
/// gebeten; ohne Freigabe bleibt alles wie vorher (Leiste immer sichtbar,
/// Fenster laufen darunter durch). Alle 2 s wird nachgesehen, ob sie
/// inzwischen erteilt oder entzogen wurde - ein Neustart ist nicht noetig.
///
/// Dieser Teil lebt auf dem Hauptthread und leitet nur weiter; die
/// eigentliche Arbeit macht `WindowGuardWorker` auf einer eigenen Queue.
@MainActor
final class WindowGuard {
    /// AXIsProcessTrusted ist billig; 2 s sind schnell genug, dass die
    /// Wache kurz nach dem Anhaken in den Systemeinstellungen loslegt.
    private static let trustPollInterval: TimeInterval = 2

    private let worker: WindowGuardWorker
    private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "windowguard")
    private var trusted = false
    /// Schluessel der Bildschirme, auf denen eine Leiste steht - nur dort
    /// wird der Streifen freigehalten. Meldet der Verwalter der Leisten.
    private var barScreenKeys: Set<String> = []

    /// `askForAccess`: beim Start die Systemfrage zeigen, falls die Freigabe
    /// fehlt. Aus, solange die Einfuehrung laeuft - die erklaert erst, wozu,
    /// und fragt dann selbst.
    ///
    /// `onFullscreenChange` meldet die Schluessel der Bildschirme, deren
    /// Vordergrund-App im Vollbild ist - dort tritt die Leiste ab.
    init(reservedWidth: CGFloat, askForAccess: Bool = true,
         onFullscreenChange: @escaping @MainActor @Sendable (Set<String>) -> Void) {
        worker = WindowGuardWorker(reservedWidth: reservedWidth) { fullscreen in
            // DispatchQueue statt Task: haelt die Reihenfolge ein, ein
            // schnelles an-aus kommt nie als aus-an an.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { onFullscreenChange(fullscreen) }
            }
        }

        // Einmal pro Start fragen (zeigt den Systemdialog nur, solange die
        // Freigabe fehlt). Der Schluessel ist der Wert von
        // kAXTrustedCheckOptionPrompt; die Konstante selbst ist eine globale
        // `var` und gaebe unter Swift 6 eine Nebenlaeufigkeits-Warnung.
        let options = ["AXTrustedCheckOptionPrompt": askForAccess] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        log.notice("Bedienungshilfen \(self.trusted ? "freigegeben" : "nicht freigegeben", privacy: .public)")
        if trusted { startWorker() }

        observeSystem()
        startTrustPolling()
    }

    // MARK: - Freigabe

    /// Die Freigabe kommt (oder geht) waehrend der Laufzeit ueber die
    /// Systemeinstellungen; eine Benachrichtigung dafuer gibt es nicht.
    /// Der Timer laeuft so lange wie der Prozess, deshalb wird er nie
    /// invalidiert.
    private func startTrustPolling() {
        let timer = Timer.scheduledTimer(withTimeInterval: Self.trustPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTrust() }
        }
        timer.tolerance = 0.5
    }

    private func pollTrust() {
        let now = AXIsProcessTrusted()
        guard now != trusted else { return }
        trusted = now
        if now {
            log.notice("Bedienungshilfen freigegeben, Fensterwache startet")
            startWorker()
        } else {
            // Entzogen: aufhoeren und die Leiste wieder zeigen, sonst bliebe
            // sie nach einem Vollbild womoeglich fuer immer weg.
            log.notice("Bedienungshilfen entzogen, Fensterwache haelt an")
            worker.stop()
        }
    }

    private func startWorker() {
        worker.start(
            screens: screensForWorker() ?? [],
            frontmost: Self.regularFrontmostPID(),
            apps: NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map(\.processIdentifier)
        )
    }

    private static func regularFrontmostPID() -> pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.activationPolicy == .regular else { return nil }
        return app.processIdentifier
    }

    /// Auf welchen Bildschirmen eine Leiste steht. Danach richtet sich, wo
    /// der Streifen freigehalten wird; der Verwalter der Leisten meldet jede
    /// Aenderung.
    func setBarScreens(_ keys: Set<String>) {
        guard keys != barScreenKeys else { return }
        barScreenKeys = keys
        log.notice("Streifen freihalten auf \(keys.count, privacy: .public) Bildschirm(en)")
        guard let screens = screensForWorker() else { return }
        worker.screensChanged(screens)
    }

    /// Bildschirme in Bedienungshilfen-Koordinaten, der mit der Menueleiste
    /// zuerst, jeder mit seinem Schluessel und der Angabe, ob dort eine
    /// Leiste steht. `nil`, wenn gerade keiner da ist (Bildschirm mitten im
    /// Umstecken): dann die alten behalten.
    private func screensForWorker() -> [GuardScreen]? {
        let screens = ShellScreens.current()
        guard let primary = screens.first else { return nil }
        // Ursprung der Bedienungshilfen ist die linke obere Ecke des
        // Hauptbildschirms, in AppKit dessen maxY.
        let primaryHeight = primary.frame.maxY
        return screens.map { screen in
            GuardScreen(
                key: screen.info.key,
                frame: WindowClamp.flipped(screen.frame, primaryHeight: primaryHeight),
                reserved: barScreenKeys.contains(screen.info.key)
            )
        }
    }

    // MARK: - Systemereignisse weiterreichen

    /// Die Wache lebt so lange wie der Prozess (AppDelegate haelt sie), die
    /// Beobachter muessen deshalb nie entfernt werden. Solange die Freigabe
    /// fehlt, laufen die Meldungen beim Worker ins Leere.
    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let worker = worker

        workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular
            else { return }
            worker.appLaunched(app.processIdentifier)
        }
        workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            worker.appTerminated(app.processIdentifier)
        }
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            worker.appActivated(app.processIdentifier, isRegular: app.activationPolicy == .regular)
        }
        // Space-Wechsel (auch Vollbild an/aus, das ist ein eigener Space) und
        // Aufwachen: Vollbild neu pruefen, neu sichtbare Fenster aufnehmen.
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                worker.spaceChanged()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let screens = self.screensForWorker() else { return }
                worker.screensChanged(screens)
            }
        }
    }
}

/// Ein Bildschirm, wie ihn die Fensterwache braucht.
struct GuardScreen: Sendable, Equatable {
    /// Stabiler Schluessel (Name plus Aufloesung), um den Bildschirm beim
    /// Vollbild zurueckzumelden.
    let key: String
    /// Rahmen in Bedienungshilfen-Koordinaten (Ursprung oben links am
    /// Hauptbildschirm, y nach unten).
    let frame: CGRect
    /// Dort steht eine Leiste: den Streifen freihalten. Auf Bildschirmen
    /// ohne Leiste werden Fenster in Ruhe gelassen.
    let reserved: Bool
}

/// Die eigentliche Fensterwache.
///
/// Alles laeuft auf einer seriellen Queue: Bedienungshilfen-Aufrufe sind
/// synchrone Anfragen an die andere App und warten, bis sie antwortet - bei
/// einer haengenden App bis zum Timeout. Auf dem Hauptthread wuerde das den
/// Launcher-Hotkey ausbremsen (dort zaehlen Millisekunden).
///
/// Die Runloop-Quellen der AXObserver haengen trotzdem an der Main-Runloop
/// (eine Dispatch-Queue hat keine eigene); ihr Callback reicht die Meldung
/// nur an die Queue weiter und kostet dort praktisch nichts.
///
/// `@unchecked Sendable`: Der Zustand wird ausschliesslich auf `queue`
/// angefasst, die oeffentlichen Methoden springen alle zuerst dorthin.
final class WindowGuardWorker: @unchecked Sendable {
    /// So lange muss ein Fenster ruhig sein, bevor es angefasst wird. Beim
    /// Ziehen, Aufziehen und bei Zoom-/Kachel-Animationen kommen die
    /// "bewegt"-Meldungen im Abstand von Millisekunden und schieben den
    /// Termin jedes Mal nach hinten; erst wenn das Fenster steht, greift die
    /// Wache ein. Kuerzer wirkt es wie ein Ruck mitten in der Animation,
    /// laenger sieht man das Fenster sichtbar unter der Leiste liegen.
    static let settleDelay: TimeInterval = 0.2
    /// Vollbild an/aus und Space-Wechsel sind animiert; Vordergrund-App und
    /// `AXFullScreen` stimmen erst danach sicher. Deshalb gleich einmal
    /// (damit die Leiste moeglichst schnell verschwindet) und zur Sicherheit
    /// nach der Animation noch einmal.
    static let fullscreenChecks: [TimeInterval] = [0.05, 0.4, 1.0]
    /// Frisch gestartete Apps antworten oft noch nicht
    /// (kAXErrorCannotComplete). So oft und in diesem Abstand nachfassen.
    static let registerRetries = 10
    static let registerRetryDelay: TimeInterval = 0.5
    /// Hoechstens so lange auf eine App warten. Vorgabe von macOS sind 6 s,
    /// so lange stuende die ganze Wache wegen einer haengenden App still.
    static let messagingTimeout: Float = 1

    private let queue = DispatchQueue(label: AppIdentity.scoped("windowguard"))
    private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "windowguard")
    private let reservedWidth: CGFloat
    private let onFullscreen: @Sendable (Set<String>) -> Void
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    // Nur auf `queue` anfassen.
    private var running = false
    /// Bildschirme in Bedienungshilfen-Koordinaten, Hauptbildschirm zuerst.
    private var screens: [GuardScreen] = []
    private var apps: [pid_t: ObservedApp] = [:]
    /// Pro Fenster der naechste geplante Blick (Entprellung).
    private var pending: [AXUIElement: DispatchWorkItem] = [:]
    /// 3 Eingriffe in 30 s: genug fuer "zweimal hintereinander wieder
    /// daruntergezogen", aber eine App, die ihr Fenster jedes Mal zurueck-
    /// legt, zappelt hoechstens alle 30 s kurz statt dauernd.
    private var ledger = ClampLedger<AXUIElement>(maxAttempts: 3, period: 30)
    /// Aus abgelehnten Verkleinerungen gelernte Mindestbreiten.
    private var minWidths: [AXUIElement: CGFloat] = [:]
    /// Letzte regulaere Vordergrund-App. Hilfs-Apps (Menueleisten-Apps,
    /// Raycast & Co.) zaehlen nicht: oeffnet so eine ihr Panel ueber einem
    /// Vollbild, soll die Leiste nicht kurz hereinblitzen.
    private var frontmostPID: pid_t?
    /// Schluessel der Bildschirme, deren Vordergrund-App im Vollbild ist.
    private var fullscreenKeys: Set<String> = []
    private var fullscreenWork: [DispatchWorkItem] = []

    init(reservedWidth: CGFloat, onFullscreen: @escaping @Sendable (Set<String>) -> Void) {
        self.reservedWidth = reservedWidth
        self.onFullscreen = onFullscreen
    }

    // MARK: - Von aussen (beliebiger Thread)

    func start(screens: [GuardScreen], frontmost: pid_t?, apps pids: [pid_t]) {
        queue.async { [self] in
            guard !running else { return }
            running = true
            // Gilt fuer alle Bedienungshilfen-Anfragen dieses Prozesses.
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)
            self.screens = screens
            frontmostPID = frontmost
            for pid in pids { watchApp(pid, attempt: 0) }
            scheduleFullscreenChecks()
            log.notice("Fensterwache laeuft, \(self.apps.count, privacy: .public) Apps beobachtet")
        }
    }

    func stop() {
        queue.async { [self] in
            guard running else { return }
            running = false
            for pid in Array(apps.keys) { unwatchApp(pid) }
            for work in pending.values { work.cancel() }
            pending = [:]
            for work in fullscreenWork { work.cancel() }
            fullscreenWork = []
            ledger = ClampLedger(maxAttempts: ledger.maxAttempts, period: ledger.period)
            minWidths = [:]
            publishFullscreen([])
        }
    }

    func appLaunched(_ pid: pid_t) {
        queue.async { [self] in
            guard running else { return }
            watchApp(pid, attempt: 0)
        }
    }

    func appTerminated(_ pid: pid_t) {
        queue.async { [self] in
            unwatchApp(pid)
            if frontmostPID == pid { frontmostPID = nil }
        }
    }

    func appActivated(_ pid: pid_t, isRegular: Bool) {
        queue.async { [self] in
            guard isRegular, pid != ownPID else { return }
            frontmostPID = pid
            guard running else { return }
            if apps[pid] == nil {
                // Apps, die erst spaeter regulaer wurden.
                watchApp(pid, attempt: 0)
            } else if let window = AX.element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) {
                // Fenster auf anderen Spaces liefert kAXWindowsAttribute nicht;
                // spaetestens wenn sie in den Vordergrund kommen, sind sie dran.
                watchWindow(window, pid: pid)
                scheduleClamp(window)
            }
            scheduleFullscreenChecks()
        }
    }

    func spaceChanged() {
        queue.async { [self] in
            guard running else { return }
            scheduleFullscreenChecks()
            sweepWindows(onlyNew: true)
        }
    }

    func screensChanged(_ screens: [GuardScreen]) {
        queue.async { [self] in
            self.screens = screens
            guard running else { return }
            // Andere Aufloesung oder Anordnung: jedes Fenster kann jetzt
            // anders zur Leiste liegen.
            sweepWindows(onlyNew: false)
            scheduleFullscreenChecks()
        }
    }

    /// Vom AXObserver-Callback auf dem Hauptthread.
    fileprivate func receive(_ element: AXElementRef, _ notification: String) {
        queue.async { [self] in handle(element.element, notification) }
    }

    // MARK: - Beobachten

    private func watchApp(_ pid: pid_t, attempt: Int) {
        guard running, pid > 0, pid != ownPID, apps[pid] == nil else { return }

        var created: AXObserver?
        let status = AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let worker = Unmanaged<WindowGuardWorker>.fromOpaque(refcon).takeUnretainedValue()
            worker.receive(AXElementRef(element: element), notification as String)
        }, &created)
        guard status == .success, let observer = created else {
            log.error("AXObserver fuer pid \(pid, privacy: .public) nicht angelegt: \(status.rawValue, privacy: .public)")
            return
        }

        // Der Worker lebt so lange wie der Prozess, unretained genuegt.
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let app = AXUIElementCreateApplication(pid)
        let results = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification].map {
            AXObserverAddNotification(observer, app, $0 as CFString, refcon)
        }
        guard results.contains(where: { $0 == .success || $0 == .notificationAlreadyRegistered }) else {
            if results.contains(.cannotComplete), attempt < Self.registerRetries {
                queue.asyncAfter(deadline: .now() + Self.registerRetryDelay) { [self] in
                    watchApp(pid, attempt: attempt + 1)
                }
            } else {
                log.info("pid \(pid, privacy: .public) nicht beobachtbar: \(results.map(\.rawValue), privacy: .public)")
            }
            return
        }

        // .commonModes: auch waehrend im Hauptthread ein Menue oder ein
        // Ziehvorgang laeuft (eventTracking), sonst stauen sich die Meldungen.
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        apps[pid] = ObservedApp(element: app, observer: observer)

        for window in AX.elements(app, kAXWindowsAttribute) {
            watchWindow(window, pid: pid)
            scheduleClamp(window)
        }
    }

    private func unwatchApp(_ pid: pid_t) {
        guard let app = apps.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(app.observer), .commonModes)
        let belongs: (AXUIElement) -> Bool = { AX.pid(of: $0) == pid }
        for (window, work) in pending where belongs(window) {
            work.cancel()
            pending[window] = nil
        }
        ledger.forget(where: belongs)
        minWidths = minWidths.filter { !belongs($0.key) }
    }

    /// "Bewegt" und "Groesse geaendert" kommen pro Fenster, also jedes neue
    /// Fenster einzeln anmelden. Das Observer-Objekt der App meldet sie ab,
    /// sobald es freigegeben wird.
    private func watchWindow(_ window: AXUIElement, pid: pid_t) {
        guard let app = apps[pid], !app.windows.contains(window),
              AX.string(window, kAXRoleAttribute) == kAXWindowRole
        else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [
            kAXWindowMovedNotification,
            kAXWindowResizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXUIElementDestroyedNotification,
        ] {
            AXObserverAddNotification(app.observer, window, name as CFString, refcon)
        }
        app.windows.insert(window)
    }

    /// Fensterliste neu lesen. `onlyNew`: nur Fenster, die noch nicht
    /// angemeldet sind (nach einem Space-Wechsel die dort neu sichtbaren);
    /// die bekannten melden sich selbst, wenn sie bewegt werden.
    private func sweepWindows(onlyNew: Bool) {
        for (pid, app) in apps {
            for window in AX.elements(app.element, kAXWindowsAttribute) {
                if onlyNew, app.windows.contains(window) { continue }
                watchWindow(window, pid: pid)
                scheduleClamp(window)
            }
        }
    }

    private func forget(_ window: AXUIElement, pid: pid_t) {
        pending.removeValue(forKey: window)?.cancel()
        ledger.forget(window)
        minWidths[window] = nil
        apps[pid]?.windows.remove(window)
    }

    private func handle(_ element: AXUIElement, _ notification: String) {
        guard running else { return }
        let pid = AX.pid(of: element)
        switch notification {
        case kAXWindowCreatedNotification:
            watchWindow(element, pid: pid)
            scheduleClamp(element)
        case kAXFocusedWindowChangedNotification:
            // Meist ist das Element das neue Fenster; manche Apps melden die App.
            let window = AX.string(element, kAXRoleAttribute) == kAXApplicationRole
                ? AX.element(element, kAXFocusedWindowAttribute) : element
            if let window {
                watchWindow(window, pid: pid)
                scheduleClamp(window)
            }
            if pid == frontmostPID { scheduleFullscreenChecks() }
        case kAXWindowResizedNotification:
            scheduleClamp(element)
            // Vollbild an/aus veraendert die Groesse des Fensters.
            if pid == frontmostPID { scheduleFullscreenChecks() }
        case kAXWindowMovedNotification, kAXWindowDeminiaturizedNotification:
            scheduleClamp(element)
        case kAXUIElementDestroyedNotification:
            forget(element, pid: pid)
        default:
            break
        }
    }

    // MARK: - Zurechtruecken

    /// Entprellt: jede Meldung schiebt den Blick auf das Fenster um
    /// `settleDelay` nach hinten, eingegriffen wird erst, wenn es ruht.
    private func scheduleClamp(_ window: AXUIElement) {
        pending[window]?.cancel()
        let ref = AXElementRef(element: window)
        let work = DispatchWorkItem { [self] in
            pending[ref.element] = nil
            clampIfNeeded(ref.element)
        }
        pending[window] = work
        queue.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func clampIfNeeded(_ window: AXUIElement) {
        guard running, !screens.isEmpty else { return }

        // Linke Maustaste noch unten: jemand zieht das Fenster gerade (oder
        // haelt es nur still). Nicht unter der Hand wegreissen, spaeter
        // wieder nachsehen - wie der Dock erst nach dem Loslassen.
        if CGEventSource.buttonState(.combinedSessionState, button: .left) {
            scheduleClamp(window)
            return
        }

        let pid = AX.pid(of: window)
        // Nur Standardfenster: Sheets, Dialoge, schwebende Paletten und
        // Popover haben eine andere Rolle oder Subrolle und haengen an ihrem
        // Elternfenster bzw. gehoeren bewusst dorthin, wo sie sind.
        // Minimierte und Vollbild-Fenster gehen die Leiste nichts an, und
        // Fenster auf einem Bildschirm ohne Leiste auch nicht.
        guard pid != ownPID, apps[pid] != nil,
              AX.string(window, kAXRoleAttribute) == kAXWindowRole,
              AX.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
              AX.bool(window, kAXMinimizedAttribute) != true,
              AX.bool(window, AX.fullScreenAttribute) != true,
              let frame = AX.frame(of: window),
              // Das Fenster gehoert dem Bildschirm, auf dem der groesste Teil
              // liegt - und geschoben wird nur dort, wo eine Leiste steht.
              let index = WindowClamp.dominantScreen(for: frame, among: screens.map(\.frame)),
              screens[index].reserved,
              let target = WindowClamp.clampedFrame(
                  window: frame, screen: screens[index].frame,
                  reservedWidth: reservedWidth, minWidth: minWidths[window] ?? 0
              )
        else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard ledger.shouldClamp(window, current: frame, now: now) else {
            log.debug("pid \(pid, privacy: .public): Fenster eben erst angefasst oder wehrt sich, lasse es")
            return
        }
        guard AX.isSettable(window, kAXPositionAttribute) else { return }

        apply(target, to: window, current: frame, pid: pid)

        // Nachlesen: Was die App daraus gemacht hat, ist der neue Stand. Hat
        // sie die Verkleinerung abgelehnt, ist das ihre Mindestbreite - dann
        // beim naechsten Mal gar nicht erst schmaler machen, nur schieben.
        let result = AX.frame(of: window) ?? target
        if target.width < frame.width - WindowClamp.tolerance,
           result.width > target.width + WindowClamp.tolerance {
            minWidths[window] = result.width
        }
        ledger.record(window, result: result, now: now)
        log.debug("pid \(pid, privacy: .public): \(String(describing: frame), privacy: .public) -> \(String(describing: result), privacy: .public)")
    }

    private func apply(_ target: CGRect, to window: AXUIElement, current: CGRect, pid: pid_t) {
        // Chromium, Firefox & Co. schalten "AXEnhancedUserInterface" ein,
        // sobald Bedienungshilfen-Software laeuft; dann animieren sie jede
        // Aenderung und uebernehmen Position und Groesse nur teilweise. Fuer
        // den Eingriff aus, danach wieder wie vorher (so macht es Rectangle).
        let app = AXUIElementCreateApplication(pid)
        let enhanced = AX.bool(app, AX.enhancedUserInterfaceAttribute) == true
        if enhanced { AX.setBool(app, AX.enhancedUserInterfaceAttribute, false) }
        defer { if enhanced { AX.setBool(app, AX.enhancedUserInterfaceAttribute, true) } }

        // Erst schmaler, dann schieben: so ragt das Fenster zwischendurch
        // nie rechts ueber den Bildschirm. Lehnt die App die Groesse ab,
        // wird es trotzdem verschoben.
        if abs(target.width - current.width) > WindowClamp.tolerance {
            AX.setSize(window, target.size)
        }
        AX.setPosition(window, target.origin)
    }

    // MARK: - Vollbild

    private func scheduleFullscreenChecks() {
        for work in fullscreenWork { work.cancel() }
        fullscreenWork = Self.fullscreenChecks.map { delay in
            let work = DispatchWorkItem { [self] in refreshFullscreen() }
            queue.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    /// Auf welchem Bildschirm ist das Fokus-Fenster der Vordergrund-App im
    /// Vollbild? Bei Unklarheit den alten Stand behalten statt raten: eine
    /// kurz nicht antwortende App soll die Leiste nicht aufblitzen lassen.
    ///
    /// Gefragt wird nur die Vordergrund-App, denn nur sie sagt etwas darueber,
    /// was der Nutzer gerade sieht. Liegt auf einem zweiten Bildschirm ein
    /// Vollbild-Fenster, waehrend vorne eine App auf einem anderen Bildschirm
    /// steht, gilt dort also kein Vollbild und jene Leiste kommt zurueck.
    private func refreshFullscreen() {
        guard running, let pid = frontmostPID else { return }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        switch status {
        case .success:
            break
        case .noValue, .attributeUnsupported:
            // App ohne Fenster (etwa der Finder auf leerem Schreibtisch).
            publishFullscreen([])
            return
        default:
            return
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return }
        let window = unsafeDowncast(value, to: AXUIElement.self)

        guard AX.bool(window, AX.fullScreenAttribute) == true else {
            publishFullscreen([])
            return
        }
        // Welcher Bildschirm: der, auf dem der groesste Teil des Fensters
        // liegt. Laesst sich das gerade nicht sagen, bleibt der alte Stand.
        guard let frame = AX.frame(of: window),
              let index = WindowClamp.dominantScreen(for: frame, among: screens.map(\.frame))
        else { return }
        publishFullscreen([screens[index].key])
    }

    private func publishFullscreen(_ value: Set<String>) {
        guard value != fullscreenKeys else { return }
        fullscreenKeys = value
        log.notice("Vollbild auf \(value.count, privacy: .public) Bildschirm(en)")
        onFullscreen(value)
    }
}

/// Eine beobachtete App. Lebt nur auf der Queue des Workers.
private final class ObservedApp {
    let element: AXUIElement
    let observer: AXObserver
    /// Fenster, fuer die "bewegt"/"Groesse" schon angemeldet sind.
    var windows: Set<AXUIElement> = []

    init(element: AXUIElement, observer: AXObserver) {
        self.element = element
        self.observer = observer
    }
}

/// Traeger, um ein AXUIElement vom Callback auf die Queue zu reichen.
/// Unbedenklich: ein AXUIElement ist ein unveraenderlicher Verweis (Prozess
/// plus Element-Kennung), die AX-Funktionen darf man von jedem Thread aus
/// aufrufen. Swift kennt dafuer nur kein `Sendable`.
private struct AXElementRef: @unchecked Sendable {
    let element: AXUIElement
}

/// Duenne Huelle um die C-Schnittstelle der Bedienungshilfen.
private enum AX {
    /// Keine oeffentlichen Konstanten dafuer, die Namen sind aber seit Jahren
    /// stabil und werden von allen Fenster-Tools so benutzt.
    static let fullScreenAttribute = "AXFullScreen"
    static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"

    static func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copy(element, attribute) as? Bool
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (copy(element, attribute) as? [AXUIElement]) ?? []
    }

    /// Rahmen in Bedienungshilfen-Koordinaten: Position ist die linke obere
    /// Ecke, gemessen ab der linken oberen Ecke des Hauptbildschirms.
    static func frame(of window: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = axValue(window, kAXPositionAttribute),
              let extent = axValue(window, kAXSizeAttribute),
              AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(extent, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
            && settable.boolValue
    }

    @discardableResult
    static func setPosition(_ window: AXUIElement, _ point: CGPoint) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    @discardableResult
    static func setSize(_ window: AXUIElement, _ size: CGSize) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    @discardableResult
    static func setBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, (value ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
    }
}
