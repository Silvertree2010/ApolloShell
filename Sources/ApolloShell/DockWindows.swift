import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
import SwiftUI

/// Fenster einer App ueber die Bedienungshilfen (die Freigabe hat die App
/// fuer die Fensterwache). Ohne Freigabe: leere Liste, das Menue hat dann
/// nur die Befehle.
enum DockWindows {
    struct Window {
        let title: String
        let minimized: Bool
        let element: AXUIElement
        /// Fuer den Abgleich mit `onScreenWindowIDs` (welche Fenster gerade
        /// auf dem aktuellen Space sichtbar sind). `nil`, wenn die private
        /// Funktion dahinter fehlt - dann zaehlt das Fenster bei "hier vs.
        /// woanders" nirgends, und der normale Weg (App aktivieren, macOS
        /// wechselt selbst) greift.
        let windowID: CGWindowID?
    }

    /// `allSpaces`: auch Fenster auf anderen Schreibtischen (fuers Menue).
    /// Ohne: nur der aktuelle, vorne nach hinten sortiert (fuers Durchschalten).
    @MainActor
    static func list(pid: pid_t, allSpaces: Bool = false) -> [Window] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        // Haengt die App, soll das Menue nicht mit ihr haengen.
        AXUIElementSetMessagingTimeout(app, 0.3)
        var elements = AX.elements(app, kAXWindowsAttribute)
        if allSpaces {
            for element in RemoteWindows.all(pid: pid) where !elements.contains(where: { CFEqual($0, element) }) {
                elements.append(element)
            }
        }
        return elements.compactMap { element in
            // Nur echte Fenster, keine Paletten/Blaetter.
            guard AX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole as String else { return nil }
            return Window(title: AX.string(element, kAXTitleAttribute) ?? "",
                          minimized: (AX.copy(element, kAXMinimizedAttribute) as? NSNumber)?.boolValue ?? false,
                          element: element,
                          windowID: AXWindowID.of(element))
        }
    }

    /// Wie ein Klick auf das Fenster im Dock-Menue: aus dem Dock holen, falls
    /// minimiert, zum Hauptfenster machen und nach oben, dann die App nach
    /// vorne. In dieser Reihenfolge wechselt macOS dabei auf den
    /// Schreibtisch dieses Fensters (vorne ist dann genau dieses).
    @MainActor
    static func raise(_ window: Window, of app: NSRunningApplication) {
        if window.minimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        // Reihenfolge ist entscheidend (gemessen 16.09.): Erst dieses Fenster
        // zum Hauptfenster machen und heben, DANN die App nach vorne. Andersherum
        // sucht macOS beim Nachvornholen selbst ein Fenster aus - das zuletzt
        // benutzte - und wechselt dafuer auf dessen Schreibtisch, obwohl hier
        // eins liegt. Nach vorne ueber die Bedienungshilfen, nicht ueber
        // `activate()`: das waehlt ebenfalls selbst aus.
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        let frontmost = AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        // Ohne Bedienungshilfen bleibt nur der alte Weg.
        if frontmost != .success { app.activate() }
    }

    /// Nummern aller Fenster der App, die auf einem Schreibtisch liegen,
    /// auch auf anderen, dazu die im Dock abgelegten. `kAXWindowsAttribute`
    /// kennt nur den aktuellen Schreibtisch (gemessen: 2 von 21 Nummern),
    /// deshalb kommt die Antwort auf "hat sie woanders Fenster?" aus der
    /// Fensterliste des Systems. Gefiltert auf echte Fenster: Ebene 0 und
    /// mindestens 100 x 100 Punkte, damit Schatten, Hilfsflaechen und Menues
    /// wegfallen.
    ///
    /// Die Liste enthaelt auch Fenster, die eine App nach dem Schliessen nur
    /// im Speicher behaelt (gemessen: 3 von 4 bei einem Dateimanager). Die
    /// liegen auf keinem Space und fallen hier weg, sonst oeffnete ein Klick
    /// auf eine App ohne sichtbares Fenster kein neues.
    ///
    /// `requireSpace: false` fuer ausgeblendete Apps: ob deren Fenster
    /// waehrenddessen auf einem Space liegen, ist nicht gemessen. Fielen sie
    /// weg, oeffnete ein Klick zusaetzlich zum Einblenden ein neues Fenster.
    @MainActor
    static func allWindowIDs(pid: pid_t, requireSpace: Bool = true) -> Set<CGWindowID> {
        guard let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids: Set<CGWindowID> = []
        for entry in info {
            guard let owner = entry[kCGWindowOwnerPID as String] as? Int, pid_t(owner) == pid,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
                  width >= 100, height >= 100
            else { continue }
            ids.insert(CGWindowID(number))
        }
        guard requireSpace, let reader = spaceReader else { return ids }
        return ids.filter { reader.isOnAnySpace($0) != false }
    }

    @MainActor private static let spaceReader = SpaceReader()

    /// Fensternummern, die gerade sichtbar sind - nicht minimiert und auf dem
    /// aktuellen Space (`CGWindowListCopyWindowInfo` liefert nur, was der
    /// Bildschirm gerade zeigt). Damit unterscheidet der Dock-Klick "Fenster
    /// hier" von "Fenster woanders" (Nachbesserung 16.09.: sonst sprang ein
    /// Klick auf den Space eines anderen Fensters, obwohl eins hier lag -
    /// Apples Dock bleibt in dem Fall da).
    @MainActor
    static func onScreenWindowIDs(pid: pid_t) -> Set<CGWindowID> {
        guard let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids: Set<CGWindowID> = []
        for entry in info {
            guard let owner = entry[kCGWindowOwnerPID as String] as? Int, pid_t(owner) == pid,
                  let number = entry[kCGWindowNumber as String] as? Int
            else { continue }
            ids.insert(CGWindowID(number))
        }
        return ids
    }

    /// Vorderstes Fenster der App auf dem Bildschirm unter der Maus (dort,
    /// wo geklickt wurde - so braucht es keine Durchreichung, welcher
    /// Bildschirm das ist, durch die Ansichten), das dort von einem fremden
    /// Fenster verdeckt liegt (`DockWindowCover`). `nil`: nichts verdeckt,
    /// auch bei nur einem Fenster oder mehreren frei nebeneinander.
    @MainActor
    static func coveredWindowID(pid: pid_t) -> CGWindowID? {
        guard let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        else { return nil }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        let windows: [DockScreenWindow] = info.compactMap { entry in
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? Int,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double
            else { return nil }
            // CGWindowListCopyWindowInfo zaehlt von oben links nach unten,
            // NSScreen von unten links nach oben (Apple-Standard) - nur fuers
            // Zuordnen zum Bildschirm unter der Maus noetig, die Ueberlappung
            // selbst rechnet unabhaengig vom Koordinatensystem.
            let cocoaCenter = CGPoint(x: x + width / 2, y: primaryHeight - y - height / 2)
            guard screen.frame.contains(cocoaCenter) else { return nil }
            let owner: DockScreenWindow.Owner = pid_t(ownerPID) == pid ? .target : (ownerPID == ownPID ? .ownShell : .other)
            return DockScreenWindow(id: number, owner: owner, layer: layer, x: x, y: y, width: width, height: height)
        }
        return DockWindowCover.nextCovered(in: windows).map(CGWindowID.init)
    }
}

/// Fensternummer (`CGWindowID`) einer Bedienungshilfen-Referenz - private
/// Funktion, wie schon bei `RemoteWindows` fuer den umgekehrten Weg genutzt
/// (etwa von AltTab, yabai). Damit lassen sich AX-Fenster mit
/// `CGWindowListCopyWindowInfo` abgleichen, die keine AX-Elemente kennt.
private enum AXWindowID {
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    /// RTLD_DEFAULT ist auf macOS der Zeiger -2.
    private static let getWindow: GetWindow? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindow.self)
    }()

    static func of(_ element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        return getWindow(element, &id) == .success ? id : nil
    }
}

/// Fenster auf anderen Schreibtischen. `kAXWindowsAttribute` liefert nur die
/// des aktuellen. Der Weg von AltTab: Bedienungshilfen-Elemente ueber ihre
/// Nummer direkt erzeugen (private Funktion `_AXUIElementCreateWithRemoteToken`
/// in HIServices, per dlsym) und die Nummern 0 bis 999 durchprobieren.
/// Gemessen 14.09.: kitty 3 Fenster statt 2 in 46 ms, Vivaldi 16 ms - kurz
/// genug, um es beim Oeffnen des Menues zu tun.
enum RemoteWindows {
    private typealias Create = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    /// RTLD_DEFAULT ist auf macOS der Zeiger -2.
    private static let create: Create? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken") else { return nil }
        return unsafeBitCast(symbol, to: Create.self)
    }()
    private static let maxElementID: UInt64 = 1000

    @MainActor
    static func all(pid: pid_t) -> [AXUIElement] {
        guard let create else { return [] }
        // Aufbau des Tokens (AltTab): pid, 0, "coco", Elementnummer.
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        var windows: [AXUIElement] = []
        for elementID in 0..<maxElementID {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = create(token as CFData)?.takeRetainedValue(),
                  AX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole as String
            else { continue }
            windows.append(element)
        }
        return windows
    }
}
