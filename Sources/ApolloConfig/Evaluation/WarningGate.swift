import Synchronization
import ApolloBase

struct WarningKey: Hashable, Sendable {
    let message: String
    let span: SourceSpan?
}

final class WarningGate: Sendable {
    static let capacity = 4096

    private let seen = Mutex<Set<WarningKey>>([])

    func admit(_ diagnostic: Diagnostic) -> Bool {
        seen.withLock { keys in
            guard keys.count < Self.capacity else { return false }
            return keys.insert(WarningKey(message: diagnostic.message, span: diagnostic.span)).inserted
        }
    }
}
