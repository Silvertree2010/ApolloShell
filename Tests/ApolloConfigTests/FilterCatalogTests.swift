import Testing
@testable import ApolloConfig

@Suite("Filterkatalog")
struct FilterCatalogTests {
    static let specNames: [String] = [
        "runs",
        "round", "floor", "ceil", "abs", "fixed", "clamp", "min", "max", "scale", "percent", "grouped",
        "bytes", "bytes-per-second", "temperature", "duration", "date", "relative",
        "string", "shell-quote", "upper", "lower", "capitalize", "truncate", "pad", "replace", "split", "starts-with", "ends-with", "json", "number",
        "count", "first", "last", "at", "take", "skip", "slice", "reverse", "sort", "where", "where-not", "map", "join",
        "contains", "index-of", "unique", "index-where", "fuzzy",
        "app-search", "month-grid", "url", "symbol-exists", "chord", "hotkey-warning",
        "default", "bool", "keys", "values",
    ]

    @Test("FilterTable.builtin enthält genau die 58 Filter aus config-language.md 4.5 und runs aus 0.2.1")
    func exactlyTheSpecFilters() {
        #expect(Self.specNames.count == 59)
        #expect(Set(Self.specNames).count == 59)
        #expect(FilterTable.builtin.names == Self.specNames.sorted())
        #expect(BuiltinFilters.all.count == 59)
    }

    @Test("jeder eingebaute Filter hat eine Stellenzahl, die zur Spec passt")
    func arities() {
        let expected: [String: FilterArity] = [
            "round": FilterArity(0, 1), "fixed": FilterArity(1, 1), "clamp": FilterArity(2, 2), "scale": FilterArity(4, 4),
            "percent": FilterArity(0, 1), "grouped": FilterArity(0, 1), "bytes": FilterArity(0, 1), "duration": FilterArity(0, 1),
            "date": FilterArity(1, 2), "relative": FilterArity(0, 0), "truncate": FilterArity(1, 1), "pad": FilterArity(1, 2),
            "replace": FilterArity(2, 2), "sort": FilterArity(0, 2), "where": FilterArity(2, 2), "slice": FilterArity(2, 2),
            "index-where": FilterArity(2, 3), "fuzzy": FilterArity(1, 2), "app-search": FilterArity(1, 1),
            "month-grid": FilterArity(0, 2), "default": FilterArity(1, 1), "join": FilterArity(1, 1), "chord": FilterArity(0, 0),
        ]
        for name in Self.specNames {
            #expect(FilterTable.builtin.arity(named: name) != nil, "\(name)")
        }
        for (name, arity) in expected {
            #expect(FilterTable.builtin.arity(named: name) == arity, "\(name)")
        }
    }
}
