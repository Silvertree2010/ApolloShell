public struct KDLEditor: Sendable {
    public private(set) var text: String
    public private(set) var document: KDLDocument
    let newline: String

    public init(_ document: KDLDocument) {
        self.document = document
        self.text = document.text
        self.newline = KDLEditor.firstNewline(in: document.text)
    }

    public mutating func replace(at path: KDLNodePath, with node: KDLNode) throws(KDLEditError) {
        let old = try existingNode(at: path)
        let source = KDLSource(text)
        let layout = KDLLineRange.layout(in: source, start: old.span.start.offset, end: old.span.end.offset)
        let piece = KDLWriter.render(node, indent: layout.lineIndent, indentUnit: indentUnit(source: source), newline: newline)
        var expected = document.nodes
        KDLEditor.mutateSiblings(&expected, path: path[...]) { siblings, index in
            siblings[index] = node
        }
        try commit(replacing: layout.start..<layout.end, with: piece, expected: expected)
    }

    public mutating func insert(_ node: KDLNode, after path: KDLNodePath) throws(KDLEditError) {
        let sibling = try existingNode(at: path)
        var expected = document.nodes
        KDLEditor.mutateSiblings(&expected, path: path[...]) { siblings, index in
            siblings.insert(node, at: index + 1)
        }
        let source = KDLSource(text)
        let layout = KDLLineRange.layout(in: source, start: sibling.span.start.offset, end: sibling.span.end.offset)
        let rendered = KDLWriter.render(node, indent: layout.lineIndent, indentUnit: indentUnit(source: source), newline: newline)
        switch layout.tail {
        case .lineEnd(_, let afterBreak) where layout.ownLine:
            try commit(replacing: afterBreak..<afterBreak, with: layout.lineIndent + rendered + newline, expected: expected)
        case .endOfFile(let fileEnd) where layout.ownLine:
            try commit(replacing: fileEnd..<fileEnd, with: newline + layout.lineIndent + rendered, expected: expected)
        default:
            try commit(replacing: layout.end..<layout.end, with: "; " + rendered, expected: expected)
        }
    }

    public mutating func insert(_ node: KDLNode, intoChildrenOf parent: KDLNodePath?, at index: Int) throws(KDLEditError) {
        let siblings: [KDLNode]
        if let parent {
            siblings = try existingNode(at: parent).children ?? []
        } else {
            siblings = document.nodes
        }
        guard index >= 0, index <= siblings.count else {
            throw KDLEditError(message: "index \(index) is outside the \(siblings.count) children")
        }
        if index > 0 {
            try insert(node, after: (parent ?? []) + [index - 1])
            return
        }
        var expected = document.nodes
        KDLEditor.mutateChildren(&expected, parent: (parent ?? [])[...]) { children in
            children.insert(node, at: 0)
        }
        let source = KDLSource(text)
        let unit = indentUnit(source: source)
        if let first = siblings.first {
            let layout = KDLLineRange.layout(in: source, start: first.span.start.offset, end: first.span.end.offset)
            let rendered = KDLWriter.render(node, indent: layout.lineIndent, indentUnit: unit, newline: newline)
            if layout.ownLine {
                try commit(replacing: layout.lineStart..<layout.lineStart, with: layout.lineIndent + rendered + newline, expected: expected)
            } else {
                try commit(replacing: layout.start..<layout.start, with: rendered + "; ", expected: expected)
            }
            return
        }
        guard let parent else {
            let end = source.count
            let needsBreak = end > source.bomLength && source.lineStart(before: end) != end
            let rendered = KDLWriter.render(node, indent: "", indentUnit: unit, newline: newline)
            try commit(replacing: end..<end, with: (needsBreak ? newline : "") + rendered + newline, expected: expected)
            return
        }
        let owner = try existingNode(at: parent)
        let ownerLayout = KDLLineRange.layout(in: source, start: owner.span.start.offset, end: owner.span.end.offset)
        let childIndent = ownerLayout.lineIndent + unit
        let rendered = KDLWriter.render(node, indent: childIndent, indentUnit: unit, newline: newline)
        if let braces = owner.childrenBlock {
            let interior = (braces.lowerBound + 1)..<(braces.upperBound - 1)
            if KDLEditor.isBlank(source, interior) {
                try commit(replacing: interior, with: newline + childIndent + rendered + newline + ownerLayout.lineIndent, expected: expected)
            } else {
                try commit(replacing: interior.lowerBound..<interior.lowerBound, with: newline + childIndent + rendered + newline, expected: expected)
            }
        } else {
            let block = " {" + newline + childIndent + rendered + newline + ownerLayout.lineIndent + "}"
            try commit(replacing: ownerLayout.end..<ownerLayout.end, with: block, expected: expected)
        }
    }

    public mutating func remove(at path: KDLNodePath) throws(KDLEditError) {
        let old = try existingNode(at: path)
        var expected = document.nodes
        KDLEditor.mutateSiblings(&expected, path: path[...]) { siblings, index in
            siblings.remove(at: index)
        }
        try commit(replacing: old.lineRange, with: "", expected: expected)
    }

    mutating func commit(replacing range: Range<Int>, with piece: String, expected: [KDLNode]) throws(KDLEditError) {
        var bytes = Array(text.utf8)
        guard range.lowerBound >= 0, range.upperBound <= bytes.count else {
            throw KDLEditError(message: "the edit range \(range) lies outside the file")
        }
        bytes.replaceSubrange(range, with: Array(piece.utf8))
        let newText = String(decoding: bytes, as: UTF8.self)
        let reparsed: KDLDocument
        do throws(KDLParseError) {
            reparsed = try KDLDocument.parse(newText, file: document.file)
        } catch {
            throw KDLEditError(message: "the edit would break the file: \(error.message)")
        }
        guard KDLNode.areEquivalent(reparsed.nodes, expected) else {
            throw KDLEditError(message: "the edited file would not contain the expected nodes")
        }
        text = newText
        document = reparsed
    }

    func existingNode(at path: KDLNodePath) throws(KDLEditError) -> KDLNode {
        guard let first = path.first, document.nodes.indices.contains(first) else {
            throw KDLEditError(message: "there is no node at \(path)")
        }
        var current = document.nodes[first]
        for index in path.dropFirst() {
            guard let children = current.children, children.indices.contains(index) else {
                throw KDLEditError(message: "there is no node at \(path)")
            }
            current = children[index]
        }
        return current
    }

    func indentUnit(source: KDLSource) -> String {
        KDLEditor.findIndentUnit(document.nodes, source: source) ?? "    "
    }

    static func findIndentUnit(_ nodes: [KDLNode], source: KDLSource) -> String? {
        for node in nodes {
            guard let children = node.children, let first = children.first else { continue }
            let parent = KDLLineRange.layout(in: source, start: node.span.start.offset, end: node.span.end.offset)
            let child = KDLLineRange.layout(in: source, start: first.span.start.offset, end: first.span.end.offset)
            if parent.indentOnly, child.indentOnly,
               child.lineIndent.count > parent.lineIndent.count,
               child.lineIndent.hasPrefix(parent.lineIndent) {
                return String(child.lineIndent.dropFirst(parent.lineIndent.count))
            }
            if let nested = findIndentUnit(children, source: source) {
                return nested
            }
        }
        return nil
    }

    static func firstNewline(in text: String) -> String {
        let source = KDLSource(text)
        var index = 0
        while index < source.count {
            if let length = source.newlineLength(at: index) {
                return source.string(from: index, to: index + length)
            }
            index += source.decoded(at: index)?.length ?? 1
        }
        return "\n"
    }

    static func isBlank(_ source: KDLSource, _ range: Range<Int>) -> Bool {
        var index = range.lowerBound
        while index < range.upperBound {
            guard let decoded = source.decoded(at: index),
                  KDLCharacters.isUnicodeSpace(decoded.scalar) || KDLCharacters.isNewline(decoded.scalar)
            else { return false }
            index += decoded.length
        }
        return true
    }

    static func mutateSiblings(_ nodes: inout [KDLNode], path: ArraySlice<Int>, _ body: (inout [KDLNode], Int) -> Void) {
        guard let first = path.first else { return }
        if path.count == 1 {
            body(&nodes, first)
            return
        }
        var children = nodes[first].children ?? []
        mutateSiblings(&children, path: path.dropFirst(), body)
        nodes[first].children = children
    }

    static func mutateChildren(_ nodes: inout [KDLNode], parent: ArraySlice<Int>, _ body: (inout [KDLNode]) -> Void) {
        guard let first = parent.first else {
            body(&nodes)
            return
        }
        var children = nodes[first].children ?? []
        if parent.count == 1 {
            body(&children)
        } else {
            mutateChildren(&children, parent: parent.dropFirst(), body)
        }
        nodes[first].children = children
    }
}
