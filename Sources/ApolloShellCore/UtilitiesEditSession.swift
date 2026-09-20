import Foundation

/// An edit of the control center (global edit mode, `ShellEditor`): the
/// panel's working copy, the selected element. "Done" adopts `layout`,
/// "Cancel" discards it (`original`).
public struct UtilitiesEditSession: Equatable, Sendable {
    public let original: UtilitiesLayout
    public private(set) var layout: UtilitiesLayout
    public var selectedToggleID: String? {
        didSet {
            guard selectedToggleID != oldValue else { return }
            pickingShortcut = false
        }
    }
    /// Whether the selected toggle's shortcut picker is open (Task 6, Esc
    /// closes it first) - purely UI state like `selectedToggleID`, not part
    /// of the control center's working copy itself.
    public var pickingShortcut = false

    public init(layout: UtilitiesLayout) {
        original = layout
        self.layout = layout
    }

    public var hasChanges: Bool { layout != original }

    // MARK: Cards

    public mutating func setCard(_ kind: UtilitiesCardKind, enabled: Bool) {
        layout.setCard(kind, enabled: enabled)
    }

    public mutating func moveCards(fromOffsets source: IndexSet, toOffset destination: Int) {
        layout.moveCards(fromOffsets: source, toOffset: destination)
    }

    // MARK: Quick toggles

    /// New toggle, appended at the end; selects it. `nil`: it may only
    /// exist once and is already there - nothing changed, nothing selected.
    @discardableResult
    public mutating func add(_ kind: UtilitiesToggleKind) -> String? {
        guard let id = layout.add(kind) else { return nil }
        selectedToggleID = id
        return id
    }

    public mutating func remove(toggle id: String) {
        layout.remove(toggle: id)
        if selectedToggleID == id { selectedToggleID = nil }
    }

    public mutating func update(toggle id: String, to toggle: UtilitiesToggle) {
        layout.update(toggle: id, to: toggle)
    }

    public mutating func moveToggle(_ id: String, onto target: String) {
        layout.moveToggle(id, onto: target)
    }
}
