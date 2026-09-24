/// Windows sharing one tile, shown one at a time like tabs. Only the active
/// window stands in the layout tree; the others lie exactly behind it.
public struct TabGroup<ID: Hashable & Sendable & Codable>: Sendable, Codable, Equatable {
    public private(set) var members: [ID]
    public private(set) var active: ID

    public init(_ first: ID, _ second: ID, active: ID? = nil) {
        members = [first, second]
        self.active = active ?? second
    }

    public func contains(_ id: ID) -> Bool { members.contains(id) }

    /// Adds a window as the last tab and shows it.
    public mutating func add(_ id: ID) {
        guard !members.contains(id) else { return }
        members.append(id)
        active = id
    }

    public mutating func activate(_ id: ID) {
        if members.contains(id) { active = id }
    }

    /// Removes a window. When it was the active one, its right neighbor tab
    /// (or the left one at the end) becomes active. Returns the new active
    /// window, or nil when the group is down to one window and should end.
    public mutating func remove(_ id: ID) -> ID? {
        guard let index = members.firstIndex(of: id) else { return active }
        members.remove(at: index)
        if active == id, !members.isEmpty {
            active = members[min(index, members.count - 1)]
        }
        return members.count > 1 ? active : nil
    }

    /// Moves a tab one place along the bar. Returns whether it moved.
    @discardableResult
    public mutating func move(_ id: ID, forward: Bool) -> Bool {
        guard let index = members.firstIndex(of: id) else { return false }
        let to = index + (forward ? 1 : -1)
        guard members.indices.contains(to) else { return false }
        members.swapAt(index, to)
        return true
    }

    /// Puts a tab at `index` (a drag along the bar).
    public mutating func move(_ id: ID, to index: Int) {
        guard let from = members.firstIndex(of: id), members.indices.contains(index), from != index else { return }
        let member = members.remove(at: from)
        members.insert(member, at: index)
    }

    /// The tab after (or before) the active one, wrapping around.
    public func neighbor(of id: ID, forward: Bool) -> ID? {
        guard let index = members.firstIndex(of: id), members.count > 1 else { return nil }
        let next = (index + (forward ? 1 : members.count - 1)) % members.count
        return members[next]
    }
}
