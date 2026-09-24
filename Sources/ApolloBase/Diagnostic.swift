public enum Severity: Int, Sendable, Hashable, Comparable {
    case note
    case warning
    case error

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .note: return "note"
        case .warning: return "warning"
        case .error: return "error"
        }
    }
}

public struct DiagnosticNote: Sendable, Hashable {
    public var message: String
    public var span: SourceSpan?

    public init(_ message: String, span: SourceSpan? = nil) {
        self.message = message
        self.span = span
    }
}

public enum DiagnosticKind: String, Sendable, Hashable {
    case stateFileUnreadable
    case valueDiscarded
}

public struct Diagnostic: Error, Sendable, Hashable {
    public var severity: Severity
    public var message: String
    public var span: SourceSpan?
    public var help: String?
    public var notes: [DiagnosticNote]
    public var kind: DiagnosticKind?

    public init(_ severity: Severity, _ message: String, span: SourceSpan? = nil, help: String? = nil, notes: [DiagnosticNote] = [], kind: DiagnosticKind? = nil) {
        self.severity = severity
        self.message = message
        self.span = span
        self.help = help
        self.notes = notes
        self.kind = kind
    }
}
