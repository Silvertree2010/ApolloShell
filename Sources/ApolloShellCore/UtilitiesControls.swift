import Foundation

/// Farbe als "#RRGGBB" fuer die Farbpipette im Utilities-Panel.
///
/// Grossbuchstaben wie in Figma und den Apple-Farbwaehlern - so sieht er
/// Hexwerte im Alltag. Werte ausserhalb 0...1 (erweiterte sRGB-Farben aus
/// P3-Bildschirmen) werden abgeschnitten statt ueberzulaufen: "#FFFFFF" ist
/// naeher an der Wahrheit als ein Zahlenfehler.
public enum UtilitiesColorHex {
    public static func hex(red: Double, green: Double, blue: Double) -> String {
        String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    private static func byte(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int((min(max(value, 0), 1) * 255).rounded())
    }
}

extension ToastText {
    /// Nach der Farbpipette: der Wert liegt schon in der Zwischenablage.
    public static func colorCopied(_ hex: String) -> Content {
        Content(title: String(localized: "Farbe kopiert"), message: hex, symbol: "eyedropper", kind: .info)
    }
}

// MARK: - Audiogeraete

/// Ausgabe oder Eingang.
public enum UtilitiesAudioScope: Sendable, Equatable {
    case output
    case input
}

/// Ein CoreAudio-Geraet, so wie es die Oberflaeche braucht. Die App liest
/// die Werte aus CoreAudio, die Auswahl (was kommt in welches Menue) ist
/// hier - damit sie testbar ist.
public struct UtilitiesAudioDevice: Equatable, Sendable, Identifiable {
    public var id: UInt32
    public var name: String
    public var outputStreams: Int
    public var inputStreams: Int
    /// `kAudioDevicePropertyDeviceCanBeDefaultDevice` je Richtung: Apple
    /// blendet Geraete ohne diese Eigenschaft in den Toneinstellungen aus.
    public var canBeDefaultOutput: Bool
    public var canBeDefaultInput: Bool
    public var hidden: Bool

    public init(id: UInt32, name: String, outputStreams: Int, inputStreams: Int,
                canBeDefaultOutput: Bool, canBeDefaultInput: Bool, hidden: Bool) {
        self.id = id
        self.name = name
        self.outputStreams = outputStreams
        self.inputStreams = inputStreams
        self.canBeDefaultOutput = canBeDefaultOutput
        self.canBeDefaultInput = canBeDefaultInput
        self.hidden = hidden
    }
}

public enum UtilitiesAudioDevices {
    /// Was im Menue fuer diese Richtung steht: mindestens ein Strom in der
    /// Richtung, als Standard waehlbar, nicht versteckt (versteckt sind z. B.
    /// Aggregat-Geraete, die Apps fuer sich anlegen).
    ///
    /// Gemessen 14.09.: AirPods Pro melden sich als zwei Geraete gleichen
    /// Namens (1 Ausgabestrom / 1 Eingangsstrom) - erst die Stromzahl trennt
    /// sie. Das iPhone-Mikrofon (Continuity) hat nur einen Eingang.
    ///
    /// Nach Namen sortiert: die Reihenfolge von CoreAudio aendert sich, wenn
    /// Geraete kommen und gehen; das Menue soll ruhig bleiben.
    public static func devices(_ all: [UtilitiesAudioDevice], for scope: UtilitiesAudioScope) -> [UtilitiesAudioDevice] {
        all.filter { device in
            guard !device.hidden else { return false }
            switch scope {
            case .output: return device.outputStreams > 0 && device.canBeDefaultOutput
            case .input: return device.inputStreams > 0 && device.canBeDefaultInput
            }
        }
        .sorted { a, b in
            let order = a.name.localizedStandardCompare(b.name)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }

    /// Name des Standardgeraets fuer die Knopfbeschriftung. Gesucht in
    /// allen Geraeten, nicht nur den gefilterten: ist ein verstecktes Geraet
    /// Standard (kommt bei Konferenz-Apps vor), soll trotzdem sein Name dort
    /// stehen, nicht "Kein Gerät".
    public static func label(defaultID: UInt32?, in all: [UtilitiesAudioDevice]) -> String {
        guard let defaultID, let device = all.first(where: { $0.id == defaultID }) else {
            return UtilitiesAudioText.noDevice
        }
        return displayName(device.name)
    }

    /// Menuezeile: leerer Name wie bei den Kurzmeldungen "Unbekanntes Gerät".
    public static func displayName(_ name: String) -> String {
        ToastText.deviceName(name)
    }
}

/// Texte der Ton-Karte.
public enum UtilitiesAudioText {
    public static let title = String(localized: "Ton")
    public static let output = String(localized: "Ausgabe")
    public static let input = String(localized: "Eingang")
    public static let noDevice = String(localized: "Kein Gerät")
    public static let noDevicesInMenu = String(localized: "Keine Geräte")

    /// "45 %" (Schweizer und deutsche Schreibweise mit Leerschlag), stumm
    /// "Stumm" - eine Null wuerde wie ein Fehler aussehen.
    public static func level(volume: Float, muted: Bool) -> String {
        muted ? String(localized: "Stumm") : String(localized: "\(VolumeGlyphs.percent(volume)) %")
    }

    public static func muteHelp(muted: Bool) -> String {
        muted ? String(localized: "Ton einschalten") : String(localized: "Ton stummschalten")
    }
}

// MARK: - Tastenkuerzel

/// Eine Taste mit Modifiern, wie sie macOS in com.apple.symbolichotkeys
/// ablegt: `parameters = (ASCII, Tastencode, Modifier-Maske)`.
///
/// Die Maske benutzt dieselben Bits wie `CGEventFlags` (⇧ 0x20000,
/// ⌃ 0x40000, ⌥ 0x80000, ⌘ 0x100000, Fn 0x800000) - die App kann sie also
/// unveraendert an den Tastendruck haengen. Genau so posten, wie es dort
/// steht: "Schreibtisch anzeigen" ist dort F11 OHNE Fn-Bit (gemessen
/// 14.09.: 65535, 103, 0), die Pfeile fuer die Spaces dagegen MIT.
public struct UtilitiesHotKey: Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64

    /// Nur die geraeteunabhaengigen Modifier-Bits; der Rest der Maske
    /// (links/rechts, Caps Lock) gehoert nicht in einen geposteten Druck.
    public static let modifierMask: UInt64 = 0x00FF_0000
    /// 65535 = "keine Taste" in symbolichotkeys.
    public static let noKey = 65535

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Mission Control "Schreibtisch anzeigen".
    public static let showDesktopID = 36
    /// "Bildschirmfoto- und Aufnahmeoptionen" (⌘⇧5).
    public static let screenshotToolbarID = 184

    /// Werte, wenn der Eintrag fehlt (dann gilt der macOS-Standard). Beide
    /// gemessen und gleich dem Standard: F11, ⌘⇧5.
    public static let showDesktopDefault = UtilitiesHotKey(keyCode: 103, modifiers: 0)
    public static let screenshotToolbarDefault = UtilitiesHotKey(keyCode: 23, modifiers: 0x12_0000)

    /// "Bildschirm sperren" im Apple-Menue, ⌃⌘Q. Kein symbolischer
    /// Hotkey, sondern ein Menuebefehl - steht deshalb fest.
    public static let lockScreen = UtilitiesHotKey(keyCode: 12, modifiers: 0x14_0000)

    /// Aus einem symbolichotkeys-Eintrag die Taste, die man posten muss.
    /// - Eintrag fehlt ganz (`enabled` und `parameters` nil): macOS-Standard.
    /// - abgeschaltet: `nil` - dann gibt es nichts zu druecken.
    /// - an, aber ohne brauchbare Werte: Standard.
    /// - Tastencode 65535: an, aber keine Taste belegt - `nil`.
    public static func resolve(enabled: Bool?, parameters: [Int]?, fallback: UtilitiesHotKey) -> UtilitiesHotKey? {
        if enabled == false { return nil }
        guard let parameters, parameters.count >= 3 else { return fallback }
        let code = parameters[1]
        guard code >= 0, code < noKey else { return nil }
        let mask = UInt64(max(parameters[2], 0)) & modifierMask
        return UtilitiesHotKey(keyCode: UInt16(code), modifiers: mask)
    }
}

// MARK: - Night Shift

/// Liest den Zustand aus CoreBrightness' `getBlueLightStatus:`. Das ist ein
/// privates C-Struct; Aufbau wie in den quelloffenen Werkzeugen (nightlight,
/// Shifty): active, enabled, sunSchedulePermitted (je 1 Byte), mode (Int32
/// ab 4), Zeitplan (4 x Int32 ab 8), disableFlags (UInt64 ab 24),
/// available (1 Byte ab 32) - 40 Bytes mit Ausrichtung.
///
/// Gemessen 14.09. um 16 Uhr (Zeitplan 22-7 gespeichert, aber aus):
/// Byte 0 = 1, Byte 1 = 0, Bytes 8/16 = 22/7, Byte 32 = 1. "enabled" (Byte 1)
/// ist also der Schalter, den Apples Kontrollzentrum zeigt; Byte 0 bleibt
/// auch bei ausgeschaltetem Night Shift 1.
public enum UtilitiesNightShiftStatus {
    /// So viel Platz bekommt der Aufruf - mehr als die 40 Bytes, falls ein
    /// kuenftiges macOS das Struct verlaengert. Zu wenig waere ein
    /// Speicherfehler, zu viel kostet nichts.
    public static let bufferSize = 64
    static let enabledOffset = 1
    static let availableOffset = 32

    /// `nil`: der Bildschirm kann kein Night Shift (oder der Puffer ist zu
    /// kurz) - dann bleibt der Knopf aus.
    public static func enabled(fromStatus bytes: [UInt8]) -> Bool? {
        guard bytes.count > availableOffset, bytes[availableOffset] != 0 else { return nil }
        return bytes[enabledOffset] != 0
    }
}
