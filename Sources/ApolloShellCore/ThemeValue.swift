import Foundation

/// Eine Farbe aus einem Theme: sRGB-Anteile und Deckkraft, jeweils 0...1.
///
/// Eigener Typ statt NSColor/Color, weil der Kern ohne Oberflaeche baut und
/// weil Werte aus fremden Dateien geklemmt sein muessen, bevor sie irgendwo
/// ankommen: `init` faengt NaN, Unendlich und Werte ausserhalb 0...1 ab.
public struct ThemeColor: Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = ThemeColor.unit(red)
        self.green = ThemeColor.unit(green)
        self.blue = ThemeColor.unit(blue)
        self.alpha = ThemeColor.unit(alpha)
    }

    /// 0xRRGGBB - die Schreibweise der Vorgaben im Token-Verzeichnis.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    /// NaN und Unendlich gibt es in einer Farbe nicht: sie wuerden spaeter in
    /// CoreGraphics landen und dort Flaechen verschwinden lassen.
    ///
    /// Zusaetzlich auf 8 Bit gerundet - genau so steht eine Farbe auch in der
    /// Datei. Damit ist Schreiben und wieder Lesen dieselbe Farbe, und
    /// `cssText` ist keine Naeherung, sondern der Wert selbst.
    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(max(value, 0), 1) * 255).rounded() / 255
    }

    public static let black = ThemeColor(hex: 0x000000)
    public static let white = ThemeColor(hex: 0xFFFFFF)
    public static let clear = ThemeColor(red: 0, green: 0, blue: 0, alpha: 0)

    /// `#rrggbb`, mit Deckkraft `#rrggbbaa`. Diese Schreibweise steht in der
    /// Doku und in den Beispiel-Themes - sie laesst sich wieder einlesen.
    public var cssText: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        let rgb = String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
        return alpha >= 1 ? rgb : rgb + String(format: "%02x", byte(alpha))
    }

    /// Relative Helligkeit nach WCAG - dieselbe Rechnung wie fuer die
    /// Schriftfarbe auf Akzentflaechen.
    public var luminance: Double {
        AccentContrast.luminance(red: red, green: green, blue: blue)
    }

    /// Kontrastverhaeltnis nach WCAG, 1...21. Beide Farben sollten deckend
    /// sein; sonst vorher `composited(over:)`.
    public static func contrast(_ one: ThemeColor, _ other: ThemeColor) -> Double {
        let a = one.luminance
        let b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Diese Farbe mit ihrer Deckkraft ueber eine (deckende) Flaeche gelegt.
    public func composited(over background: ThemeColor) -> ThemeColor {
        guard alpha < 1 else { return self }
        func mix(_ top: Double, _ bottom: Double) -> Double { top * alpha + bottom * (1 - alpha) }
        return ThemeColor(red: mix(red, background.red),
                          green: mix(green, background.green),
                          blue: mix(blue, background.blue),
                          alpha: 1)
    }

    /// Linear in Richtung `other` verschoben, Deckkraft bleibt. `amount` 0...1.
    public func blended(with other: ThemeColor, amount: Double) -> ThemeColor {
        let t = ThemeColor.unit(amount)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return ThemeColor(red: mix(red, other.red),
                          green: mix(green, other.green),
                          blue: mix(blue, other.blue),
                          alpha: alpha)
    }

    /// Mit anderer Deckkraft.
    public func withAlpha(_ value: Double) -> ThemeColor {
        ThemeColor(red: red, green: green, blue: blue, alpha: value)
    }
}

/// Einheit einer Zahl im Theme. `px` und `pt` sind fuer uns dasselbe: die
/// Shell rechnet in Punkten, und ein Theme soll nicht wissen muessen, auf
/// welchem Bildschirm es landet.
public enum ThemeUnit: String, Equatable, Hashable, Sendable, CaseIterable {
    /// Laenge in Punkten - `12px`, `12pt` oder `12`.
    case points
    /// Anteil 0...1 - `0.5` oder `50%`.
    case ratio
    /// Blosse Zahl ohne Einheit - `400`.
    case scalar

    /// Wie eine Zahl dieser Einheit geschrieben wird (Doku, Beispiele).
    public func cssText(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        // Ganze Zahlen ohne ".0" - aber nur, solange sie in Int passen. Ein
        // Theme darf beliebig grosse Zahlen hineinschreiben, und die
        // landen hier im Hinweis, bevor sie geklemmt werden.
        let digits = rounded.isFinite && rounded == rounded.rounded() && rounded.magnitude < 1e15
            ? String(Int(rounded))
            : String(rounded.isFinite ? rounded : value)
        return self == .points ? digits + "px" : digits
    }
}

/// Eine Datei aus dem Theme-Ordner. `url` ist `nil`, solange nichts geprueft
/// wurde oder die Pruefung fehlschlug - dann gilt die Vorgabe (kein Bild).
public struct ThemeAsset: Equatable, Hashable, Sendable {
    /// Wie es im Theme steht, nur zum Anzeigen und fuer Fehlermeldungen.
    public let reference: String
    /// Die gepruefte Datei: existiert, liegt im Theme-Ordner, ist nicht zu gross.
    public let url: URL?

    public init(reference: String, url: URL?) {
        self.reference = reference
        self.url = url
    }

    public static let none = ThemeAsset(reference: "", url: nil)
}

/// Ein Farbverlauf aus einem Theme.
///
/// Ein Verlauf ist immer geradlinig (`linear-gradient`): Das genuegt fuer
/// Flaechen einer Shell, und was es nicht gibt, kann auch nicht kaputtgehen.
/// `none` - also kein Verlauf - ist der Normalfall; dann faerbt die
/// zugehoerige Farbe die Flaeche wie bisher.
///
/// Der Winkel folgt CSS: 0 Grad zeigt nach oben, 90 Grad nach rechts.
public struct ThemeGradient: Equatable, Hashable, Sendable {
    /// Eine Farbe an einer Stelle des Verlaufs, 0...1.
    public struct Stop: Equatable, Hashable, Sendable {
        public let color: ThemeColor
        public let position: Double

        public init(color: ThemeColor, position: Double) {
            self.color = color
            self.position = position.isFinite ? min(max(position, 0), 1) : 0
        }
    }

    /// Hoechstens so viele Farbstellen. Mehr braucht keine Flaeche, und die
    /// Grenze haelt eine Datei davon ab, das Zeichnen lahmzulegen.
    public static let maximumStops = 8

    public let angle: Double
    public let stops: [Stop]

    public init(angle: Double = 180, stops: [Stop]) {
        self.angle = angle.isFinite ? angle.truncatingRemainder(dividingBy: 360) : 180
        self.stops = Array(stops.prefix(ThemeGradient.maximumStops))
    }

    /// Kein Verlauf. Dann gilt die Farbe des Tokens daneben.
    public static let none = ThemeGradient(stops: [])

    /// Ein Verlauf braucht mindestens zwei Farben; alles andere ist keiner.
    public var isEmpty: Bool { stops.count < 2 }

    /// `none` oder `linear-gradient(180deg, #111111 0%, #333333 100%)`.
    public var cssText: String {
        guard !isEmpty else { return "none" }
        let parts = stops.map { stop in
            "\(stop.color.cssText) \(Int((stop.position * 100).rounded()))%"
        }
        return "linear-gradient(\(ThemeUnit.scalar.cssText(angle))deg, \(parts.joined(separator: ", ")))"
    }
}

/// Der Wert eines Tokens, schon geprueft und in der Einheit des Tokens.
public enum ThemeValue: Equatable, Hashable, Sendable {
    case color(ThemeColor)
    case gradient(ThemeGradient)
    case number(Double)
    case text(String)
    case file(ThemeAsset)
    case option(String)
    case flag(Bool)

    public var color: ThemeColor? { if case let .color(value) = self { value } else { nil } }
    public var gradient: ThemeGradient? { if case let .gradient(value) = self { value } else { nil } }
    public var number: Double? { if case let .number(value) = self { value } else { nil } }
    public var text: String? { if case let .text(value) = self { value } else { nil } }
    public var asset: ThemeAsset? { if case let .file(value) = self { value } else { nil } }
    public var option: String? { if case let .option(value) = self { value } else { nil } }
    public var flag: Bool? { if case let .flag(value) = self { value } else { nil } }
}
