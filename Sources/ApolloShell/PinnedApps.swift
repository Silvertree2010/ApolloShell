import Foundation
import ApolloShellCore
import os

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

    /// Changes the list where the launcher pins and unpins (right click,
    /// dragging). Written atomically right away; a broken file is kept as
    /// pinned.json.unreadable before it gets replaced. Hands back the list
    /// as it is now in the file, `nil` when nothing changed or writing failed.
    @discardableResult
    static func update(at url: URL = ShellFiles.live.pinned, _ change: (inout PinnedList) -> Void) -> [String]? {
        let data = ShellFiles.read(url)
        if PinnedList.isUnreadable(data) {
            ShellFiles.preserveUnreadable(url)
            log.error("pinned.json unreadable, copy kept as pinned.json.unreadable")
        }
        let before = PinnedList.load(from: data)
        var list = before
        change(&list)
        guard list != before else { return nil }
        do {
            try ShellFiles.write(list.encoded(), to: url)
            return list.ids
        } catch {
            log.error("pinned.json not saved: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static let log = Logger(category: "pinned")
}
