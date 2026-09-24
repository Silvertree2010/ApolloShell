extension KDLScalar {
    public func isEquivalent(to other: KDLScalar) -> Bool {
        switch (self, other) {
        case let (.string(lhs), .string(rhs)):
            return lhs == rhs
        case let (.number(lhs, _), .number(rhs, _)):
            return lhs == rhs || (lhs.isNaN && rhs.isNaN)
        case let (.bool(lhs), .bool(rhs)):
            return lhs == rhs
        case (.null, .null):
            return true
        default:
            return false
        }
    }
}

extension KDLValue {
    public func isEquivalent(to other: KDLValue) -> Bool {
        annotation == other.annotation && scalar.isEquivalent(to: other.scalar)
    }
}

extension KDLProperty {
    public func isEquivalent(to other: KDLProperty) -> Bool {
        name == other.name && value.isEquivalent(to: other.value)
    }
}

extension KDLNode {
    public func isEquivalent(to other: KDLNode) -> Bool {
        guard name == other.name,
              annotation == other.annotation,
              arguments.count == other.arguments.count,
              properties.count == other.properties.count
        else { return false }
        for (lhs, rhs) in zip(arguments, other.arguments) where !lhs.isEquivalent(to: rhs) {
            return false
        }
        for (lhs, rhs) in zip(properties, other.properties) where !lhs.isEquivalent(to: rhs) {
            return false
        }
        switch (children, other.children) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return KDLNode.areEquivalent(lhs, rhs)
        default:
            return false
        }
    }

    public static func areEquivalent(_ lhs: [KDLNode], _ rhs: [KDLNode]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) where !left.isEquivalent(to: right) {
            return false
        }
        return true
    }
}
