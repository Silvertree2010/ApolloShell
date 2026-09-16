import Foundation
import ApolloShellCore
import os

/// Laedt und speichert die Nutzungsstatistik lokal unter
/// ~/Library/Application Support/ApolloShell/usage.json.
@MainActor
final class UsageStore {
    private(set) var stats: UsageStats
    private let url: URL
    private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "usage")

    init(url: URL = UsageStore.defaultURL) {
        self.url = url
        let data = try? Data(contentsOf: url)
        if let data, let decoded = try? JSONDecoder().decode(UsageStats.self, from: data) {
            stats = decoded
        } else {
            stats = UsageStats()
            // Da, aber unlesbar: aufheben, bevor der naechste Start sie ersetzt.
            if data != nil {
                NexusFile.preserveUnreadable(url)
                log.error("usage.json unlesbar, Kopie als usage.json.unreadable")
            }
        }
    }

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ApolloShell/usage.json")
    }

    func record(_ key: String) {
        stats.record(key)
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(stats).write(to: url, options: .atomic)
        } catch {
            log.error("usage.json nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }
}
