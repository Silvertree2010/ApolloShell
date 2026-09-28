import ApolloBase
import Synchronization

final class TemplateCache: Sendable {
    private struct Key: Hashable {
        var text: String
        var span: SourceSpan
    }

    private struct Storage {
        var templates: [Key: Result<StringTemplate, Diagnostic>] = [:]
        var occurrences: [Key: [String: [NameOccurrence]]] = [:]
        var userFilters: [String: UserFilter] = [:]
    }

    private let storage = Mutex(Storage())

    func template(_ text: String, span: SourceSpan) -> Result<StringTemplate, Diagnostic> {
        let key = Key(text: text, span: span)
        if let cached = storage.withLock({ $0.templates[key] }) { return cached }
        let parsed = ExpressionParser.parseTemplate(text, span: span)
        storage.withLock { $0.templates[key] = parsed }
        return parsed
    }

    var userFilters: [String: UserFilter] {
        get { storage.withLock { $0.userFilters } }
        set { storage.withLock { $0.userFilters = newValue } }
    }

    func occurrences(in text: String, span: SourceSpan) -> [String: [NameOccurrence]] {
        let key = Key(text: text, span: span)
        if let cached = storage.withLock({ $0.occurrences[key] }) { return cached }
        let found = NameLocator.occurrences(in: text, span: span)
        storage.withLock { $0.occurrences[key] = found }
        return found
    }
}
