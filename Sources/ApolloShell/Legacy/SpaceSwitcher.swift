import AppKit
import CoreGraphics

/// Wechselt Schreibtische wie ⌃← / ⌃→ (Mission Control "Einen Space nach
/// links/rechts", standardmaessig aktiv - gemessen 14.09. in
/// com.apple.symbolichotkeys 79/81).
///
/// macOS hat dafuer keine oeffentliche Schnittstelle; die private
/// (CGSManagedDisplaySetCurrentSpace) schaltet nur die Anzeige um, nicht die
/// Fenster. Der Tastendruck ist genau das, was Mission Control erwartet:
/// ⌃ plus Pfeil, mit dem Fn-Flag, das echte Pfeiltasten tragen (die
/// Tastenbelegung steht dort als 0x840000 = ⌃ | Fn). Tastendruecke posten
/// braucht die Bedienungshilfen-Freigabe, die der Launcher hat. Karabiner
/// sieht sie nicht (er sitzt vor dem System, nicht dahinter).
///
/// Die Punkte zaehlen nur Schreibtische. Liegen Vollbild-Spaces dazwischen,
/// zaehlt ⌃→ sie mit, und ein Sprung landet zu kurz - dann nochmal klicken.
@MainActor
enum SpaceSwitcher {
    private static let left: CGKeyCode = 123
    private static let right: CGKeyCode = 124
    /// Abstand zwischen mehreren Schritten: jeder startet seine eigene
    /// Wisch-Animation; zu dicht hintereinander verschluckt macOS welche.
    private static let stepDelay: TimeInterval = 0.12

    /// `delta` Schreibtische weiter (negativ = nach links).
    static func step(_ delta: Int) {
        guard delta != 0, AXIsProcessTrusted() else { return }
        let key = delta > 0 ? right : left
        for index in 0..<abs(delta) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * stepDelay) {
                post(key)
            }
        }
    }

    /// "Show All Windows" aus Apples Dock-Menue: App-Exposé, also ⌃↓
    /// (Mission Control "Programmfenster", standardmaessig aktiv - symbolichotkeys 33)
    /// fuer die App, die gerade vorne ist. Deshalb erst die App nach vorne,
    /// kurz warten, dann die Taste.
    static func showAppWindows(of app: NSRunningApplication) {
        guard AXIsProcessTrusted() else { return }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            post(125)
        }
    }

    nonisolated private static func post(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = [.maskControl, .maskSecondaryFn]
            event?.post(tap: .cghidEventTap)
        }
    }
}
