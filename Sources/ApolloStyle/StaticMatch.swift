import Foundation

public struct StaticSubject: Sendable, Hashable {
    public var kind: String
    public var id: String?
    public var anyID: Bool
    public var classes: Set<String>
    public var anyClass: Bool

    public init(kind: String, id: String? = nil, anyID: Bool = false, classes: Set<String> = [], anyClass: Bool = false) {
        self.kind = kind
        self.id = id
        self.anyID = anyID
        self.classes = classes
        self.anyClass = anyClass
    }
}

extension CompoundSelector {
    func mayMatch(_ subject: StaticSubject) -> Bool {
        if let kind, kind != subject.kind.lowercased() { return false }
        if let id, !subject.anyID, id != subject.id { return false }
        if !subject.anyClass, !classes.allSatisfy(subject.classes.contains) { return false }
        return true
    }
}

extension StyleEngine {
    public func mayDeclare(_ property: String, _ subject: StaticSubject) -> Bool {
        sheets.contains { sheet in
            sheet.rules.contains { rule in
                rule.declarations.contains { declaration in
                    (declaration.property == property || declaration.property.hasPrefix(property + "-"))
                        && declaration.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "none"
                } && rule.selectors.contains { $0.compounds.last?.mayMatch(subject) ?? false }
            }
        }
    }

    public func mayMatch(_ state: PseudoState, _ subject: StaticSubject) -> Bool {
        sheets.contains { sheet in
            sheet.rules.contains { rule in
                !rule.declarations.isEmpty && rule.selectors.contains { selector in
                    guard let last = selector.compounds.last else { return false }
                    return !last.pseudo.isDisjoint(with: state) && last.mayMatch(subject)
                }
            }
        }
    }
}
