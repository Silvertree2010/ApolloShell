import Foundation
import ApolloShellCore
import Observation
import os

/// Where Nexus reads and writes. Injectable, so that image samples and
/// development never touch the real files: `nil` means "in memory only".
struct NexusPaths: Sendable {
    var settings: URL?
    var pinned: URL?
    var weather: URL?

    /// The files in `files`, with the same names as the real ones.
    init(_ files: ShellFiles) {
        self.init(settings: files.settings, pinned: files.pinned, weather: files.weather)
    }

    init(settings: URL?, pinned: URL?, weather: URL?) {
        self.settings = settings
        self.pinned = pinned
        self.weather = weather
    }

    /// The real files - the same ones the launcher and the weather read.
    static var live: NexusPaths { NexusPaths(.live) }

    /// Everything in a folder of its own (image samples, experiments).
    static func directory(_ url: URL) -> NexusPaths {
        NexusPaths(ShellFiles(directory: url))
    }

    static let inMemory = NexusPaths(settings: nil, pinned: nil, weather: nil)
}

/// The settings of the shell, once for the whole app (AppDelegate holds them).
/// The bar and Nexus read `settings` in SwiftUI - the observation redraws them
/// on every change; toasts ask at the moment of the event; the desktop clock
/// watches with `Observations`. That way every switch holds right away,
/// without a restart and without a notification path of its own.
///
/// It is read once on the start. Whoever changes settings.json by hand needs a
/// restart - it is edited through Nexus.
@MainActor
@Observable
final class ShellSettingsStore {
    var settings: ShellSettings {
        didSet {
            // Stayed the same (a switch back to the old value in the same
            // round, say): write nothing.
            if settings != oldValue { save() }
        }
    }

    /// The last write attempt failed - Nexus shows it.
    private(set) var saveFailed = false

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private let log = Logger(category: "settings")

    /// `url == nil`: in memory only, never writes.
    init(url: URL?) {
        self.url = url
        let data = ShellFiles.read(url)
        if let url, let data, !ShellFiles.isJSONObject(data) {
            ShellFiles.preserveUnreadable(url)
            log.error("settings.json unlesbar, Kopie als settings.json.unreadable")
        }
        settings = ShellSettings.load(from: data)
    }

    /// For image samples: a fixed state, no file.
    static func preview(_ settings: ShellSettings = ShellSettings()) -> ShellSettingsStore {
        let store = ShellSettingsStore(url: nil)
        store.settings = settings
        return store
    }

    private func save() {
        guard let url else { return }
        do {
            try ShellFiles.write(settings.encoded(), to: url)
            if saveFailed { saveFailed = false }
        } catch {
            saveFailed = true
            log.error("settings.json nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }
}
