public struct SourcePosition: Sendable, Hashable, Comparable {
    private var o: Int32
    private var l: Int32
    private var c: Int32

    public var offset: Int {
        get { Int(o) }
        set { o = Int32(clamping: newValue) }
    }

    public var line: Int {
        get { Int(l) }
        set { l = Int32(clamping: newValue) }
    }

    public var column: Int {
        get { Int(c) }
        set { c = Int32(clamping: newValue) }
    }

    public init(offset: Int, line: Int, column: Int) {
        o = Int32(clamping: offset)
        l = Int32(clamping: line)
        c = Int32(clamping: column)
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
