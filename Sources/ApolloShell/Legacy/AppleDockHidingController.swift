import ApolloShellCore
import Foundation
import Observation
import os

@MainActor
final class AppleDockHidingController {
    static let killall = "/usr/bin/killall"
    private static let domain = "com.apple.dock" as CFString

    private let fileURL: URL?
    private var settingsObservation: Task<Void, Never>?
    private let log = Logger(category: "appleDockHiding")

    init(settings: ShellSettingsStore, fileURL: URL? = ShellFiles.live.appleDock) {
        self.fileURL = fileURL
        settingsObservation = Task { [weak self, settings] in
            for await hide in Observations({ settings.settings.appleDockHiding.hideWhileRunning }) {
                self?.apply(hide)
            }
        }
    }

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

    private func hide(fileURL: URL) {
        if AppleDockPreferenceValues.load(from: try? Data(contentsOf: fileURL)) == nil {
            let original = AppleDockHiding.originalToSave(current: readCurrent())
            guard write(original.encoded(), to: fileURL) else { return }
        }
        writeAndApply(AppleDockHiding.hidden)
        log.notice("Apple-Dock ausgeblendet")
    }

    private func restore(fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
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
