import Foundation

// The kind and the options in one, the way BarModule, UtilitiesToggle and
// DashboardCard each are on their own: only kinds with options carry any.
// The protocol pins down what an entry (`BarEntry`, `UtilitiesToggleEntry`,
// `DashboardCard`) needs of it, so that `hasOptions` becomes `options != nil`
// and the encode switch falls away.
//
// The three do NOT share the decode switch word for word: their CodingKeys
// (with or without an `id` of their own) and option types differ, and a
// generic decoder over all three would have cost more detour than it saves in
// lines. So one of its own stays per file, but only ONE switch (instead of
// two: one for the defaults, one for the reading) - see `make(_:default:wrap:)`.
public protocol BlockModule: Equatable, Sendable {
    associatedtype Kind: Hashable, Sendable

    /// With the defaults of the kind.
    init(_ kind: Kind)

    var kind: Kind { get }

    /// `nil` with a kind without options.
    var options: (any Encodable)? { get }
}

public extension BlockModule {
    /// Whether a user interface lets options unfold for this block.
    var hasOptions: Bool { options != nil }

    /// The options out of the file, otherwise the default - for the one switch
    /// that carries `init(_:)` and the reading together.
    static func decoded<O: Codable, Key: CodingKey>(_ c: KeyedDecodingContainer<Key>?, forKey key: Key, default def: O) -> O {
        c?.lenient(key) ?? def
    }
}
