public struct SourcePosition: Sendable, Hashable, Comparable {
    public var offset: Int
    public var line: Int
    public var column: Int

    public init(offset: Int, line: Int, column: Int) {
        self.offset = offset
        self.line = line
        self.column = column
    }

    public static func < (lhs: SourcePosition, rhs: SourcePosition) -> Bool {
        (lhs.offset, lhs.line, lhs.column) < (rhs.offset, rhs.line, rhs.column)
    }
}

public struct SourceSpan: Sendable, Hashable {
    public var file: String
    public var start: SourcePosition
    public var end: SourcePosition

    public init(file: String, start: SourcePosition, end: SourcePosition) {
        self.file = file
        self.start = start
        self.end = end
    }

    public static func synthetic(_ file: String = "<generated>") -> SourceSpan {
        let origin = SourcePosition(offset: 0, line: 0, column: 0)
        return SourceSpan(file: file, start: origin, end: origin)
    }

    public var isSynthetic: Bool {
        start.line == 0
    }
}
