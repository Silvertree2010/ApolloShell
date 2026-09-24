import ApolloBase
import ApolloConfig

struct BindingSource: Sendable {
    var template: StringTemplate
    var dependencies: Set<DependencyPath>
    var localNames: Set<String>
    var span: SourceSpan

    init(template: StringTemplate, localNames: Set<String> = [], span: SourceSpan = .synthetic()) {
        self.template = template
        self.localNames = localNames
        self.dependencies = template.dependencies(locals: localNames)
        self.span = span
    }

    var isConstant: Bool {
        dependencies.isEmpty
    }
}

enum BindingRank: Comparable, Sendable {
    case derived(order: Int)
    case structure(depth: Int)
    case property

    private var tier: Int {
        switch self {
        case .derived: 0
        case .structure: 1
        case .property: 2
        }
    }

    private var secondary: Int {
        switch self {
        case .derived(let order): order
        case .structure(let depth): depth
        case .property: 0
        }
    }

    static func < (lhs: BindingRank, rhs: BindingRank) -> Bool {
        (lhs.tier, lhs.secondary) < (rhs.tier, rhs.secondary)
    }
}
