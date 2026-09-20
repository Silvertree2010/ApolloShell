import Foundation
import ApolloShellCore

/// Pinned apps: always stay on top without search text, in a fixed
/// order. Kept as bundle IDs in
/// ~/Library/Application Support/ApolloShell/pinned.json:
///
///     { "pinned": ["com.vivaldi.Vivaldi", "net.kovidgoyal.kitty", ...] }
///
/// Reread on every opening, so changes take effect immediately.
/// If the file is missing or broken, there simply are no pins.
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
