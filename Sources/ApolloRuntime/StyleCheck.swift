import Foundation
import ApolloBase
import ApolloConfig
import ApolloStyle

public enum StyleCheck {
    public static func run(_ ir: ConfigIR) -> [Diagnostic] {
        var r: [Diagnostic] = []
        for ref in ir.styleSheets {
            guard let text = try? String(contentsOf: ref.url, encoding: .utf8) else {
                r.append(Diagnostic(.warning, "cannot read style sheet \(ref.url.path)", span: ref.span, code: .fileUnreadable))
                continue
            }
            let (sheet, found) = StyleSheet.parse(text, file: ref.url.path, origin: .config, assetRoot: ref.url.deletingLastPathComponent())
            r += found + sheet.fallbackProblems()
        }
        return r
    }
}
