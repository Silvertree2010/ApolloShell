import Foundation

// An open list of building blocks, the way BarLayout (the bar) and
// UtilitiesLayout (the quick toggles) each had one of their own: unique ids
// that are never empty, kinds that may only appear once at most once, lenient
// reading out of the file. Rules of a layout's own (where a new block is
// sorted into the bar, templates, card places in the dashboard) stay in their
// files and build on `BlockList`.

/// A kind of building block: the raw value stands in settings.json (`kind`),
/// and `isUnique` says whether there may be at most one of it.
public protocol BlockKind: RawRepresentable, Hashable, Sendable where RawValue == String {
    var isUnique: Bool { get }
}

/// A place in a `BlockList`: the id plus the kind. The id can change, because
/// `BlockList` hands out new ones when clearing up and adding.
/// vergibt.
public protocol Block: Codable, Equatable, Identifiable, Sendable where ID == String {
    associatedtype Kind: BlockKind
    var id: String { get set }
    var kind: Kind { get }
}

/// Always valid: the ids unique and never empty, kinds with `isUnique` at most
/// once - the initialiser and the changes here see to that, which is why
/// `entries` is only readable from outside.
///
/// In the file a plain list. Unreadable entries fall away, the rest stays.
///
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

    // MARK: Reading

    public subscript(id id: String) -> B? {
        entries.first { $0.id == id }
    }

    public func contains(_ kind: B.Kind) -> Bool {
        entries.contains { $0.kind == kind }
    }

    /// For the gallery: an at-most-once kind that is there already cannot be
    /// added again.
    public func canAdd(_ kind: B.Kind) -> Bool {
        !kind.isUnique || !contains(kind)
    }

    // MARK: Changing

    /// A new block, appended at the end without an `index`. Hands back its
    /// (possibly newly given) id; `nil` when the kind is there already and may
    /// only appear once.
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

    /// A different block in the same place. The kind stays: a clock does not
    /// become a second Dock that way.
    public mutating func update(id: String, to entry: B) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].kind == entry.kind else { return }
        entries[index] = entry
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
    }

    /// One place forward (-1) or back (+1); nothing at the edge.
    public mutating func move(id: String, by step: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let target = index + step
        guard entries.indices.contains(target) else { return }
        entries.swapAt(index, target)
    }

    /// To the place of another block - everything in between moves along a
    /// step. For dragging in the grid (`UtilitiesLayout`), where the dragged
    /// button visibly travels along.
    public mutating func move(id: String, onto target: String) {
        guard id != target,
              let from = entries.firstIndex(where: { $0.id == id }),
              let to = entries.firstIndex(where: { $0.id == target })
        else { return }
        let entry = entries.remove(at: from)
        entries.insert(entry, at: to)
    }

    // MARK: Rules

    /// Duplicate at-most-once kinds go (the first one stays), empty or
    /// duplicate ids become new ones - without taking an explicit id away from
    /// a later one.
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

    /// "clock", otherwise "clock-2", "clock-3" ... - readable in settings.json.
    static func uniqueID(for kind: B.Kind, taken: Set<String>) -> String {
        if !taken.contains(kind.rawValue) { return kind.rawValue }
        var n = 2
        while taken.contains("\(kind.rawValue)-\(n)") { n += 1 }
        return "\(kind.rawValue)-\(n)"
    }
}
