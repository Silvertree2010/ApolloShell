import ApolloShellCore
import AppKit
import Foundation
import os

/// The side effects around `AppleMenuBarHiding` (ApolloShellCore, pure):
/// writes `_HIHideMenuBar` into the global domain and posts the notification
/// that makes every app follow at once. The value from before lies in
/// ~/Library/Application Support/ApolloShell/apple-menubar.json while the
/// bar is hidden - the pattern of `AppleDockHidingController`:
///
/// - follows the setting: our menu bar on with "Hide Apple's Menu Bar" ->
///   hide right away, anything else -> restore right away;
/// - `terminate()` (applicationWillTerminate, SIGTERM) restores whatever the
///   setting says;
/// - after a crash or a SIGKILL the file is still there: the next start
///   restores from it, or keeps it hidden when the setting still asks for
///   that - the saved original stays the one from before the first hiding.
///
/// ⌃F2 (focus the menu bar) is not touched: Apple's bar slides in under ours
/// and its menus open above everything.
@MainActor
final class AppleMenuBarHidingController {
    private let fileURL: URL?
    private var settingsObservation: Task<Void, Never>?
    /// Called after a change, once the screens report their new visible
    /// frame: the bars measure again.
    var onChange: @MainActor () -> Void = {}
    private let log = Logger(category: "appleMenuBarHiding")

    init(settings: ShellSettingsStore, fileURL: URL? = ShellFiles.live.appleMenuBar) {
        self.fileURL = fileURL
        settingsObservation = Task { [weak self, settings] in
            for await hide in Observations({ AppleMenuBarHiding.shouldHide(settings.settings.apolloMenuBar) }) {
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
        if AppleMenuBarOriginal.load(from: ShellFiles.read(fileURL)) == nil {
            // Without a backup no hiding: the way back would be lost.
            do {
                try ShellFiles.write(AppleMenuBarOriginal(hidden: Self.current()).encoded(), to: fileURL)
            } catch {
                log.error("apple-menubar.json not saved, the menu bar stays: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        guard Self.current() != true else { return }
        write(true)
        log.notice("Apple menu bar hidden")
    }

    private func restore(fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        // Unreadable backup: back to macOS's default (key missing = shown)
        // rather than leaving the bar hidden.
        let original = AppleMenuBarOriginal.load(from: ShellFiles.read(fileURL)) ?? AppleMenuBarOriginal()
        if Self.current() != original.hidden { write(original.hidden) }
        try? FileManager.default.removeItem(at: fileURL)
        log.notice("Apple menu bar restored (\(original.hidden.map(String.init) ?? "default", privacy: .public))")
    }

    private static func current() -> Bool? {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[AppleMenuBarHiding.key] as? Bool
    }

    private func write(_ hidden: Bool?) {
        var domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        domain[AppleMenuBarHiding.key] = hidden
        UserDefaults.standard.setPersistentDomain(domain, forName: UserDefaults.globalDomain)
        DistributedNotificationCenter.default().postNotificationName(
            .init(AppleMenuBarHiding.notification), object: nil, userInfo: nil, deliverImmediately: true)
        // The screens report the new visible frame a moment later, and not
        // always with a notification (PoC, 22.09.).
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.onChange()
        }
    }
}
