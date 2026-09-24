public enum DiagnosticFormatter {
    public static func format(_ diagnostic: Diagnostic, sourceText: (String) -> String?) -> String {
        var lines = [header(diagnostic)]
        var gutter = 5
        if let span = diagnostic.span, !span.isSynthetic, let text = sourceText(span.file) {
            let locator = SourceLocator(text)
            if let content = locator.lineText(span.start.line) {
                let number = String(span.start.line)
                gutter = max(5, number.count)
                lines.append(String(repeating: " ", count: gutter - number.count) + number + " | " + content)
                lines.append(String(repeating: " ", count: gutter) + " | " + marker(for: span, in: content))
            }
        }
        let indent = String(repeating: " ", count: gutter + 1)
        if let help = diagnostic.help {
            lines.append(indent + "= help: " + help)
        }
        for note in diagnostic.notes {
            var line = indent + "= note: " + note.message
            if let span = note.span {
                line += " (" + location(span) + ")"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static func location(_ span: SourceSpan) -> String {
        span.isSynthetic ? span.file : "\(span.file):\(span.start.line):\(span.start.column)"
    }

    static func header(_ diagnostic: Diagnostic) -> String {
        let text = diagnostic.severity.label + ": " + diagnostic.message
        guard let span = diagnostic.span else { return text }
        return location(span) + ": " + text
    }

    static func marker(for span: SourceSpan, in content: String) -> String {
        let characters = Array(content)
        let startIndex = max(0, span.start.column - 1)
        var prefix = ""
        for character in characters.prefix(startIndex) {
            prefix.append(character == "\t" ? "\t" : " ")
        }
        if startIndex > characters.count {
            prefix += String(repeating: " ", count: startIndex - characters.count)
        }
        let width: Int
        if span.end.line == span.start.line {
            width = span.end.column - span.start.column
        } else {
            width = characters.count - startIndex
        }
        return prefix + String(repeating: "^", count: max(1, width))
    }
}
