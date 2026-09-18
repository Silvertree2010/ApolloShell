import Foundation
import ApolloShellCore
import Observation
import os

/// Wo Nexus liest und schreibt. Einspritzbar, damit Bildproben und
/// Entwicklung nie die echten Dateien anfassen: `nil` heisst "nur im Speicher".
struct NexusPaths: Sendable {
    var settings: URL?
    var pinned: URL?
    var weather: URL?

    /// Die Dateien in `files`, mit denselben Namen wie die echten.
    init(_ files: ShellFiles) {
        self.init(settings: files.settings, pinned: files.pinned, weather: files.weather)
    }

    init(settings: URL?, pinned: URL?, weather: URL?) {
        self.settings = settings
        self.pinned = pinned
        self.weather = weather
    }

    /// Die echten Dateien - dieselben, die Launcher und Wetter lesen.
    static var live: NexusPaths { NexusPaths(.live) }

    /// Alles in einem eigenen Ordner (Bildproben, Versuche).
    static func directory(_ url: URL) -> NexusPaths {
        NexusPaths(ShellFiles(directory: url))
    }

    static let inMemory = NexusPaths(settings: nil, pinned: nil, weather: nil)
}

/// Die Einstellungen der Shell, einmal fuer die ganze App (AppDelegate haelt
/// sie). Leiste und Nexus lesen `settings` in SwiftUI - die Beobachtung
/// zeichnet sie bei jeder Aenderung neu; Kurzmeldungen fragen im Moment des
/// Ereignisses; die Schreibtisch-Uhr beobachtet mit `Observations`. So gilt
/// jeder Schalter sofort, ohne Neustart und ohne eigenen Benachrichtigungsweg.
///
/// Gelesen wird einmal beim Start. Wer settings.json von Hand aendert,
/// braucht einen Neustart - bearbeitet wird sie ueber Nexus.
@MainActor
@Observable
final class ShellSettingsStore {
    var settings: ShellSettings {
        didSet {
            // Gleich geblieben (z. B. Schalter zurueck auf den alten Wert
            // in derselben Runde): nichts schreiben.
            if settings != oldValue { save() }
        }
    }

    /// Letzter Schreibversuch gescheitert - Nexus zeigt es an.
    private(set) var saveFailed = false

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "settings")

    /// `url == nil`: nur im Speicher, schreibt nie.
    init(url: URL?) {
        self.url = url
        let data = ShellFiles.read(url)
        if let url, let data, !ShellFiles.isJSONObject(data) {
            ShellFiles.preserveUnreadable(url)
            log.error("settings.json unlesbar, Kopie als settings.json.unreadable")
        }
        settings = ShellSettings.load(from: data)
    }

    /// Fuer Bildproben: fester Stand, keine Datei.
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
