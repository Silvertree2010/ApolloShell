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
                diagnostics.append(Diagnostic(.warning, "cannot read style sheet \(ref.url.path)", span: ref.span, code: .fileUnreadable))
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
    static func liveEnvironment(dark: Bool, tokens: TokenEnvironment = .empty, accessibility: LiveAccessibility = .current()) -> StyleEnvironment {
        StyleEnvironment(appearance: dark ? .dark : .light, reduceMotion: accessibility.reduceMotion,
                         reduceTransparency: accessibility.reduceTransparency, tokens: tokens)
    }
}

struct LiveAccessibility: Equatable {
    var reduceMotion: Bool
    var reduceTransparency: Bool

    @MainActor
    static func current() -> LiveAccessibility {
        let workspace = NSWorkspace.shared
        return LiveAccessibility(reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
                                 reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency)
    }
}
