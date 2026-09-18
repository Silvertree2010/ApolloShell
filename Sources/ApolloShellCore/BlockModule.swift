import Foundation

// Art und Optionen in einem, wie es BarModule, UtilitiesToggle und
// DashboardCard je fuer sich sind: nur Arten mit Optionen tragen welche.
// Das Protokoll haelt fest, was ein Entry (`BarEntry`, `UtilitiesToggleEntry`,
// `DashboardCard`) davon braucht, damit `hasOptions` zu `options != nil`
// wird und der Encode-Switch entfaellt.
//
// Den Decode-Switch teilen sich die drei NICHT woertlich: ihre CodingKeys
// (mit/ohne eigene `id`) und Optionstypen unterscheiden sich, ein generischer
// Decoder ueber alle drei haette mehr Umweg gekostet als er Zeilen spart. Je
// Datei bleibt darum ein eigenes, aber nur noch EIN Switch (statt zwei: einer
// fuer die Vorgaben, einer fuers Lesen) - siehe `make(_:default:wrap:)`.
public protocol BlockModule: Equatable, Sendable {
    associatedtype Kind: Hashable, Sendable

    /// Mit den Vorgaben der Art.
    init(_ kind: Kind)

    var kind: Kind { get }

    /// `nil` bei einer Art ohne Optionen.
    var options: (any Encodable)? { get }
}

public extension BlockModule {
    /// Ob eine Oberflaeche fuer diesen Baustein Optionen aufklappen laesst.
    var hasOptions: Bool { options != nil }

    /// Optionen aus der Datei, sonst die Vorgabe - fuer den einen Switch, der
    /// `init(_:)` und das Lesen gemeinsam traegt.
    static func decoded<O: Codable, Key: CodingKey>(_ c: KeyedDecodingContainer<Key>?, forKey key: Key, default def: O) -> O {
        c?.lenient(key) ?? def
    }
}
