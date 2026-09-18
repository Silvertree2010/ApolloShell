import Foundation

// Eine offene Liste von Bausteinen, wie sie BarLayout (Leiste) und
// UtilitiesLayout (Schnellschalter) je fuer sich hatten: eindeutige, nie
// leere Kennungen, Arten die nur einmal vorkommen duerfen hoechstens einmal,
// nachsichtiges Lesen aus der Datei. Layout-eigene Regeln (z. B. wo ein
// neuer Baustein in der Leiste einsortiert wird, Vorlagen, Kartenplaetze im
// Dashboard) bleiben in den jeweiligen Dateien und bauen auf `BlockList` auf.

/// Eine Art von Baustein: der Rohwert steht in settings.json (`kind`),
/// `isUnique` sagt, ob es sie hoechstens einmal geben darf.
public protocol BlockKind: RawRepresentable, Hashable, Sendable where RawValue == String {
    var isUnique: Bool { get }
}

/// Ein Platz in einer `BlockList`: Kennung plus Art. Die Kennung ist
/// veraenderlich, weil `BlockList` sie beim Aufraeumen und Hinzufuegen neu
/// vergibt.
public protocol Block: Codable, Equatable, Identifiable, Sendable where ID == String {
    associatedtype Kind: BlockKind
    var id: String { get set }
    var kind: Kind { get }
}

/// Immer gueltig: Kennungen eindeutig und nie leer, Arten mit `isUnique`
/// hoechstens einmal - dafuer sorgen Initialisierer und Aenderungen hier,
/// deshalb ist `entries` von aussen nur lesbar.
///
/// In der Datei eine schlichte Liste. Unlesbare Eintraege fallen weg, der
/// Rest bleibt.
public struct BlockList<B: Block>: Codable, Equatable, Sendable {
    public private(set) var entries: [B]

    public init(_ entries: [B] = []) {
        self.entries = Self.normalized(entries)
    }

    public init(from decoder: any Decoder) throws {
        self.init(try LenientList<B>(from: decoder).values)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(entries)
    }

    // MARK: Lesen

    public subscript(id id: String) -> B? {
        entries.first { $0.id == id }
    }

    public func contains(_ kind: B.Kind) -> Bool {
        entries.contains { $0.kind == kind }
    }

    /// Fuer die Galerie: eine hoechstens-einmal-Art, die schon da ist, laesst
    /// sich nicht noch einmal hinzufuegen.
    public func canAdd(_ kind: B.Kind) -> Bool {
        !kind.isUnique || !contains(kind)
    }

    // MARK: Aendern

    /// Neuer Baustein, ohne `index` hinten angehaengt. Gibt seine (moeglich
    /// neu vergebene) Kennung zurueck; `nil`, wenn die Art schon da ist und
    /// nur einmal vorkommen darf.
    @discardableResult
    public mutating func add(_ entry: B, at index: Int? = nil) -> String? {
        guard canAdd(entry.kind) else { return nil }
        var entry = entry
        entry.id = Self.uniqueID(for: entry.kind, taken: Set(entries.map(\.id)))
        let position = min(max(index ?? entries.count, 0), entries.count)
        entries.insert(entry, at: position)
        return entry.id
    }

    public mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    /// Anderer Baustein an derselben Stelle. Die Art bleibt: aus einer Uhr
    /// wird so kein zweites Dock.
    public mutating func update(id: String, to entry: B) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].kind == entry.kind else { return }
        entries[index] = entry
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
    }

    /// Eine Stelle nach vorne (-1) oder hinten (+1); am Rand nichts.
    public mutating func move(id: String, by step: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let target = index + step
        guard entries.indices.contains(target) else { return }
        entries.swapAt(index, target)
    }

    /// An die Stelle eines anderen Bausteins - alles dazwischen rueckt ein
    /// Stueck weiter. Fuer das Ziehen im Raster (`UtilitiesLayout`), wo der
    /// gezogene Knopf sichtbar mitwandert.
    public mutating func move(id: String, onto target: String) {
        guard id != target,
              let from = entries.firstIndex(where: { $0.id == id }),
              let to = entries.firstIndex(where: { $0.id == target })
        else { return }
        let entry = entries.remove(at: from)
        entries.insert(entry, at: to)
    }

    // MARK: Regeln

    /// Doppelte hoechstens-einmal-Arten weg (die erste bleibt), leere oder
    /// doppelte Kennungen neu - ohne einer spaeteren ihre ausdrueckliche
    /// Kennung wegzunehmen.
    static func normalized(_ list: [B]) -> [B] {
        var kinds = Set<B.Kind>()
        var used = Set<String>()
        var taken = Set(list.map(\.id))
        var result: [B] = []
        for var entry in list {
            if entry.kind.isUnique, !kinds.insert(entry.kind).inserted { continue }
            if entry.id.isEmpty || used.contains(entry.id) {
                entry.id = uniqueID(for: entry.kind, taken: taken)
                taken.insert(entry.id)
            }
            used.insert(entry.id)
            result.append(entry)
        }
        return result
    }

    /// "clock", sonst "clock-2", "clock-3" ... - lesbar in settings.json.
    static func uniqueID(for kind: B.Kind, taken: Set<String>) -> String {
        if !taken.contains(kind.rawValue) { return kind.rawValue }
        var n = 2
        while taken.contains("\(kind.rawValue)-\(n)") { n += 1 }
        return "\(kind.rawValue)-\(n)"
    }
}
