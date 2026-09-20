import Foundation
import ApolloShellCore
import os

/// Loads and saves the usage statistics locally at
/// ~/Library/Application Support/ApolloShell/usage.json.
@MainActor
final class UsageStore {
    private(set) var stats: UsageStats
    private let url: URL
    private let log = Logger(category: "usage")

    init(url: URL = ShellFiles.live.usage) {
        self.url = url
        let data = try? Data(contentsOf: url)
        if let data, let decoded = try? JSONDecoder().decode(UsageStats.self, from: data) {
            stats = decoded
        } else {
            stats = UsageStats()
            // There, but unreadable: keep it before the next launch replaces it.
            if data != nil {
                ShellFiles.preserveUnreadable(url)
                log.error("usage.json unreadable, copy saved as usage.json.unreadable")
            }
        }
    }

    func record(_ key: String) {
        stats.record(key)
        save()
    }

    private func save() {
        do {
            try ShellFiles.write(JSONEncoder().encode(stats), to: url)
        } catch {
            log.error("usage.json not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
