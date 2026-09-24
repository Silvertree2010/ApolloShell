public struct SpaceLayouts<Space: Hashable & Sendable, ID: Hashable & Sendable>: Sendable {
    public private(set) var trees: [Space: DwindleTree<ID>] = [:]
    public private(set) var spaceOf: [ID: Space] = [:]

    public init() {}

    public subscript(space: Space) -> DwindleTree<ID> {
        get { trees[space] ?? DwindleTree() }
        set { trees[space] = newValue.isEmpty ? nil : newValue }
    }

    public func space(of id: ID) -> Space? { spaceOf[id] }

    public mutating func assign(_ id: ID, to space: Space, insert: (inout DwindleTree<ID>) -> Void) {
        guard spaceOf[id] != space else { return }
        remove(id)
        var tree = self[space]
        insert(&tree)
        self[space] = tree
        spaceOf[id] = space
    }

    public mutating func replace(_ old: ID, with new: ID) {
        guard let space = spaceOf[old], spaceOf[new] == nil else { return }
        self[space].replace(old, with: new)
        spaceOf[old] = nil
        spaceOf[new] = space
    }

    public mutating func move(_ from: Space, to target: Space) {
        guard from != target, let tree = trees[from] else { return }
        trees[from] = nil
        if self[target].isEmpty {
            trees[target] = tree
            for id in tree.ids { spaceOf[id] = target }
        } else {
            for id in tree.ids {
                spaceOf[id] = nil
                assign(id, to: target) { $0.insert(id) }
            }
        }
    }

    public mutating func retain(where keep: (ID) -> Bool) {
        for id in spaceOf.keys where !keep(id) { remove(id) }
    }

    public mutating func remove(_ id: ID) {
        guard let space = spaceOf.removeValue(forKey: id) else { return }
        self[space].remove(id)
    }
}

extension SpaceLayouts: Codable where Space: Codable, ID: Codable {}
