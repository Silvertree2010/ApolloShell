import Foundation
import ApolloShellCore
import os

/// Laedt und speichert die Nutzungsstatistik lokal unter
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
            // Da, aber unlesbar: aufheben, bevor der naechste Start sie ersetzt.
            if data != nil {
                ShellFiles.preserveUnreadable(url)
                log.error("usage.json unlesbar, Kopie als usage.json.unreadable")
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
            log.error("usage.json nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }
}
