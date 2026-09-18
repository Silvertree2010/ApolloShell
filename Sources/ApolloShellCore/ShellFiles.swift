import Foundation

/// Wo ApolloShell seine Dateien ablegt, an einer Stelle:
/// ~/Library/Application Support/ApolloShell/. Bisher leitete jede Datei den
/// Ordner selbst her, teils ueber eine andere (`PinnedApps.url` aus
/// `UsageStore.defaultURL`).
///
/// Die Namen sind Teil des Formats: bestehende Installationen lesen genau
/// diese Dateien, ein Test haelt sie fest. Nie umbenennen.
public struct ShellFiles: Sendable {
    /// Der Ordner, in dem alle Dateien liegen.
    public let directory: URL

    /// Ein eigener Ordner, z. B. fuer Bildproben und Tests.
    public init(directory: URL) {
        self.directory = directory
    }

    /// Name des Ordners unter Application Support.
    public static let folderName = "ApolloShell"

    /// Der echte Ordner des angemeldeten Benutzers.
    public static var live: ShellFiles {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ShellFiles(directory: support.appendingPathComponent(folderName, isDirectory: true))
    }

    /// Einstellungen (Nexus), siehe `ShellSettings`.
    public var settings: URL { file("settings.json") }
    /// Angeheftete Apps des Launchers.
    public var pinned: URL { file("pinned.json") }
    /// Nutzungsstatistik fuer die Reihenfolge im Launcher.
    public var usage: URL { file("usage.json") }
    /// Wetterorte und Favoriten.
    public var weather: URL { file("weather.json") }
    /// Gesicherte Werte von Apples Dock, solange es versteckt ist.
    public var appleDock: URL { file("apple-dock.json") }
    /// Merker: ApolloShell hat den Ruhezustand bei zugeklapptem Deckel
    /// abgeschaltet und muss ihn wieder einschalten.
    public var lidAwakeMarker: URL { file("lid-awake") }
    /// Ordner mit den Themes, siehe `ThemeLoader`.
    public var themes: URL { ThemeLoader.folder(inApplicationSupport: directory) }

    private func file(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }
}

// MARK: - Lesen und Schreiben

/// Schreiben ohne halbe Dateien. Hiess `NexusFile`, schreibt aber auch fuer
/// Launcher und Wetter.
public extension ShellFiles {
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
