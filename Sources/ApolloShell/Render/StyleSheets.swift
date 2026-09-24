import Foundation
import AppKit
import ApolloBase
import ApolloConfig
import ApolloStyle

enum StyleSheets {
    static func load(_ ir: ConfigIR) -> ([StyleSheet], [Diagnostic]) {
        var sheets = [BaseStyleSheet.sheet]
        var diagnostics: [Diagnostic] = []
        for ref in ir.styleSheets {
            guard let text = try? String(contentsOf: ref.url, encoding: .utf8) else {
                diagnostics.append(Diagnostic(.warning, "cannot read style sheet \(ref.url.path)", span: ref.span))
                continue
            }
            let (sheet, found) = StyleSheet.parse(text, file: ref.url.path, origin: .config, assetRoot: ref.url.deletingLastPathComponent())
            sheets.append(sheet)
            diagnostics += found
        }
        return (sheets, diagnostics)
    }

    static func environment(dark: Bool, tokens: TokenEnvironment = .empty) -> StyleEnvironment {
        StyleEnvironment(appearance: dark ? .dark : .light, reduceMotion: false, reduceTransparency: false, tokens: tokens)
    }

    @MainActor
    static func liveEnvironment(dark: Bool, tokens: TokenEnvironment = .empty) -> StyleEnvironment {
        let workspace = NSWorkspace.shared
        return StyleEnvironment(appearance: dark ? .dark : .light, reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
                                reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency, tokens: tokens)
    }
}
