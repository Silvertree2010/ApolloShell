import ApolloShellCore
import AppKit
import Foundation
import os

@MainActor
final class AppleMenuBarHidingController {
    private let fileURL: URL?
    private let log = Logger(category: "appleMenuBarHiding")
    var read: () -> Bool? = { AppleMenuBarHidingController.current() }
    var write: (Bool?) -> Void = { AppleMenuBarHidingController.store($0) }

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    var isHidden: Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    func recoverAfterCrash() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        log.notice("apple-menubar.json left from an earlier run, restoring Apple's menu bar")
        restore(fileURL: fileURL)
    }

    func terminate() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        restore(fileURL: fileURL)
    }

    func apply(_ hide: Bool) {
        guard let fileURL else { return }
        if hide { self.hide(fileURL: fileURL) } else { restore(fileURL: fileURL) }
    }

    private func hide(fileURL: URL) {
        if AppleMenuBarOriginal.load(from: try? Data(contentsOf: fileURL)) == nil {
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try AppleMenuBarOriginal(hidden: read()).encoded().write(to: fileURL, options: .atomic)
            } catch {
                log.error("apple-menubar.json not saved, the menu bar stays: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        guard read() != true else { return }
        write(true)
        log.notice("Apple menu bar hidden")
    }

    private func restore(fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let original = AppleMenuBarOriginal.load(from: try? Data(contentsOf: fileURL)) ?? AppleMenuBarOriginal()
        if read() != original.hidden { write(original.hidden) }
        try? FileManager.default.removeItem(at: fileURL)
        log.notice("Apple menu bar restored (\(original.hidden.map(String.init) ?? "default", privacy: .public))")
    }

    nonisolated static func current() -> Bool? {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[AppleMenuBarHiding.key] as? Bool
    }

    nonisolated static func store(_ hidden: Bool?) {
        var domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        domain[AppleMenuBarHiding.key] = hidden
        UserDefaults.standard.setPersistentDomain(domain, forName: UserDefaults.globalDomain)
        DistributedNotificationCenter.default().postNotificationName(
            .init(AppleMenuBarHiding.notification), object: nil, userInfo: nil, deliverImmediately: true)
    }
}
