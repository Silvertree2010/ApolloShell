import Foundation

/// Texte der Karte "Keep Awake" im Utilities-Panel (Caelestia: IdleInhibit).
public enum KeepAwakeText {
    public static let title = String(localized: "Keep Awake")
    public static let inactive = String(localized: "Mac sleeps normally")

    /// "Aktiv seit 14:30". Laeuft es seit gestern oder laenger, gehoert der
    /// Tag dazu - sonst liest man am Morgen "seit 23:10" als "heute Abend".
    ///
    /// Feste 24-Stunden-Schreibweise statt DateFormatter mit Locale: auf
    /// Deutsch ohnehin ueblich, und so ist das Ergebnis testbar gleich.
    /// `lidClosed`: gilt auch bei zugeklapptem Deckel (`LidAwake`) - das soll
    /// man sehen, weil es den Mac in der Tasche wach laesst.
    public static func subtitle(since: Date?, now: Date, lidClosed: Bool = false, calendar: Calendar = .current) -> String {
        subtitle(since: since, now: now, lid: lidClosed ? .on : .off, calendar: calendar)
    }

    /// Mit dem Stand des Deckel-Teils: auch sagen, wenn er fehlt, obwohl er
    /// eingestellt ist (Administrator abgelehnt) - sonst klappte man den Mac
    /// im Glauben zu, er bleibe wach.
    public static func subtitle(since: Date?, now: Date, lid: KeepAwakeLid, calendar: Calendar = .current) -> String {
        guard let since else { return inactive }
        let base = plainSubtitle(since: since, now: now, calendar: calendar)
        switch lid {
        case .off: return base
        case .on: return base + String(localized: " · also with lid closed")
        case .pending: return base + String(localized: " · waiting for approval")
        case .declined: return base + String(localized: " · only with lid open")
        }
    }

    private static func plainSubtitle(since: Date, now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.day, .month, .hour, .minute], from: since)
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        if calendar.isDate(since, inSameDayAs: now) {
            return String(localized: "Active since \(time)")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(since, inSameDayAs: yesterday) {
            return String(localized: "Active since yesterday, \(time)")
        }
        return String(localized: "Active since \(String(format: "%02d.%02d.", c.day ?? 0, c.month ?? 0)), ") + time
    }
}

/// Was ein Schnellschalter zeigt: Symbol, ob er leuchtet (Akzentfarbe),
/// ob er klickbar ist, und der Text fuer Tooltip und VoiceOver.
public struct QuickToggleLook: Equatable, Sendable {
    /// SF Symbol. `nil` heisst Bluetooth-Rune: dafuer gibt es kein SF Symbol,
    /// die Oberflaeche zeichnet sie selbst.
    public var symbol: String?
    public var active: Bool
    public var enabled: Bool
    public var help: String

    public init(symbol: String?, active: Bool, enabled: Bool, help: String) {
        self.symbol = symbol
        self.active = active
        self.enabled = enabled
        self.help = help
    }
}

/// Die Schnellschalter des Utilities-Panels (Caelestia: Toggles) und ihre
/// Form. "Leuchtet" heisst wie bei Caelestia immer "ist an" - beim Mikrofon
/// also "nicht stumm" (Caelestia: `checked: !Audio.sourceMuted`), damit die
/// ganze Reihe gleich zu lesen ist.
public enum QuickToggles {
    /// `nil`: kein WLAN-Interface gefunden, dann gibt es nichts zu schalten.
    public static func wifi(powerOn: Bool?) -> QuickToggleLook {
        switch powerOn {
        case true?: QuickToggleLook(symbol: "wifi", active: true, enabled: true, help: String(localized: "Wi-Fi On"))
        case false?: QuickToggleLook(symbol: "wifi.slash", active: false, enabled: true, help: String(localized: "Wi-Fi Off"))
        case nil: QuickToggleLook(symbol: "wifi.slash", active: false, enabled: false, help: String(localized: "No Wi-Fi Found"))
        }
    }

    /// `muted == nil`: kein Eingangsgeraet. `settable == false`: das Geraet
    /// kennt keine (schreibbare) Stummschaltung - anzeigen ja, klicken nein.
    public static func microphone(muted: Bool?, settable: Bool) -> QuickToggleLook {
        guard let muted else {
            return QuickToggleLook(symbol: "mic.slash", active: false, enabled: false, help: String(localized: "No Microphone"))
        }
        let state = muted ? String(localized: "Microphone Muted") : String(localized: "Microphone On")
        return QuickToggleLook(
            symbol: muted ? "mic.slash.fill" : "mic.fill",
            active: !muted,
            enabled: settable,
            help: settable ? state : state + String(localized: " (not switchable)")
        )
    }

    /// Bluetooth zeigt nur an; Schalten geht ohne private Schnittstellen
    /// nicht, deshalb oeffnet der Klick die Bluetooth-Einstellungen.
    public static func bluetooth(powerOn: Bool?) -> QuickToggleLook {
        let state = switch powerOn {
        case true?: String(localized: "Bluetooth On")
        case false?: String(localized: "Bluetooth Off")
        case nil: "Bluetooth"
        }
        return QuickToggleLook(symbol: nil, active: powerOn == true, enabled: true,
                               help: state + String(localized: " – Open Settings"))
    }

    /// Kein Schalter, nur ein Knopf: leuchtet nie. Oeffnet wie bei Caelestia
    /// das eigene Einstellungsfenster (Nexus), nicht die Systemeinstellungen -
    /// die sind von Nexus aus eine Zeile entfernt.
    public static let settings = QuickToggleLook(
        symbol: "gearshape.fill", active: false, enabled: true, help: String(localized: "Settings (SUPER+,)")
    )

    /// Knoepfe pro Reihe. Vorgabe sind zwei Reihen zu fuenf: oben die
    /// Schalter mit Zustand, unten die Aktionen - so liest man die Reihen wie
    /// bei Apples Kontrollzentrum. Wie viele Reihen es werden, bestimmt die
    /// Anordnung in Nexus (`UtilitiesLayout.toggleRows`).
    public static let columns = 5

    /// Leuchtet im Dunkelmodus. `nil`: Zustand nicht lesbar (weder SkyLight
    /// noch die Voreinstellung) - dann nicht klickbar.
    public static func darkMode(on: Bool?) -> QuickToggleLook {
        switch on {
        case true?: QuickToggleLook(symbol: "circle.lefthalf.filled", active: true, enabled: true, help: String(localized: "Dark Mode On"))
        case false?: QuickToggleLook(symbol: "circle.lefthalf.filled", active: false, enabled: true, help: String(localized: "Dark Mode Off"))
        case nil: QuickToggleLook(symbol: "circle.lefthalf.filled", active: false, enabled: false,
                                  help: String(localized: "Dark Mode Unavailable"))
        }
    }

    /// `nil`: dieser Mac bzw. Bildschirm kann kein Night Shift, oder
    /// CoreBrightness antwortet nicht. Der Knopf bleibt dann sichtbar, aber
    /// aus - das Raster behaelt so seine feste Form.
    public static func nightShift(enabled: Bool?) -> QuickToggleLook {
        switch enabled {
        case true?: QuickToggleLook(symbol: "sunset.fill", active: true, enabled: true, help: String(localized: "Night Shift On"))
        case false?: QuickToggleLook(symbol: "sunset.fill", active: false, enabled: true, help: String(localized: "Night Shift Off"))
        case nil: QuickToggleLook(symbol: "sunset.fill", active: false, enabled: false, help: String(localized: "Night Shift Not Available"))
        }
    }

    /// Aktionen leuchten nie, sie haben keinen Zustand.
    public static let screenshot = QuickToggleLook(
        symbol: "camera.viewfinder", active: false, enabled: true, help: String(localized: "Screenshot or Recording (⌘⇧5)")
    )

    /// `available == false`: der Kurzbefehl ist in Mission Control
    /// abgeschaltet - ohne ihn gibt es keinen Weg, also nicht klickbar.
    /// Symbol: Bildschirm mit leerem Schreibtisch. "menubar.dock.rectangle"
    /// las sich in der Bildprobe 14.09. wie eine Kreditkarte.
    public static func showDesktop(available: Bool) -> QuickToggleLook {
        QuickToggleLook(
            symbol: "desktopcomputer", active: false, enabled: available,
            help: available ? String(localized: "Show Desktop") : String(localized: "Show Desktop – shortcut turned off in Mission Control")
        )
    }

    public static let colorPicker = QuickToggleLook(
        symbol: "eyedropper", active: false, enabled: true, help: String(localized: "Color Picker – hex value to the clipboard")
    )

    public static let lockScreen = QuickToggleLook(
        symbol: "lock.fill", active: false, enabled: true, help: String(localized: "Lock Screen (⌃⌘Q)")
    )

    /// Eckenradius wie Caelestias IconButton mit `shapeMorph`: aus ganz rund
    /// (halbe Hoehe), an ein abgerundetes Rechteck mit 12, gedrueckt 8.
    public static func cornerRadius(active: Bool, pressed: Bool, height: Double) -> Double {
        if pressed { return 8 }
        return active ? 12 : height / 2
    }
}
