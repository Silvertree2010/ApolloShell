import Foundation

/// Eine Bearbeitung des Kontrollzentrums (globaler Bearbeitungsmodus,
/// `ShellEditor`): die Arbeitskopie des Panels, das gewaehlte Element.
/// "Fertig" uebernimmt `layout`, "Abbrechen" verwirft es (`original`).
public struct UtilitiesEditSession: Equatable, Sendable {
    public let original: UtilitiesLayout
    public private(set) var layout: UtilitiesLayout
    public var selectedToggleID: String? {
        didSet {
            guard selectedToggleID != oldValue else { return }
            pickingShortcut = false
        }
    }
    /// Ob der Kurzbefehl-Picker des gewaehlten Knopfs offen ist (Task 6, Esc
    /// schliesst ihn zuerst) - reine UI-Anzeige wie `selectedToggleID`, nicht
    /// Teil der Kontrollzentrum-Arbeitskopie selbst.
    public var pickingShortcut = false

    public init(layout: UtilitiesLayout) {
        original = layout
        self.layout = layout
    }

    public var hasChanges: Bool { layout != original }

    // MARK: Karten

    public mutating func setCard(_ kind: UtilitiesCardKind, enabled: Bool) {
        layout.setCard(kind, enabled: enabled)
    }

    public mutating func moveCards(fromOffsets source: IndexSet, toOffset destination: Int) {
        layout.moveCards(fromOffsets: source, toOffset: destination)
    }

    // MARK: Schnellschalter

    /// Neuer Knopf, ans Ende; waehlt ihn aus. `nil`: darf es nur einmal geben
    /// und ist schon da - nichts geaendert, nichts ausgewaehlt.
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
