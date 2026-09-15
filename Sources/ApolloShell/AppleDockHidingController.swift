import ApolloShellCore
import Foundation
import Observation
import os

/// Seiteneffekte um `AppleDockHiding` (ApolloShellCore, rein) herum: liest
/// und schreibt `com.apple.dock` ueber cfprefsd wie `SidebarDock.writeTiles`,
/// danach `killall Dock` - aber nur, wenn sich dabei wirklich etwas aendert.
/// Das gesicherte Original liegt in
/// ~/Library/Application Support/ApolloShell/apple-dock.json.
///
/// Folgt der Einstellung (Nexus > Allgemein): eingeschaltet -> sofort
/// verstecken, ausgeschaltet -> sofort wiederherstellen. `terminate()` fuer
/// applicationWillTerminate und SIGTERM stellt beim Beenden ebenfalls wieder
/// her, egal wie die Einstellung gerade steht - ApolloShell soll das Dock
/// nie versteckt zuruecklassen.
@MainActor
final class AppleDockHidingController {
    static let killall = "/usr/bin/killall"
    private static let domain = "com.apple.dock" as CFString

    private let fileURL: URL?
    private var settingsObservation: Task<Void, Never>?
    private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "appleDockHiding")

    init(settings: ShellSettingsStore, fileURL: URL? = AppleDockHidingController.defaultFileURL) {
        self.fileURL = fileURL
        // Liefert zuerst den aktuellen Wert (das erledigt den Start mit
        // aktiver Einstellung, siehe `hide()`), danach jede Aenderung -
        // wie `SidebarDockModel`s Beobachtung von Nexus.
        settingsObservation = Task { [weak self, settings] in
            for await hide in Observations({ settings.settings.appleDockHiding.hideWhileRunning }) {
                self?.apply(hide)
            }
        }
    }

    static var defaultFileURL: URL {
        UsageStore.defaultURL.deletingLastPathComponent().appendingPathComponent("apple-dock.json")
    }

    /// Beim Beenden (applicationWillTerminate, SIGTERM): unabhaengig von der
    /// Einstellung wiederherstellen, falls gerade versteckt (Datei da).
    /// Kein Abbruch stellt fest, ob ApolloShell wirklich sauber beendet -
    /// nur ein SIGKILL laesst das Dock bis zum naechsten normalen Start und
    /// Ende versteckt.
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

    /// Existiert schon eine gesicherte apple-dock.json, bleibt sie -
    /// entweder von einem frueheren Absturz waehrend versteckt, oder weil
    /// ein zweiter "Start" (z. B. erneutes Einschalten der Einstellung)
    /// nichts am gesicherten Original aendert. Sonst Ist-Zustand lesen,
    /// Original sichern. Danach in jedem Fall die versteckten Werte
    /// schreiben.
    private func hide(fileURL: URL) {
        if AppleDockPreferenceValues.load(from: try? Data(contentsOf: fileURL)) == nil {
            let original = AppleDockHiding.originalToSave(current: readCurrent())
            write(original.encoded(), to: fileURL)
        }
        writeAndApply(AppleDockHiding.hidden)
        log.notice("Apple-Dock ausgeblendet")
    }

    /// Das gesicherte Original zurueckschreiben (fehlende Schluessel
    /// loeschen), Datei entfernen. Keine Datei: nichts zu tun (schon
    /// wiederhergestellt oder nie versteckt).
    private func restore(fileURL: URL) {
        guard let original = AppleDockPreferenceValues.load(from: try? Data(contentsOf: fileURL)) else { return }
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

    /// Schreibt `target` nur, wenn sich gegenueber dem Ist-Zustand wirklich
    /// etwas aendert - erst dann `killall Dock` (Apples Dock liest seine
    /// Einstellung nur beim eigenen Start neu).
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
        Self.launch(Self.killall, ["Dock"])
    }

    private func write(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("apple-dock.json nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func launch(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
