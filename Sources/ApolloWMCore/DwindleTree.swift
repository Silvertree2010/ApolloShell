import CoreGraphics

/// Spacing around and between tiles, in points.
public struct Gaps: Sendable, Equatable {
    public var outer: CGFloat
    public var inner: CGFloat

    public init(outer: CGFloat, inner: CGFloat) {
        self.outer = outer
        self.inner = inner
    }

    public static let none = Gaps(outer: 0, inner: 0)
}

/// Hyprland's "dwindle" layout: a binary tree where every new window splits
/// an existing tile in two. Each split runs along the longer side of the tile,
/// so the layout spirals inward as windows are added.
///
/// Coordinates are top-left based (y grows downward), matching the
/// Accessibility API. "First" means left in a side-by-side split and top in a
/// stacked split.
public struct DwindleTree<ID: Hashable & Sendable>: Sendable {
    indirect enum Node: Sendable {
        case leaf(ID)
        /// `sideBySide` nil means "decide by the tile's shape"; once frozen it
        /// stays, so resizing never flips a split's direction.
        case split(first: Node, second: Node, ratio: CGFloat, sideBySide: Bool?)
    }

    /// The split direction: frozen, or by shape (wide tiles split side by side).
    static func sideBySide(_ frozen: Bool?, _ plain: CGRect) -> Bool {
        frozen ?? (plain.width >= plain.height)
    }

    private(set) var root: Node?

    public init() {}

    public var isEmpty: Bool { root == nil }

    /// All windows in reading order (first before second, depth first).
    public var ids: [ID] {
        var result: [ID] = []
        func walk(_ node: Node) {
            switch node {
            case .leaf(let id): result.append(id)
            case .split(let a, let b, _, _): walk(a); walk(b)
            }
        }
        if let root { walk(root) }
        return result
    }

    public func contains(_ id: ID) -> Bool { ids.contains(id) }

    /// Splits `target`'s tile and puts `id` in one half. Without a target the
    /// last tile is split, which produces the dwindle spiral.
    public mutating func insert(_ id: ID, splitting target: ID? = nil, first: Bool = false) {
        guard !contains(id) else { return }
        guard let root else {
            self.root = .leaf(id)
            return
        }
        let target = target.flatMap { contains($0) ? $0 : nil } ?? ids.last!
        self.root = Self.replacing(target, in: root) { leaf in
            first
                ? .split(first: .leaf(id), second: leaf, ratio: 0.5, sideBySide: nil)
                : .split(first: leaf, second: .leaf(id), ratio: 0.5, sideBySide: nil)
        }
    }

    /// Inserts `id` where the mouse dropped it: the tile under `point` is
    /// split, and the half of that tile the point lies in decides the side.
    /// A point outside every tile falls back to splitting the last tile.
    public mutating func insert(_ id: ID, at point: CGPoint, in area: CGRect, gaps: Gaps = .none,
                                minimums: [ID: CGSize] = [:], maximums: [ID: CGSize] = [:]) {
        let frames = tiles(in: area, gaps: gaps, minimums: minimums, maximums: maximums)
        guard let target = frames.first(where: { $0.value.contains(point) }) else {
            insert(id)
            return
        }
        let rect = target.value
        let sideBySide = rect.width >= rect.height
        let first = sideBySide ? point.x < rect.midX : point.y < rect.midY
        insert(id, splitting: target.key, first: first)
    }

    /// Removes `id`; its sibling takes over the freed space.
    public mutating func remove(_ id: ID) {
        guard let root else { return }
        self.root = Self.removing(id, from: root)
    }

    /// The window whose tile contains `point`, if any.
    public func id(at point: CGPoint, in area: CGRect, gaps: Gaps = .none,
                   minimums: [ID: CGSize] = [:], maximums: [ID: CGSize] = [:]) -> ID? {
        tiles(in: area, gaps: gaps, minimums: minimums, maximums: maximums).first(where: { $0.value.contains(point) })?.key
    }

    /// Target frame for every window.
    ///
    /// `minimums` and `maximums` are sizes windows refuse to go below or
    /// above (learned by the engine). A split moves so each side stays within
    /// its limits: a side that cannot grow hands the rest to its neighbor, so
    /// no hole appears; a side that cannot shrink takes space from it.
    /// Minimums win over maximums. When both minimums together cannot fit,
    /// the space is shared in proportion to them.
    ///
    /// Split directions always come from the plain layout (no limits), so a
    /// shifted split never flips a neighbor from stacked to side by side.
    public func layout(in area: CGRect, gaps: Gaps = .none,
                       minimums: [ID: CGSize] = [:], maximums: [ID: CGSize] = [:]) -> [ID: CGRect] {
        tiles(in: area, gaps: gaps, minimums: minimums, maximums: maximums)
            .reduce(into: [ID: CGRect]()) { frames, entry in
                frames[entry.key] = Self.centered(entry.value, maximum: maximums[entry.key])
            }
    }

    /// A window that cannot fill its tile sits in the middle of it, so the
    /// leftover space reads as margin rather than a hole.
    public static func centered(_ tile: CGRect, maximum: CGSize?) -> CGRect {
        guard let maximum else { return tile }
        var frame = tile
        if maximum.width < tile.width {
            frame.origin.x += (tile.width - maximum.width) / 2
            frame.size.width = maximum.width
        }
        if maximum.height < tile.height {
            frame.origin.y += (tile.height - maximum.height) / 2
            frame.size.height = maximum.height
        }
        return frame
    }

    /// Each window's whole tile, before centering windows that cannot fill
    /// it. Hit-testing uses tiles, so the margin around such a window still
    /// counts as its spot.
    public func tiles(in area: CGRect, gaps: Gaps = .none,
                      minimums: [ID: CGSize] = [:], maximums: [ID: CGSize] = [:]) -> [ID: CGRect] {
        var frames: [ID: CGRect] = [:]
        func place(_ node: Node, in rect: CGRect, plain: CGRect) {
            switch node {
            case .leaf(let id):
                frames[id] = rect
            case .split(let a, let b, let ratio, let frozen):
                let sideBySide = Self.sideBySide(frozen, plain)
                let (pa, pb) = Self.divide(plain, ratio: ratio, gap: gaps.inner, sideBySide: sideBySide)
                let minA = Self.limit(of: a, plain: pa, gap: gaps.inner, sizes: minimums, missing: .zero, cross: max)
                let minB = Self.limit(of: b, plain: pb, gap: gaps.inner, sizes: minimums, missing: .zero, cross: max)
                let maxA = Self.limit(of: a, plain: pa, gap: gaps.inner, sizes: maximums, missing: .infinite, cross: max)
                let maxB = Self.limit(of: b, plain: pb, gap: gaps.inner, sizes: maximums, missing: .infinite, cross: max)
                func along(_ size: CGSize) -> CGFloat { sideBySide ? size.width : size.height }
                let available = along(rect.size) - gaps.inner
                var length = available * ratio
                length = min(length, along(maxA))
                length = max(length, available - along(maxB))
                let needA = along(minA), needB = along(minB)
                if needA + needB > available {
                    if needA + needB > 0 { length = available * needA / (needA + needB) }
                } else {
                    length = min(max(length, needA), available - needB)
                }
                let adjusted = available > 0 ? length / available : ratio
                let (ra, rb) = Self.divide(rect, ratio: adjusted, gap: gaps.inner, sideBySide: sideBySide)
                place(a, in: ra, plain: pa)
                place(b, in: rb, plain: pb)
            }
        }
        if let root {
            let inset = area.insetBy(dx: gaps.outer, dy: gaps.outer)
            place(root, in: inset, plain: inset)
        }
        return frames
    }

    /// Combined limit of a subtree: along a split the children's limits add
    /// up; across it the larger one counts. Uses the plain layout's directions.
    static func limit(of node: Node, plain: CGRect, gap: CGFloat, sizes: [ID: CGSize],
                      missing: CGSize, cross: (CGFloat, CGFloat) -> CGFloat) -> CGSize {
        switch node {
        case .leaf(let id):
            return sizes[id] ?? missing
        case .split(let a, let b, let ratio, let frozen):
            let sideBySide = Self.sideBySide(frozen, plain)
            let (pa, pb) = divide(plain, ratio: ratio, gap: gap, sideBySide: sideBySide)
            let la = limit(of: a, plain: pa, gap: gap, sizes: sizes, missing: missing, cross: cross)
            let lb = limit(of: b, plain: pb, gap: gap, sizes: sizes, missing: missing, cross: cross)
            return sideBySide
                ? CGSize(width: la.width + gap + lb.width, height: cross(la.height, lb.height))
                : CGSize(width: cross(la.width, lb.width), height: la.height + gap + lb.height)
        }
    }

    /// Fixes every undecided split direction to what the current layout
    /// shows. Call after each change, so later resizes never flip a split.
    public mutating func freezeDirections(in area: CGRect, gaps: Gaps = .none) {
        func freeze(_ node: Node, plain: CGRect) -> Node {
            guard case .split(let a, let b, let ratio, let frozen) = node else { return node }
            let sideBySide = Self.sideBySide(frozen, plain)
            let (pa, pb) = Self.divide(plain, ratio: ratio, gap: gaps.inner, sideBySide: sideBySide)
            return .split(first: freeze(a, plain: pa), second: freeze(b, plain: pb),
                          ratio: ratio, sideBySide: sideBySide)
        }
        if let root { self.root = freeze(root, plain: area.insetBy(dx: gaps.outer, dy: gaps.outer)) }
    }

    /// The user dragged edges of `id` so the window now covers `frame`. Each
    /// edge that moved shifts the nearest split on that side, like dragging
    /// a border in Hyprland; the neighbors on the other side give or take
    /// the space. Ratios stay between 5% and 95%.
    public mutating func resize(_ id: ID, to frame: CGRect, in area: CGRect, gaps: Gaps = .none) {
        guard let root, let tile = tiles(in: area, gaps: gaps)[id] else { return }
        // Which edges moved, compared with the window's current tile.
        var edges: Set<Edge> = []
        if abs(frame.minX - tile.minX) > 1 { edges.insert(.left) }
        if abs(frame.maxX - tile.maxX) > 1 { edges.insert(.right) }
        if abs(frame.minY - tile.minY) > 1 { edges.insert(.top) }
        if abs(frame.maxY - tile.maxY) > 1 { edges.insert(.bottom) }
        guard !edges.isEmpty else { return }

        func clamp(_ r: CGFloat) -> CGFloat { min(max(r, 0.05), 0.95) }
        func adjust(_ node: Node, rect: CGRect) -> Node {
            guard case .split(let a, let b, var ratio, let frozen) = node else { return node }
            let sideBySide = Self.sideBySide(frozen, rect)
            let (ra, rb) = Self.divide(rect, ratio: ratio, gap: gaps.inner, sideBySide: sideBySide)
            let length = (sideBySide ? rect.width : rect.height) - gaps.inner
            guard length > 0 else { return node }
            if Self.contains(a, id) {
                // Deeper splits claim an edge first: they sit closer to the window.
                let na = adjust(a, rect: ra)
                if sideBySide, edges.remove(.right) != nil {
                    ratio = clamp((frame.maxX - rect.minX) / length)
                } else if !sideBySide, edges.remove(.bottom) != nil {
                    ratio = clamp((frame.maxY - rect.minY) / length)
                }
                return .split(first: na, second: b, ratio: ratio, sideBySide: frozen)
            } else if Self.contains(b, id) {
                let nb = adjust(b, rect: rb)
                if sideBySide, edges.remove(.left) != nil {
                    ratio = clamp((frame.minX - gaps.inner - rect.minX) / length)
                } else if !sideBySide, edges.remove(.top) != nil {
                    ratio = clamp((frame.minY - gaps.inner - rect.minY) / length)
                }
                return .split(first: a, second: nb, ratio: ratio, sideBySide: frozen)
            }
            return node
        }
        self.root = adjust(root, rect: area.insetBy(dx: gaps.outer, dy: gaps.outer))
    }

    enum Edge { case left, right, top, bottom }

    static func contains(_ node: Node, _ id: ID) -> Bool {
        switch node {
        case .leaf(let leaf): return leaf == id
        case .split(let a, let b, _, _): return contains(a, id) || contains(b, id)
        }
    }

    static func divide(_ rect: CGRect, ratio: CGFloat, gap: CGFloat, sideBySide: Bool) -> (CGRect, CGRect) {
        if sideBySide {
            let w = (rect.width - gap) * ratio
            return (
                CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height),
                CGRect(x: rect.minX + w + gap, y: rect.minY, width: rect.width - w - gap, height: rect.height)
            )
        } else {
            let h = (rect.height - gap) * ratio
            return (
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h),
                CGRect(x: rect.minX, y: rect.minY + h + gap, width: rect.width, height: rect.height - h - gap)
            )
        }
    }

    private static func replacing(_ target: ID, in node: Node, with make: (Node) -> Node) -> Node {
        switch node {
        case .leaf(let id):
            return id == target ? make(node) : node
        case .split(let a, let b, let ratio, let frozen):
            return .split(first: replacing(target, in: a, with: make),
                          second: replacing(target, in: b, with: make),
                          ratio: ratio, sideBySide: frozen)
        }
    }

    private static func removing(_ target: ID, from node: Node) -> Node? {
        switch node {
        case .leaf(let id):
            return id == target ? nil : node
        case .split(let a, let b, let ratio, let frozen):
            let na = removing(target, from: a)
            let nb = removing(target, from: b)
            switch (na, nb) {
            case let (x?, y?): return .split(first: x, second: y, ratio: ratio, sideBySide: frozen)
            case let (x?, nil): return x
            case let (nil, y?): return y
            case (nil, nil): return nil
            }
        }
    }
}

extension CGSize {
    public static let infinite = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
}
