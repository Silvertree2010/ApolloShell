import Foundation

// Shared lenient reading for the settings files: when a key is missing or has
// the wrong type, the default holds instead of an error - for single fields
// (`lenient(_:)`) just as for whole lists (`LenientList`), out of which only
// the unreadable entries fall away. Until now this existed five times word for
// word (BarLayout, DashboardLayout, ShellSettings, UpdateSettings,
// UtilitiesLayout) - now in one place.

public extension KeyedDecodingContainer {
    /// When the key is missing or the type does not fit: `nil` instead of an error.
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Like `lenient(_:)`, but writes straight into a field `init()` has filled
    /// with the default already - that way every default stands only once:
    ///
    ///     self.init()
    ///     let c = try decoder.container(keyedBy: CodingKeys.self)
    ///     c.lenient(.showRunning, into: &showRunning)
    ///
    /// It writes into the storage of the field without setting off
    /// `willSet`/`didSet` (a quirk of `inout`) - a field with a `didSet` of its
    /// own (clamping like `BarGapOptions.height`, say) therefore still needs
    /// its own line instead of `into:`.
    func lenient<T: Decodable>(_ key: Key, into target: inout T) {
        if let value: T = lenient(key) { target = value }
    }
}

/// Reads a single element and never fails: unreadable gives `nil`. That way
/// the cursor of a list always moves on, and one broken entry does not take
/// the whole list with it.
struct LenientElement<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) {
        value = try? T(from: decoder)
    }
}

/// A list out of which unreadable entries fall away. It only fails when the
/// JSON is no list at all.
public struct LenientList<Element: Decodable>: Decodable {
    public let values: [Element]

    public init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var list: [Element] = []
        while !c.isAtEnd {
            // `LenientElement` never fails, so the cursor always moves on.
            // Should it not (a decoder that handles it differently): stop
            // instead of standing on the same spot forever.
            guard let item = try? c.decode(LenientElement<Element>.self) else { break }
            if let value = item.value { list.append(value) }
        }
        values = list
    }
}

/// An `Encodable` without a fixed type, for options whose kind is only decided
/// at runtime (`BlockModule.options`).
struct AnyEncodable: Encodable {
    let value: any Encodable
    func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }
}
