enum BuiltinFilters {
    static let all: [BuiltinFilter] = NumberFilters.all
        + UnitFilters.all
        + StringFilters.all
        + ListShapeFilters.all
        + ListSearchFilters.all
        + OtherFilters.all
        + DomainFilters.all
        + CanvasFilters.all
        + RunFilters.all

    static var entries: [String: FilterTable.Entry] {
        var result: [String: FilterTable.Entry] = [:]
        for filter in all {
            result[filter.name] = FilterTable.Entry(
                function: { input, arguments, context in filter.run(input, arguments, context) },
                arity: filter.arity
            )
        }
        return result
    }
}
