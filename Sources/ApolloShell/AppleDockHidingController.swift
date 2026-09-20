import ApolloShellCore
import Foundation
import Observation
import os

/// The side effects around `AppleDockHiding` (ApolloShellCore, pure): reads
/// and writes `com.apple.dock` through cfprefsd like `SidebarDock.writeTiles`,
/// then `killall Dock` - but only when something really changes. The saved
/// original lies in
/// ~/Library/Application Support/ApolloShell/apple-dock.json.
///
/// Follows the setting (Nexus > General): switched on -> hide right away,
/// switched off -> restore right away. `terminate()` for
/// applicationWillTerminate and SIGTERM restores on quit too, whatever the
/// setting says - ApolloShell should never leave the Dock hidden.
/// nie versteckt zuruecklassen.
@MainActor
final class AppleDockHidingController {
    static let killall = "/usr/bin/killall"
    private static let domain = "com.apple.dock" as CFString

    private let fileURL: URL?
    private var settingsObservation: Task<Void, Never>?
    private let log = Logger(category: "appleDockHiding")

    init(settings: ShellSettingsStore, fileURL: URL? = ShellFiles.live.appleDock) {
        self.fileURL = fileURL
        // Delivers the current value first (which takes care of the start with
        // the setting on, see `hide()`), then every change - like
        // `SidebarDockModel`'s observation of Nexus.
        settingsObservation = Task { [weak self, settings] in
            for await hide in Observations({ settings.settings.appleDockHiding.hideWhileRunning }) {
                self?.apply(hide)
            }
        }
    }

    /// On quit (applicationWillTerminate, SIGTERM): restore whatever the
    /// setting says, when it is hidden right now (the file is there). No
    /// interruption decides whether ApolloShell really quits cleanly - only a
    /// SIGKILL leaves the Dock hidden until the next normal start and quit.
    ///
    func terminate() {
        settingsObservation?.cancel()
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        restore(fileURL: fileURL)
    }

    private func apply(_ hide: Bool) {
        guard let fileURL else { return }
        if hide {
            self.hide(fileURL: fileURL)
        } else {
            restore(fileURL: fileURL)
        }
    }

    /// When a saved apple-dock.json exists already, it stays - either from an
    /// earlier crash while hidden, or because a second "start" (switching the
    /// setting on again, say) changes nothing about the saved original.
    /// Otherwise read the current state and save the original. After that,
    /// write the hidden values in any case.
    ///
    private func hide(fileURL: URL) {
        if AppleDockPreferenceValues.load(from: try? Data(contentsOf: fileURL)) == nil {
            let original = AppleDockHiding.originalToSave(current: readCurrent())
            // Without a backup no hiding: otherwise the restore would find
            // nothing and the Dock would stay away forever.
            guard write(original.encoded(), to: fileURL) else { return }
        }
        writeAndApply(AppleDockHiding.hidden)
        log.notice("Apple-Dock ausgeblendet")
    }

    /// Write the saved original back (deleting missing keys), remove the file.
    /// No file: nothing to do (restored already or never hidden).
    ///
    private func restore(fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        // A backup that is there but unreadable: back to the defaults of macOS,
        // instead of leaving the Dock hidden.
        let original = AppleDockPreferenceValues.load(from: try? Data(contentsOf: fileURL))
            ?? AppleDockPreferenceValues(autohide: nil, autohideDelay: nil, autohideTimeModifier: nil)
        writeAndApply(original)
        try? FileManager.default.removeItem(at: fileURL)
        log.notice("Apple-Dock wieder eingeblendet")
    }

    private func readCurrent() -> AppleDockPreferenceValues {
        CFPreferencesAppSynchronize(Self.domain)
        let autohide = CFPreferencesCopyAppValue(AppleDockHiding.autohideKey as CFString, Self.domain) as? NSNumber
        let delay = CFPreferencesCopyAppValue(AppleDockHiding.autohideDelayKey as CFString, Self.domain) as? NSNumber
        let modifier = CFPreferencesCopyAppValue(
            AppleDockHiding.autohideTimeModifierKey as CFString, Self.domain
        ) as? NSNumber
        return AppleDockPreferenceValues(
            autohide: autohide?.boolValue, autohideDelay: delay?.doubleValue,
            autohideTimeModifier: modifier?.doubleValue
        )
    }

    /// Writes `target` only when something really changes against the current
    /// state - and only then `killall Dock` (Apple's Dock reads its settings
    /// anew only on its own start).
    private func writeAndApply(_ target: AppleDockPreferenceValues) {
        guard readCurrent() != target else { return }
        for action in AppleDockHiding.actions(toReach: target) {
            switch action {
            case .setBool(let key, let value):
                CFPreferencesSetAppValue(key as CFString, NSNumber(value: value), Self.domain)
            case .setDouble(let key, let value):
                CFPreferencesSetAppValue(key as CFString, NSNumber(value: value), Self.domain)
            case .remove(let key):
                CFPreferencesSetAppValue(key as CFString, nil, Self.domain)
            }
        }
        CFPreferencesAppSynchronize(Self.domain)
        Subprocess.launch(Self.killall, ["Dock"])
    }

    @discardableResult
    private func write(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            log.error("apple-dock.json nicht gespeichert, Dock bleibt sichtbar: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
