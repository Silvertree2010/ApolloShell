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

    /// Die echten Dateien - dieselben, die Launcher und Wetter lesen.
    static var live: NexusPaths {
        NexusPaths(
            settings: PinnedApps.url.deletingLastPathComponent().appendingPathComponent("settings.json"),
            pinned: PinnedApps.url,
            weather: WeatherModel.locationFileURL
        )
    }

    /// Alles in einem eigenen Ordner (Bildproben, Versuche).
    static func directory(_ url: URL) -> NexusPaths {
        NexusPaths(
            settings: url.appendingPathComponent("settings.json"),
            pinned: url.appendingPathComponent("pinned.json"),
            weather: url.appendingPathComponent("weather.json")
        )
    }

    static let inMemory = NexusPaths(settings: nil, pinned: nil, weather: nil)
}

/// Schreiben ohne halbe Dateien.
enum NexusFile {
    /// `.atomic`: erst in eine Nachbardatei, dann umbenennen. Launcher und
    /// Wetter lesen ihre Datei bei jedem Oeffnen - sie sehen die alte oder
    /// die neue, nie eine halb geschriebene.
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func read(_ url: URL?) -> Data? {
        url.flatMap { try? Data(contentsOf: $0) }
    }

    /// Eine Datei, die nicht zu lesen war, neben das Original kopieren
    /// (`<Name>.unreadable`), bevor das naechste Speichern sie ersetzt. Wer
    /// sie von Hand kaputt bearbeitet hat, verliert so nichts.
    static func preserveUnreadable(_ url: URL) {
        let copy = url.appendingPathExtension("unreadable")
        try? FileManager.default.removeItem(at: copy)
        try? FileManager.default.copyItem(at: url, to: copy)
    }

    /// Ist das ueberhaupt ein JSON-Objekt? Einzelne falsche Werte liest
    /// ShellSettings nachsichtig; hier geht es um eine ganz kaputte Datei.
    static func isJSONObject(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }
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
        let data = NexusFile.read(url)
        if let url, let data, !NexusFile.isJSONObject(data) {
            NexusFile.preserveUnreadable(url)
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
            try NexusFile.write(settings.encoded(), to: url)
            if saveFailed { saveFailed = false }
        } catch {
            saveFailed = true
            log.error("settings.json nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }
}
