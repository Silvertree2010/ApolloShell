import CoreGraphics

public struct Gaps: Sendable, Equatable, Codable {
    public var outer: CGFloat
    public var inner: CGFloat

    public init(outer: CGFloat, inner: CGFloat) {
        self.outer = outer
        self.inner = inner
    }

    public static let none = Gaps(outer: 0, inner: 0)
}

public struct DwindleTree<ID: Hashable & Sendable>: Sendable {
    indirect enum Node: Sendable {
        case leaf(ID)
        case split(first: Node, second: Node, ratio: CGFloat, sideBySide: Bool?)
    }

    static func sideBySide(_ frozen: Bool?, _ plain: CGRect) -> Bool {
        frozen ?? (plain.width >= plain.height)
    }

    private(set) var root: Node?

    public init() {}

    public var isEmpty: Bool { root == nil }

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

    public mutating func remove(_ id: ID) {
        guard let root else { return }
        self.root = Self.removing(id, from: root)
    }

    public func id(at point: CGPoint, in area: CGRect, gaps: Gaps = .none,
                   minimums: [ID: CGSize] = [:], maximums: [ID: CGSize] = [:]) -> ID? {
        tiles(in: area, gaps: gaps, minimums: minimums, maximums: maximums).first(where: { $0.value.contains(point) })?.key
    }

    public func layout(in area: CGRect, gaps: Gaps = .none,
                       minimums: [ID: CGSize] = [:], maximums: [ID: CGSize] = [:]) -> [ID: CGRect] {
        let inner = area.insetBy(dx: gaps.outer, dy: gaps.outer)
        return tiles(in: area, gaps: gaps, minimums: minimums, maximums: maximums)
            .reduce(into: [ID: CGRect]()) { frames, entry in
                let frame = Self.centered(entry.value, maximum: maximums[entry.key])
                frames[entry.key] = Self.keptInside(frame, minimum: minimums[entry.key], area: inner)
            }
    }

    static func keptInside(_ frame: CGRect, minimum: CGSize?, area: CGRect) -> CGRect {
        guard let minimum else { return frame }
        var frame = frame
        if minimum.width > frame.width {
            frame.size.width = min(minimum.width, area.width)
            frame.origin.x = min(max(frame.minX, area.minX), area.maxX - frame.width)
        }
        if minimum.height > frame.height {
            frame.size.height = min(minimum.height, area.height)
            frame.origin.y = min(max(frame.minY, area.minY), area.maxY - frame.height)
        }
        return frame
    }

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

    public mutating func replace(_ old: ID, with new: ID) {
        guard old != new, contains(old), !contains(new), let root else { return }
        self.root = Self.replacing(old, in: root) { _ in .leaf(new) }
    }

    public func sibling(of id: ID) -> ID? {
        func first(_ node: Node) -> ID {
            switch node {
            case .leaf(let leaf): return leaf
            case .split(let a, _, _, _): return first(a)
            }
        }
        func search(_ node: Node) -> ID? {
            guard case .split(let a, let b, _, _) = node else { return nil }
            if case .leaf(let leaf) = a, leaf == id { return first(b) }
            if case .leaf(let leaf) = b, leaf == id { return first(a) }
            return search(a) ?? search(b)
        }
        return root.flatMap(search)
    }

    public func fits(in area: CGRect, gaps: Gaps = .none, minimums: [ID: CGSize]) -> Bool {
        let tiles = tiles(in: area, gaps: gaps, minimums: minimums)
        return tiles.allSatisfy { id, tile in
            guard let minimum = minimums[id] else { return true }
            return tile.width + 1 >= minimum.width && tile.height + 1 >= minimum.height
        }
    }

    public mutating func swap(_ a: ID, _ b: ID) {
        guard a != b, contains(a), contains(b), let root else { return }
        func swapped(_ node: Node) -> Node {
            switch node {
            case .leaf(let id):
                return .leaf(id == a ? b : id == b ? a : id)
            case .split(let first, let second, let ratio, let frozen):
                return .split(first: swapped(first), second: swapped(second), ratio: ratio, sideBySide: frozen)
            }
        }
        self.root = swapped(root)
    }

    public mutating func toggleSplit(of id: ID) {
        guard let root else { return }
        func toggled(_ node: Node) -> Node {
            guard case .split(let a, let b, let ratio, let frozen) = node else { return node }
            if case .leaf(let leaf) = a, leaf == id {
                return .split(first: a, second: b, ratio: ratio, sideBySide: frozen.map { !$0 })
            }
            if case .leaf(let leaf) = b, leaf == id {
                return .split(first: a, second: b, ratio: ratio, sideBySide: frozen.map { !$0 })
            }
            return .split(first: toggled(a), second: toggled(b), ratio: ratio, sideBySide: frozen)
        }
        self.root = toggled(root)
    }

    public mutating func equalize() {
        guard let root else { return }
        func even(_ node: Node) -> Node {
            guard case .split(let a, let b, _, let frozen) = node else { return node }
            return .split(first: even(a), second: even(b), ratio: 0.5, sideBySide: frozen)
        }
        self.root = even(root)
    }

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

    public mutating func resize(_ id: ID, to frame: CGRect, in area: CGRect, gaps: Gaps = .none) {
        guard let root, let tile = tiles(in: area, gaps: gaps)[id] else { return }
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

    public mutating func grow(_ id: ID, by delta: CGSize, in area: CGRect, gaps: Gaps = .none) {
        guard let tile = tiles(in: area, gaps: gaps)[id] else { return }
        let bounds = area.insetBy(dx: gaps.outer, dy: gaps.outer)
        var frame = tile
        if delta.width != 0 {
            if tile.maxX < bounds.maxX - 1 {
                frame.size.width += delta.width
            } else if tile.minX > bounds.minX + 1 {
                frame.origin.x -= delta.width
                frame.size.width += delta.width
            }
        }
        if delta.height != 0 {
            if tile.maxY < bounds.maxY - 1 {
                frame.size.height += delta.height
            } else if tile.minY > bounds.minY + 1 {
                frame.origin.y -= delta.height
                frame.size.height += delta.height
            }
        }
        resize(id, to: frame, in: area, gaps: gaps)
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

extension DwindleTree.Node: Codable where ID: Codable {}
extension DwindleTree: Codable where ID: Codable {}
