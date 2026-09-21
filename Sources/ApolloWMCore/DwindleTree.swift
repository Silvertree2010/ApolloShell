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
        case split(first: Node, second: Node, ratio: CGFloat)
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
            case .split(let a, let b, _): walk(a); walk(b)
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
                ? .split(first: .leaf(id), second: leaf, ratio: 0.5)
                : .split(first: leaf, second: .leaf(id), ratio: 0.5)
        }
    }

    /// Inserts `id` where the mouse dropped it: the tile under `point` is
    /// split, and the half of that tile the point lies in decides the side.
    /// A point outside every tile falls back to splitting the last tile.
    public mutating func insert(_ id: ID, at point: CGPoint, in area: CGRect, gaps: Gaps = .none) {
        let frames = layout(in: area, gaps: gaps)
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
    public func id(at point: CGPoint, in area: CGRect, gaps: Gaps = .none) -> ID? {
        layout(in: area, gaps: gaps).first(where: { $0.value.contains(point) })?.key
    }

    /// Target frame for every window.
    public func layout(in area: CGRect, gaps: Gaps = .none) -> [ID: CGRect] {
        var frames: [ID: CGRect] = [:]
        func place(_ node: Node, in rect: CGRect) {
            switch node {
            case .leaf(let id):
                frames[id] = rect
            case .split(let a, let b, let ratio):
                let (ra, rb) = Self.divide(rect, ratio: ratio, gap: gaps.inner)
                place(a, in: ra)
                place(b, in: rb)
            }
        }
        if let root { place(root, in: area.insetBy(dx: gaps.outer, dy: gaps.outer)) }
        return frames
    }

    static func divide(_ rect: CGRect, ratio: CGFloat, gap: CGFloat) -> (CGRect, CGRect) {
        if rect.width >= rect.height {
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
        case .split(let a, let b, let ratio):
            return .split(first: replacing(target, in: a, with: make),
                          second: replacing(target, in: b, with: make),
                          ratio: ratio)
        }
    }

    private static func removing(_ target: ID, from node: Node) -> Node? {
        switch node {
        case .leaf(let id):
            return id == target ? nil : node
        case .split(let a, let b, let ratio):
            let na = removing(target, from: a)
            let nb = removing(target, from: b)
            switch (na, nb) {
            case let (x?, y?): return .split(first: x, second: y, ratio: ratio)
            case let (x?, nil): return x
            case let (nil, y?): return y
            case (nil, nil): return nil
            }
        }
    }
}
