import Foundation

// MARK: - Where a block stands

/// One list of blocks the edit mode can change: the sidebar, or one zone of
/// an edge bar. Every such list is an ordinary `BarLayout`.
public enum BarPlace: Hashable, Sendable {
    case sidebar
    case edge(BarEdge, BarZone)

    /// The sidebar first, then every zone of every edge in reading order.
    public static let all: [BarPlace] = [.sidebar] + BarEdge.allCases.flatMap { edge in
        BarZone.allCases.map { BarPlace.edge(edge, $0) }
    }

    public var edge: BarEdge? {
        if case .edge(let edge, _) = self { edge } else { nil }
    }

    /// "top.start" - for drag payloads, which carry only text.
    var token: String? {
        if case .edge(let edge, let zone) = self { "\(edge.rawValue).\(zone.rawValue)" } else { nil }
    }

    init?(token: String) {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let edge = BarEdge(rawValue: String(parts[0])),
              let zone = BarZone(rawValue: String(parts[1])) else { return nil }
        self = .edge(edge, zone)
    }
}

/// A block in one of the bars. Ids are only unique within one list, so a
/// block is named by its list and its id together.
public struct BarEntryRef: Hashable, Sendable {
    public var place: BarPlace
    public var id: String

    public init(place: BarPlace, id: String) {
        self.place = place
        self.id = id
    }

    public static func sidebar(_ id: String) -> BarEntryRef { BarEntryRef(place: .sidebar, id: id) }

    /// The text a drag carries. A sidebar block is its bare id, exactly what
    /// the sidebar dragged before the edge bars could be edited, so nothing
    /// changes there; an edge block is "top.start/clock".
    public var payload: String {
        place.token.map { "\($0)/\(id)" } ?? id
    }

    /// Reads `payload` back. Text before a "/" that names no zone belongs to
    /// a sidebar id (a hand-edited one may contain a slash).
    public init(payload: String) {
        if let slash = payload.firstIndex(of: "/"), let place = BarPlace(token: String(payload[..<slash])) {
            self.init(place: place, id: String(payload[payload.index(after: slash)...]))
        } else {
            self.init(place: .sidebar, id: payload)
        }
    }
}

// MARK: - The session

/// An edit of the bars (global edit mode, `ShellEditor`): working copies of
/// the sidebar and of the edge bars' zones, and the selected block. "Done"
/// adopts them, "Cancel" discards them (`original`, `originalEdgeBars`).
///
/// The same shape as `UtilitiesEditSession`, and for the same reason: the
/// rules of one list (unique ids, kinds that may exist only once, where a new
/// block goes) live in `BarLayout`, so this only carries the copies and the
/// selection through the mode - plus the two rules that span lists: Dock and
/// status icons at most once per bar (not per zone, `EdgeBar.canAdd`), and
/// groups (`joinsPrevious`) that stay whole when a block leaves or arrives.
///
/// The sidebar-only calls (`add(_:at:)`, `move(id:onto:)`, `selectedEntryID`
/// ...) are the ones the sidebar used before the edge bars could be edited;
/// they behave exactly as they did.
public struct BarEditSession: Equatable, Sendable {
    public let original: BarLayout
    public let originalEdgeBars: EdgeBars
    /// The sidebar's working copy.
    public private(set) var layout: BarLayout
    /// The edge bars' working copy. Only the zones change here; switching a
    /// bar on, its style and thickness stay Nexus settings.
    public private(set) var edgeBars: EdgeBars
    /// At most one block in all bars together: only one options popover.
    public var selection: BarEntryRef?

    public init(layout: BarLayout, edgeBars: EdgeBars = EdgeBars()) {
        original = layout
        originalEdgeBars = edgeBars
        self.layout = layout
        self.edgeBars = edgeBars
    }

    public var hasChanges: Bool { layout != original || edgeBars != originalEdgeBars }

    /// The selected sidebar block. Setting `nil` clears the selection
    /// wherever it is, as it did when the sidebar was the only bar.
    public var selectedEntryID: String? {
        get { selection?.place == .sidebar ? selection?.id : nil }
        set { selection = newValue.map(BarEntryRef.sidebar) }
    }

    // MARK: Reading

    public subscript(place: BarPlace) -> BarLayout {
        get {
            switch place {
            case .sidebar: layout
            case .edge(let edge, let zone): edgeBars[edge][zone]
            }
        }
        set {
            switch place {
            case .sidebar: layout = newValue
            case .edge(let edge, let zone): edgeBars[edge][zone] = newValue
            }
        }
    }

    public func entry(_ ref: BarEntryRef) -> BarEntry? {
        self[ref.place][id: ref.id]
    }

    /// Dock and status icons once per bar: in the sidebar, or once across
    /// all three zones of an edge bar.
    public func canAdd(_ kind: BarModuleKind, to place: BarPlace) -> Bool {
        switch place {
        case .sidebar: layout.canAdd(kind)
        case .edge(let edge, _): edgeBars[edge].canAdd(kind)
        }
    }

    /// Only an edge bar draws groups, and the first block of a zone has
    /// nothing before it to join.
    public func canJoin(_ ref: BarEntryRef) -> Bool {
        guard ref.place != .sidebar, let index = self[ref.place].entries.firstIndex(where: { $0.id == ref.id })
        else { return false }
        return index > 0
    }

    // MARK: Sidebar (the calls from before the edge bars)

    /// A new block, without `index` at the spot `BarLayout.insertionIndex`
    /// picks; selects it. `nil`: the kind may exist only once and is there
    /// already - then nothing changed and nothing is selected anew.
    @discardableResult
    public mutating func add(_ kind: BarModuleKind, at index: Int? = nil) -> String? {
        add(kind, to: .sidebar, at: index)
    }

    public mutating func remove(id: String) {
        remove(.sidebar(id))
    }

    /// Other options for a block. The kind stays, so a clock cannot become a
    /// second Dock this way.
    public mutating func update(id: String, to module: BarModule) {
        layout.update(id: id, to: module)
    }

    /// Like SwiftUI's `onMove`: `destination` counts in the list before the
    /// move.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        layout.move(fromOffsets: source, toOffset: destination)
    }

    /// One spot up (-1) or down (+1); nothing at the edge.
    public mutating func move(id: String, by step: Int) {
        layout.move(id: id, by: step)
    }

    /// To the place of another block, for dragging in the bar.
    public mutating func move(id: String, onto target: String) {
        layout.move(id: id, onto: target)
    }

    // MARK: Any bar

    /// A new block in `place`, without `index` at the spot
    /// `BarLayout.insertionIndex` picks; selects it. `nil` when the kind may
    /// exist only once in that bar and is there already.
    @discardableResult
    public mutating func add(_ kind: BarModuleKind, to place: BarPlace, at index: Int? = nil) -> String? {
        guard canAdd(kind, to: place), let id = self[place].add(kind, at: index) else { return nil }
        selection = BarEntryRef(place: place, id: id)
        return id
    }

    public mutating func remove(_ ref: BarEntryRef) {
        guard entry(ref) != nil else { return }
        detach(ref)
        self[ref.place].remove(id: ref.id)
        if selection == ref { selection = nil }
    }

    public mutating func update(_ ref: BarEntryRef, to module: BarModule) {
        self[ref.place].update(id: ref.id, to: module)
    }

    /// "Join with previous" in the options popover. Nothing where there is
    /// nothing to join (`canJoin`).
    public mutating func setJoinsPrevious(_ ref: BarEntryRef, _ joins: Bool) {
        guard !joins || canJoin(ref) else { return }
        self[ref.place].setJoinsPrevious(id: ref.id, joins)
    }

    public mutating func toggleJoin(_ ref: BarEntryRef) {
        guard let entry = entry(ref) else { return }
        setJoinsPrevious(ref, !entry.joinsPrevious)
    }

    /// Moves a block to `index` in `place` - within its list, to another
    /// zone or to another bar, options and all. `index` is the block's final
    /// position there (clamped). Returns where it stands now; `nil` (and
    /// nothing changed) when it is gone or the target bar already has its
    /// one Dock or status icons. An id the target list already uses is
    /// replaced by a fresh one, and the selection follows the block.
    ///
    /// Groups: the group it leaves stays whole (its next block takes over the
    /// head, so it does not melt into the group before), and it joins the
    /// group it lands in the middle of - otherwise it arrives on its own.
    @discardableResult
    public mutating func move(_ ref: BarEntryRef, to place: BarPlace, at index: Int) -> BarEntryRef? {
        guard var entry = entry(ref) else { return nil }
        // Dropped where it already stands: nothing moves, and its group
        // flag must not be re-read from a list it was taken out of.
        if place == ref.place, self[place].entries.firstIndex(where: { $0.id == ref.id })
            == min(max(index, 0), self[place].entries.count - 1) { return ref }
        var next = self
        next.detach(ref)
        next[ref.place].remove(id: ref.id)
        guard next.canAdd(entry.kind, to: place) else { return nil }
        let target = next[place].entries
        let position = min(max(index, 0), target.count)
        entry.joinsPrevious = position > 0 && position < target.count && target[position].joinsPrevious
        guard let id = next[place].insert(entry, at: position) else { return nil }
        let moved = BarEntryRef(place: place, id: id)
        if next.selection == ref { next.selection = moved }
        self = next
        return moved
    }

    /// To the place of another block, for dragging: in its own list it
    /// takes the target's spot (like `move(id:onto:)`), in another list it
    /// goes in right before the target. Two sidebar blocks move exactly as
    /// before.
    @discardableResult
    public mutating func move(_ ref: BarEntryRef, onto target: BarEntryRef) -> BarEntryRef? {
        guard ref != target, let index = self[target.place].entries.firstIndex(where: { $0.id == target.id })
        else { return nil }
        if ref.place == .sidebar, target.place == .sidebar {
            guard entry(ref) != nil else { return nil }
            layout.move(id: ref.id, onto: target.id)
            return ref
        }
        return move(ref, to: target.place, at: index)
    }

    /// Appends at the end of `place`, for a drop next to the blocks.
    @discardableResult
    public mutating func moveToEnd(_ ref: BarEntryRef, of place: BarPlace) -> BarEntryRef? {
        let count = self[place].entries.count - (ref.place == place ? 1 : 0)
        return move(ref, to: place, at: count)
    }

    /// Before a block leaves its list: when it heads a group, the block
    /// after it takes over the head, instead of joining the group before.
    private mutating func detach(_ ref: BarEntryRef) {
        let entries = self[ref.place].entries
        guard let index = entries.firstIndex(where: { $0.id == ref.id }), index + 1 < entries.count else { return }
        let heads = index == 0 || !entries[index].joinsPrevious
        if heads, entries[index + 1].joinsPrevious {
            self[ref.place].setJoinsPrevious(id: entries[index + 1].id, false)
        }
    }
}
