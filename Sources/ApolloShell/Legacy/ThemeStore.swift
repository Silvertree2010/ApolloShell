import AppKit
import ApolloShellCore
import SwiftUI
import os

@MainActor
@Observable
final class ThemeStore {
    private(set) var theme: Theme = .standard
    private(set) var available: [Theme] = []

    let folder: URL

    private(set) static var shared: ThemeStore?

    @ObservationIgnored private let settings: ShellSettingsStore
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var fileWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var reloadWork: DispatchWorkItem?
    @ObservationIgnored private var watchedInode: Int?

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

    func style(dark: Bool) -> ShellStyle {
        ShellStyle(theme: theme, dark: dark)
    }

    var selection: String? { settings.settings.theme.name }

    func select(_ name: String?) {
        settings.settings.theme.name = name
        reload()
    }

    func reload() {
        defer { applyAppearance() }
        available = ThemeLoader.themes(in: folder)
        guard let name = settings.settings.theme.name else {
            theme = .standard
            stopWatchingFile()
            return
        }
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

    func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

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
                self?.rearmIfFolderChanged()
            }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reloadDelay, execute: work)
    }
}

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
