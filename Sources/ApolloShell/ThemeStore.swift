import AppKit
import ApolloShellCore
import SwiftUI
import os

/// Holds the chosen theme and the content of the theme folder.
///
/// Reading, checking and clamping is the core's job (`ThemeLoader`, `Theme`);
/// only which theme applies, what lies in the folder and when it is read
/// again stands here.
///
/// Live: the folder is watched. Whoever saves a .css sees the change right
/// away - that is how one works on a theme without restarting the shell. The
/// events are gathered briefly (`reloadDelay`), because an editor sets off
/// several of them when saving.
@MainActor
@Observable
final class ThemeStore {
    /// The chosen theme, fully checked. Without a choice: the defaults.
    private(set) var theme: Theme = .standard
    /// Everything that lies in the folder - for the list in Nexus.
    private(set) var available: [Theme] = []

    let folder: URL

    /// The store of the running app. Views get their style through it
    /// (`shellTheme()` puts it into the environment at every window root):
    /// there is exactly one theme for the whole shell, and Observation still
    /// sees to it that every view which read a value redraws.
    /// Without an app (image samples, tests) it stays empty, and everything
    /// looks the way it does without a theme.
    private(set) static var shared: ThemeStore?

    @ObservationIgnored private let settings: ShellSettingsStore
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    /// A second watcher on the file of the chosen theme: the folder only
    /// reports when something is added or disappears - a change *inside* a
    /// file only shows on the file itself.
    @ObservationIgnored private var fileWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var reloadWork: DispatchWorkItem?
    /// Inode of the watched folder, to notice a swap.
    @ObservationIgnored private var watchedInode: Int?

    /// An editor writes several times when saving; only read afterwards.
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

    /// The style for the user interface, in the wanted appearance.
    func style(dark: Bool) -> ShellStyle {
        ShellStyle(theme: theme, dark: dark)
    }

    /// Name of the chosen theme (file or folder name), `nil` = none.
    var selection: String? { settings.settings.theme.name }

    /// Chooses a theme or none. Takes hold right away.
    func select(_ name: String?) {
        settings.settings.theme.name = name
        reload()
    }

    /// Reads the folder and the chosen theme again.
    func reload() {
        defer { applyAppearance() }
        available = ThemeLoader.themes(in: folder)
        guard let name = settings.settings.theme.name else {
            theme = .standard
            stopWatchingFile()
            return
        }
        // Only out of the folder: the name in the settings is never a path
        // (ShellSettings checks that), and it is found in the list, not by
        // putting a path together.
        guard let found = available.first(where: { $0.identifier == name }) else {
            log.notice("Theme \(name, privacy: .public) is not in the folder - without a theme")
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

    /// `--apollo-theme-appearance`: a light or dark theme sets the whole shell
    /// to it (`NSApp.appearance`), no matter what macOS shows right now.
    /// Before, the shell did not read the token: around 117 places take the
    /// system text color (.primary/.secondary), and on a dark Mac that was
    /// white and unreadable on the light areas of Latte, Dawn or Paper. Glass
    /// and system colors follow the appearance by themselves. `auto` leaves it
    /// to the system.
    private func applyAppearance() {
        let wanted: NSAppearance? = switch ThemeAppearance(theme: theme) {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .auto: nil
        }
        guard NSApp.appearance?.name != wanted?.name else { return }
        NSApp.appearance = wanted
        log.notice("Appearance out of the theme: \(wanted?.name.rawValue ?? "System", privacy: .public)")
    }

    /// Copies a .css or a theme folder into the theme folder and picks it.
    /// Hands back the name it lies under now.
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

        // Do not overwrite: "Midnight 2" when "Midnight" exists already.
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

    /// Shows the theme folder in the Finder; creates it when it is not there yet.
    func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: - Watching

    /// Does the watcher still point at the same folder? What is compared is
    /// the inode number: a freshly created folder of the same name is a
    /// different folder.
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

    /// Watches the file of the chosen theme. An editor that writes into the
    /// file instead of replacing it would otherwise set off no event.
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
                // If the folder was deleted, renamed or replaced (a syncing
                // service, a grab in the Finder), the old watcher points into
                // the void. Then hook it up again, otherwise live reloading
                // would be quietly dead for the rest of the session.
                self?.rearmIfFolderChanged()
            }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reloadDelay, execute: work)
    }
}

/// Why an import did not work. Short, and in words that fit on one page.
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
