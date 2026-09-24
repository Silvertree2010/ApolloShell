import ApolloBase

struct DiagnosticReport: Sendable {
    var diagnostics: [Diagnostic]
    var stageCounts: [String: Int]
    var totalCounts: [Severity: Int]

    var hasErrors: Bool {
        (totalCounts[.error] ?? 0) > 0
    }
}

struct DiagnosticCollector {
    let limit: Int
    private var buckets: [Severity: [Diagnostic]] = [.error: [], .warning: [], .note: []]
    private var totalCounts: [Severity: Int] = [.error: 0, .warning: 0, .note: 0]
    private var stageCounts: [String: Int] = [:]
    private var fileOrder: [String: Int] = [:]

    init(limit: Int = 200) {
        self.limit = limit
    }

    mutating func add(_ diagnostic: Diagnostic, stage: String, includeChain: [SourceSpan] = []) {
        stageCounts[stage, default: 0] += 1
        let enriched = DiagnosticCollector.withIncludeChain(diagnostic, chain: includeChain)
        registerFile(of: enriched)
        totalCounts[enriched.severity, default: 0] += 1
        insert(enriched)
    }

    func finalize() -> DiagnosticReport {
        var result: [Diagnostic] = []
        for severity in [Severity.error, .warning, .note] {
            result.append(contentsOf: buckets[severity] ?? [])
        }
        let total = totalCounts.values.reduce(0, +)
        if result.count > limit {
            result = Array(result.prefix(limit))
        }
        if total > limit {
            result.append(Diagnostic(.note, "and \(total - limit) more"))
        }
        return DiagnosticReport(diagnostics: result, stageCounts: stageCounts, totalCounts: totalCounts)
    }

    private mutating func registerFile(of diagnostic: Diagnostic) {
        guard let span = diagnostic.span, !span.isSynthetic, fileOrder[span.file] == nil else { return }
        fileOrder[span.file] = fileOrder.count
    }

    private mutating func insert(_ diagnostic: Diagnostic) {
        let key = sortKey(diagnostic)
        var bucket = buckets[diagnostic.severity] ?? []
        let index = bucket.firstIndex { sortKey($0) > key } ?? bucket.count
        bucket.insert(diagnostic, at: index)
        if bucket.count > limit {
            bucket.removeLast()
        }
        buckets[diagnostic.severity] = bucket
    }

    private func sortKey(_ diagnostic: Diagnostic) -> (Int, Int, Int) {
        guard let span = diagnostic.span, !span.isSynthetic else { return (Int.max, 0, 0) }
        return (fileOrder[span.file] ?? Int.max, span.start.line, span.start.column)
    }

    static func location(_ span: SourceSpan) -> String {
        span.isSynthetic ? span.file : "\(span.file):\(span.start.line):\(span.start.column)"
    }

    static func withIncludeChain(_ diagnostic: Diagnostic, chain: [SourceSpan]) -> Diagnostic {
        guard !chain.isEmpty else { return diagnostic }
        var enriched = diagnostic
        let notes = chain.reversed().map { DiagnosticNote("included from \(DiagnosticCollector.location($0))", span: $0) }
        enriched.notes = notes + enriched.notes
        return enriched
    }
}
