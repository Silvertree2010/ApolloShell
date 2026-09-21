/// One layout tree per desktop (macOS Space, later also our own workspaces).
/// Every window belongs to exactly one desktop.
public struct SpaceLayouts<Space: Hashable & Sendable, ID: Hashable & Sendable>: Sendable {
    public private(set) var trees: [Space: DwindleTree<ID>] = [:]
    public private(set) var spaceOf: [ID: Space] = [:]

    public init() {}

    public subscript(space: Space) -> DwindleTree<ID> {
        get { trees[space] ?? DwindleTree() }
        set { trees[space] = newValue.isEmpty ? nil : newValue }
    }

    public func space(of id: ID) -> Space? { spaceOf[id] }

    /// Puts `id` on `space` using `insert` to place it in that tree. A window
    /// already on another desktop leaves that one first; one already on
    /// `space` stays where it is.
    public mutating func assign(_ id: ID, to space: Space, insert: (inout DwindleTree<ID>) -> Void) {
        guard spaceOf[id] != space else { return }
        remove(id)
        var tree = self[space]
        insert(&tree)
        self[space] = tree
        spaceOf[id] = space
    }

    /// Forgets every window `keep` rejects, e.g. windows that no longer exist.
    public mutating func retain(where keep: (ID) -> Bool) {
        for id in spaceOf.keys where !keep(id) { remove(id) }
    }

    public mutating func remove(_ id: ID) {
        guard let space = spaceOf.removeValue(forKey: id) else { return }
        self[space].remove(id)
    }
}

extension SpaceLayouts: Codable where Space: Codable, ID: Codable {}
