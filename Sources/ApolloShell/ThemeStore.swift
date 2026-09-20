import AppKit
import ApolloShellCore
import SwiftUI
import os

/// Haelt das gewaehlte Theme und den Inhalt des Theme-Ordners.
///
/// Lesen, Pruefen und Klemmen macht der Kern (`ThemeLoader`, `Theme`); hier
/// steht nur, welches Theme gilt, was im Ordner liegt und wann neu gelesen
/// wird.
///
/// Live: Der Ordner wird beobachtet. Wer eine .css speichert, sieht die
/// Aenderung sofort - so arbeitet man an einem Theme, ohne die Shell neu zu
/// starten. Gesammelt wird kurz (`reloadDelay`), weil ein Editor beim
/// Speichern mehrere Ereignisse ausloest.
@MainActor
@Observable
final class ThemeStore {
    /// Das gewaehlte Theme, fertig geprueft. Ohne Wahl: die Vorgaben.
    private(set) var theme: Theme = .standard
    /// Alles, was im Ordner liegt - fuer die Liste in Nexus.
    private(set) var available: [Theme] = []

    let folder: URL

    /// Der Speicher der laufenden App. Ansichten holen ihren Stil hierueber
    /// (`shellTheme()` legt ihn an jeder Fensterwurzel in die Umgebung): Es gibt
    /// genau ein Theme fuer die ganze Shell, und Observation sorgt trotzdem
    /// dafuer, dass jede Ansicht neu zeichnet, die einen Wert gelesen hat.
    /// Ohne App (Bildproben, Tests) bleibt er leer, und alles sieht aus wie
    /// ohne Theme.
    private(set) static var shared: ThemeStore?

    @ObservationIgnored private let settings: ShellSettingsStore
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    /// Zweiter Beobachter auf die Datei des gewaehlten Themes: Der Ordner
    /// meldet nur, wenn etwas dazukommt oder verschwindet - eine Aenderung
    /// *in* einer Datei sieht man nur an ihr selbst.
    @ObservationIgnored private var fileWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var reloadWork: DispatchWorkItem?
    /// Inode des beobachteten Ordners, zum Erkennen eines Austauschs.
    @ObservationIgnored private var watchedInode: Int?

    /// Ein Editor schreibt beim Speichern mehrfach; erst danach lesen.
    private static let reloadDelay: DispatchTimeInterval = .milliseconds(250)

    private let log = Logger(category: "themes")

    init(settings: ShellSettingsStore, folder: URL? = nil) {
        self.settings = settings
        self.folder = folder ?? ShellFiles.live.themes
        reload()
        watch()
        ThemeStore.shared = self
    }

    deinit {
        watcher?.cancel()
        fileWatcher?.cancel()
    }

    /// Der Stil fuer die Oberfläche, im gewuenschten Erscheinungsbild.
    func style(dark: Bool) -> ShellStyle {
        ShellStyle(theme: theme, dark: dark)
    }

    /// Name des gewaehlten Themes (Datei- oder Ordnername), `nil` = keins.
    var selection: String? { settings.settings.theme.name }

    /// Waehlt ein Theme oder keines. Wirkt sofort.
    func select(_ name: String?) {
        settings.settings.theme.name = name
        reload()
    }

    /// Liest den Ordner und das gewaehlte Theme neu.
    func reload() {
        defer { applyAppearance() }
        available = ThemeLoader.themes(in: folder)
        guard let name = settings.settings.theme.name else {
            theme = .standard
            stopWatchingFile()
            return
        }
        // Nur aus dem Ordner: Der Name aus den Einstellungen ist nie ein Pfad
        // (ShellSettings prueft das), und gefunden wird er in der Liste, nicht
        // durch Zusammensetzen eines Pfades.
        guard let found = available.first(where: { $0.identifier == name }) else {
            log.notice("Theme \(name, privacy: .public) nicht im Ordner - ohne Theme")
            theme = .standard
            stopWatchingFile()
            return
        }
        theme = found
        watchSelectedFile()
        if !found.issues.isEmpty {
            log.notice("Theme \(name, privacy: .public): \(found.issues.count) Hinweis(e)")
        }
    }

    /// `--apollo-theme-appearance`: ein helles oder dunkles Theme stellt die
    /// ganze Shell darauf ein (`NSApp.appearance`), unabhaengig davon, was
    /// macOS gerade zeigt. Vorher las die Shell das Token nicht: rund 117
    /// Stellen nehmen die Systemschrift (.primary/.secondary), und auf einem
    /// dunklen Mac war die auf den hellen Flaechen von Latte, Dawn oder Paper
    /// weiss und unlesbar. Glas und Systemfarben folgen dem Erscheinungsbild
    /// von selbst. `auto` laesst es beim System.
    private func applyAppearance() {
        let wanted: NSAppearance? = switch ThemeAppearance(theme: theme) {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .auto: nil
        }
        guard NSApp.appearance?.name != wanted?.name else { return }
        NSApp.appearance = wanted
        log.notice("Erscheinungsbild aus dem Theme: \(wanted?.name.rawValue ?? "System", privacy: .public)")
    }

    /// Kopiert eine .css oder einen Theme-Ordner in den Theme-Ordner und
    /// waehlt sie aus. Gibt den Namen zurueck, unter dem sie jetzt liegt.
    @discardableResult
    func importTheme(from source: URL) throws -> String {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw ThemeImportError.notATheme
        }
        if isDirectory.boolValue {
            guard manager.fileExists(atPath: source.appendingPathComponent(ThemeLoader.styleSheetName).path) else {
                throw ThemeImportError.folderWithoutStyleSheet
            }
        } else if source.pathExtension.lowercased() != "css" {
            throw ThemeImportError.notATheme
        }

        // Nicht ueberschreiben: "Mitternacht 2", wenn es "Mitternacht" schon gibt.
        let base = isDirectory.boolValue ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        let suffix = isDirectory.boolValue ? "" : ".css"
        var name = base + suffix
        var counter = 2
        while manager.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(base) \(counter)\(suffix)"
            counter += 1
        }
        try manager.copyItem(at: source, to: folder.appendingPathComponent(name))
        reload()
        select(isDirectory.boolValue ? name : String(name.dropLast(suffix.count)))
        return name
    }

    /// Zeigt den Theme-Ordner im Finder; legt ihn an, falls es ihn noch nicht gibt.
    func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: - Beobachten

    /// Zeigt der Beobachter noch auf denselben Ordner? Verglichen wird die
    /// Inode-Nummer: Ein neu angelegter Ordner gleichen Namens ist ein
    /// anderer Ordner.
    private func rearmIfFolderChanged() {
        let current = (try? FileManager.default.attributesOfItem(atPath: folder.path)[.systemFileNumber] as? Int) ?? nil
        guard current != watchedInode else { return }
        watcher?.cancel()
        watcher = nil
        watch()
    }

    private func watch() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        watchedInode = (try? FileManager.default.attributesOfItem(atPath: folder.path)[.systemFileNumber] as? Int) ?? nil
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
        watcher = source
    }

    /// Beobachtet die Datei des gewaehlten Themes. Ein Editor, der in die
    /// Datei schreibt statt sie zu ersetzen, loest sonst kein Ereignis aus.
    private func watchSelectedFile() {
        stopWatchingFile()
        let manager = FileManager.default
        let single = folder.appendingPathComponent(theme.identifier + ".css")
        let inFolder = folder.appendingPathComponent(theme.identifier)
            .appendingPathComponent(ThemeLoader.styleSheetName)
        let path = manager.fileExists(atPath: single.path) ? single
            : (manager.fileExists(atPath: inFolder.path) ? inFolder : nil)
        guard let path else { return }
        let descriptor = open(path.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
        fileWatcher = source
    }

    private func stopWatchingFile() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.reload()
                // Wurde der Ordner geloescht, umbenannt oder ersetzt (ein
                // Abgleichdienst, ein Griff im Finder), zeigt der alte
                // Beobachter ins Leere. Dann neu anhaengen, sonst waere das
                // Live-Neuladen fuer den Rest der Sitzung still tot.
                self?.rearmIfFolderChanged()
            }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reloadDelay, execute: work)
    }
}

/// Warum ein Import nicht ging. Kurz und in Worten, die auf einer Seite stehen können.
enum ThemeImportError: LocalizedError {
    case notATheme
    case folderWithoutStyleSheet

    var errorDescription: String? {
        switch self {
        case .notATheme:
            String(localized: "That is not a theme: a .css file or a folder with a theme.css is expected.")
        case .folderWithoutStyleSheet:
            String(localized: "This folder has no theme.css.")
        }
    }
}
