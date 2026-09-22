import ApolloShellCore
import ApolloWM
import AppKit
import Observation
import os

/// twm.conf: the TWM's keys and window rules, like Hyprland's config file.
/// Written from a commented template the first time, read again whenever it
/// is saved. Nexus > TWM shows the lines it could not read.
@MainActor
@Observable
final class TWMConfigFile {
    static let shared = TWMConfigFile(url: ShellFiles.live.twmConfig)

    private(set) var config = TWMConfig()
    /// Called with every (re)load while someone listens (the TWM runs).
    @ObservationIgnored var onChange: ((TWMConfig) -> Void)?

    @ObservationIgnored let url: URL
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var reloadWork: DispatchWorkItem?
    @ObservationIgnored private let log = Logger(category: "twm")

    init(url: URL) {
        self.url = url
    }

    /// Creates the file if needed, reads it and watches it.
    func start() {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(TWMConfig.template.utf8).write(to: url, options: .atomic)
        }
        reload()
        watch()
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        reloadWork?.cancel()
    }

    /// Opens the file in the user's text editor.
    func open() {
        if !FileManager.default.fileExists(atPath: url.path) { start() }
        NSWorkspace.shared.open(url)
    }

    private func reload() {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let fresh = TWMConfig.parse(text)
        for problem in fresh.problems { log.notice("twm.conf \(problem, privacy: .public)") }
        if fresh != config { config = fresh }
        onChange?(fresh)
    }

    /// Editors save by replacing the file, which ends a watch on the old
    /// one; after a delete or rename the watch starts over on the new file.
    private func watch() {
        watcher?.cancel()
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            let replaced = source.map { !$0.data.isDisjoint(with: [.rename, .delete]) } ?? false
            MainActor.assumeIsolated { self?.scheduleReload(rewatch: replaced) }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func scheduleReload(rewatch: Bool) {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if rewatch { self.watch() }
                self.reload()
            }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
