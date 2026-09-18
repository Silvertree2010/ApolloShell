import Foundation

// Gemeinsames nachsichtiges Lesen fuer die Einstellungsdateien: fehlt ein
// Schluessel oder hat er den falschen Typ, gilt die Vorgabe statt eines
// Fehlers - fuer einzelne Felder (`lenient(_:)`) genauso wie fuer ganze
// Listen (`LenientList`), aus denen nur die unlesbaren Eintraege wegfallen.
// Bisher gab es das fuenfmal wortgleich (BarLayout, DashboardLayout,
// ShellSettings, UpdateSettings, UtilitiesLayout) - jetzt an einer Stelle.

public extension KeyedDecodingContainer {
    /// Fehlt der Schluessel oder passt der Typ nicht: `nil` statt Fehler.
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Wie `lenient(_:)`, aber schreibt direkt in ein Feld, das `init()`
    /// schon mit der Vorgabe belegt hat - so steht jede Vorgabe nur einmal:
    ///
    ///     self.init()
    ///     let c = try decoder.container(keyedBy: CodingKeys.self)
    ///     c.lenient(.showRunning, into: &showRunning)
    ///
    /// Schreibt in den Speicher des Feldes, ohne `willSet`/`didSet`
    /// auszuloesen (Eigenart von `inout`) - ein Feld mit eigenem `didSet`
    /// (z. B. Klemmung wie `BarGapOptions.height`) braucht darum weiter
    /// seine eigene Zeile statt `into:`.
    func lenient<T: Decodable>(_ key: Key, into target: inout T) {
        if let value: T = lenient(key) { target = value }
    }
}

/// Liest ein einzelnes Element und scheitert nie: unlesbar ergibt `nil`. So
/// rueckt der Zeiger einer Liste immer weiter, und ein kaputter Eintrag
/// nimmt nicht die ganze Liste mit.
struct LenientElement<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) {
        value = try? T(from: decoder)
    }
}

/// Eine Liste, aus der unlesbare Eintraege wegfallen. Scheitert nur, wenn
/// das JSON gar keine Liste ist.
public struct LenientList<Element: Decodable>: Decodable {
    public let values: [Element]

    public init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var list: [Element] = []
        while !c.isAtEnd {
            // `LenientElement` scheitert nie, der Zeiger rueckt also immer
            // weiter. Falls doch (ein Decoder, der das anders haelt):
            // abbrechen statt endlos auf derselben Stelle zu stehen.
            guard let item = try? c.decode(LenientElement<Element>.self) else { break }
            if let value = item.value { list.append(value) }
        }
        values = list
    }
}

/// Ein `Encodable` ohne festen Typ, fuer Optionen, deren Art erst zur
/// Laufzeit feststeht (`BlockModule.options`).
struct AnyEncodable: Encodable {
    let value: any Encodable
    func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }
}
