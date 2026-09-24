import Foundation
import ApolloShellCore

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
