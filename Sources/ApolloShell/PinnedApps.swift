import Foundation
import ApolloShellCore

/// Angeheftete Apps: stehen ohne Suchtext immer ganz oben, in fester
/// Reihenfolge. Liegen als Bundle-IDs in
/// ~/Library/Application Support/ApolloShell/pinned.json:
///
///     { "pinned": ["com.vivaldi.Vivaldi", "net.kovidgoyal.kitty", ...] }
///
/// Wird bei jedem Oeffnen neu gelesen, Aenderungen gelten also sofort.
/// Fehlt die Datei oder ist sie kaputt, gibt es einfach keine Pins.
enum PinnedApps {
    private struct File: Decodable {
        var pinned: [String]
    }

    static func load(from url: URL = ShellFiles.live.pinned) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [] }
        return file.pinned
    }
}
