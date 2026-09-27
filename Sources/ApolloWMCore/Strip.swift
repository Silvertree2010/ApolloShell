#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

public struct Strip<ID: Hashable & Sendable>: Sendable, Equatable where ID: Equatable {
    public struct Column: Sendable, Equatable {
        public var windows: [ID]
        public var width: CGFloat
        public var active: ID

        public init(windows: [ID], width: CGFloat, active: ID) {
            self.windows = windows
            self.width = width
            self.active = active
        }
    }

    public static var widthPresets: [CGFloat] { [1.0 / 3, 0.5, 2.0 / 3, 1.0] }

    public private(set) var columns: [Column] = []
    public private(set) var offset: CGFloat = 0
    public private(set) var focusedColumn = 0

    public var centerFocused = false

    public init() {}

    public var isEmpty: Bool { columns.isEmpty }

    public var ids: [ID] { columns.flatMap(\.windows) }

    public func contains(_ id: ID) -> Bool { columns.contains { $0.windows.contains(id) } }

    public var focused: ID? {
        columns.indices.contains(focusedColumn) ? columns[focusedColumn].active : nil
    }

    public func column(of id: ID) -> Int? {
        columns.firstIndex { $0.windows.contains(id) }
    }

    public mutating func insert(_ id: ID, width: CGFloat = 0.5) {
        guard !contains(id) else { return }
        let index = columns.isEmpty ? 0 : focusedColumn + 1
        columns.insert(Column(windows: [id], width: clampWidth(width), active: id), at: index)
        focusedColumn = index
    }

    public mutating func stack(_ id: ID, intoColumnOf other: ID) {
        guard !contains(id), let index = column(of: other) else { return }
        var column = columns[index]
        let at = (column.windows.firstIndex(of: other) ?? column.windows.count - 1) + 1
        column.windows.insert(id, at: at)
        column.active = id
        columns[index] = column
        focusedColumn = index
    }

    public mutating func remove(_ id: ID) {
        guard let index = column(of: id) else { return }
        var column = columns[index]
        column.windows.removeAll { $0 == id }
        if column.windows.isEmpty {
            columns.remove(at: index)
            if index < focusedColumn { focusedColumn -= 1 }
            focusedColumn = min(focusedColumn, max(columns.count - 1, 0))
        } else {
            if column.active == id { column.active = column.windows[0] }
            columns[index] = column
        }
    }

    public mutating func focus(_ id: ID) {
        guard let index = column(of: id) else { return }
        columns[index].active = id
        focusedColumn = index
    }

    @discardableResult
    public mutating func focusColumn(next: Bool) -> ID? {
        guard !columns.isEmpty else { return nil }
        let index = focusedColumn + (next ? 1 : -1)
        guard columns.indices.contains(index) else { return focused }
        focusedColumn = index
        return focused
    }

    @discardableResult
    public mutating func focusInColumn(next: Bool) -> ID? {
        guard columns.indices.contains(focusedColumn) else { return nil }
        var column = columns[focusedColumn]
        guard let at = column.windows.firstIndex(of: column.active) else { return nil }
        let index = at + (next ? 1 : -1)
        guard column.windows.indices.contains(index) else { return column.active }
        column.active = column.windows[index]
        columns[focusedColumn] = column
        return column.active
    }

    public mutating func moveColumn(next: Bool) {
        let index = focusedColumn + (next ? 1 : -1)
        guard columns.indices.contains(focusedColumn), columns.indices.contains(index) else { return }
        columns.swapAt(focusedColumn, index)
        focusedColumn = index
    }

    public mutating func moveInColumn(_ id: ID, next: Bool) {
        guard let index = column(of: id) else { return }
        var column = columns[index]
        guard let at = column.windows.firstIndex(of: id) else { return }
        let to = at + (next ? 1 : -1)
        guard column.windows.indices.contains(to) else { return }
        column.windows.swapAt(at, to)
        columns[index] = column
    }

    public mutating func expel(_ id: ID) {
        guard let index = column(of: id), columns[index].windows.count > 1 else { return }
        let width = columns[index].width
        remove(id)
        let at = min(index + 1, columns.count)
        columns.insert(Column(windows: [id], width: width, active: id), at: at)
        focusedColumn = at
    }

    public mutating func moveColumn(of id: ID, nearX x: CGFloat, width area: CGFloat, gaps: Gaps) {
        guard let from = column(of: id) else { return }
        let frames = columnFrames(width: area, gaps: gaps)
        var to = frames.count - 1
        for frame in frames where x < frame.x + frame.width / 2 {
            to = frame.index
            break
        }
        guard to != from else { return }
        let column = columns.remove(at: from)
        columns.insert(column, at: to > from ? to - 1 : to)
        focusedColumn = columns.firstIndex { $0.windows.contains(id) } ?? to
    }

    public mutating func cycleWidth(of id: ID, wider: Bool) {
        guard let index = column(of: id) else { return }
        let presets = Self.widthPresets
        let current = columns[index].width
        let next: CGFloat
        if wider {
            next = presets.first { $0 > current + 0.001 } ?? presets[0]
        } else {
            next = presets.last { $0 < current - 0.001 } ?? presets[presets.count - 1]
        }
        columns[index].width = next
    }

    public mutating func setWidth(_ width: CGFloat, of id: ID) {
        guard let index = column(of: id) else { return }
        columns[index].width = clampWidth(width)
    }

    private func clampWidth(_ width: CGFloat) -> CGFloat { min(max(width, 0.1), 1) }

    public func columnFrames(width area: CGFloat, gaps: Gaps) -> [(index: Int, x: CGFloat, width: CGFloat)] {
        var x: CGFloat = 0
        var result: [(Int, CGFloat, CGFloat)] = []
        for (index, column) in columns.enumerated() {
            let columnWidth = (area * column.width).rounded()
            result.append((index, x, columnWidth))
            x += columnWidth + gaps.inner
        }
        return result
    }

    public func length(width area: CGFloat, gaps: Gaps) -> CGFloat {
        guard let last = columnFrames(width: area, gaps: gaps).last else { return 0 }
        return last.x + last.width
    }

    public mutating func scrollToFocused(area: CGRect, gaps: Gaps) {
        let inner = area.insetBy(dx: gaps.outer, dy: gaps.outer)
        let frames = columnFrames(width: inner.width, gaps: gaps)
        guard frames.indices.contains(focusedColumn) else { return }
        let column = frames[focusedColumn]
        if centerFocused {
            offset = column.x - (inner.width - column.width) / 2
        } else if column.x < offset {
            offset = column.x
        } else if column.x + column.width > offset + inner.width {
            offset = column.x + column.width - inner.width
        }
        clampOffset(area: area, gaps: gaps)
    }

    public mutating func scroll(by delta: CGFloat, area: CGRect, gaps: Gaps) {
        offset += delta
        clampOffset(area: area, gaps: gaps)
    }

    private mutating func clampOffset(area: CGRect, gaps: Gaps) {
        let inner = area.insetBy(dx: gaps.outer, dy: gaps.outer)
        let total = length(width: inner.width, gaps: gaps)
        let highest = max(total - inner.width, 0)
        offset = min(max(offset, 0), highest)
    }

    public func layout(in area: CGRect, gaps: Gaps,
                       minimums: [ID: CGSize] = [:]) -> [ID: CGRect] {
        let inner = area.insetBy(dx: gaps.outer, dy: gaps.outer)
        var frames: [ID: CGRect] = [:]
        for (index, x, width) in columnFrames(width: inner.width, gaps: gaps) {
            let column = columns[index]
            let count = CGFloat(column.windows.count)
            let height = (inner.height - gaps.inner * (count - 1)) / count
            for (row, id) in column.windows.enumerated() {
                var frame = CGRect(x: inner.minX + x - offset,
                                   y: inner.minY + (height + gaps.inner) * CGFloat(row),
                                   width: width, height: height)
                if let minimum = minimums[id] {
                    frame.size.width = max(frame.width, minimum.width)
                    frame.size.height = max(frame.height, minimum.height)
                }
                frames[id] = frame
            }
        }
        return frames
    }

    public func visible(in area: CGRect, gaps: Gaps) -> Set<ID> {
        var result: Set<ID> = []
        for (id, frame) in layout(in: area, gaps: gaps) where frame.intersects(area) {
            result.insert(id)
        }
        return result
    }
}
