import Foundation

/// An edit of the sidebar (global edit mode, `ShellEditor`): the bar's
/// working copy and the selected block. "Done" adopts `layout`, "Cancel"
/// discards it (`original`).
///
/// The same shape as `UtilitiesEditSession`, and for the same reason: the
/// rules of a bar (unique ids, kinds that may exist only once, where a new
/// block goes) live in `BarLayout`, so this only has to carry the copy and
/// the selection through the mode.
public struct BarEditSession: Equatable, Sendable {
    public let original: BarLayout
    public private(set) var layout: BarLayout
    public var selectedEntryID: String?

    public init(layout: BarLayout) {
        original = layout
        self.layout = layout
    }

    public var hasChanges: Bool { layout != original }

    /// A new block, without `index` at the spot `BarLayout.insertionIndex`
    /// picks; selects it. `nil`: the kind may exist only once and is there
    /// already - then nothing changed and nothing is selected anew.
    @discardableResult
    public mutating func add(_ kind: BarModuleKind, at index: Int? = nil) -> String? {
        guard let id = layout.add(kind, at: index) else { return nil }
        selectedEntryID = id
        return id
    }

    public mutating func remove(id: String) {
        layout.remove(id: id)
        if selectedEntryID == id { selectedEntryID = nil }
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
}
