import Foundation

/// Welcher Dateimanager oben im Dock der Leiste steht (Finders Platz), und
/// wie "In … zeigen" dort eine Datei zeigt. Die App fragt nur, ob etwas
/// installiert ist; entschieden wird hier, getestet.
///
/// Der systemweite Standard (`NSFileViewer`, den "Im Finder zeigen" in
/// anderen Apps nimmt) wird nur gelesen, nie geaendert: die Auswahl gilt fuer
/// die Leiste, nicht fuer das System.
public enum ProviderFileManager {
    public static let finder = AppleDockPrefs.finder

    /// Bekannte Dateimanager, in dieser Reihenfolge in Nexus vorgeschlagen,
    /// sofern installiert. Bundle-IDs nachgeschlagen 14.09.2026 (ForkLift an
    /// einer Installation gemessen); was fehlt, geht ueber "Andere App …".
    public static let known: [String] = [
        AppleDockPrefs.forkLift,
        "com.cocoatech.PathFinder",
        "com.eltima.cmd1",              // Commander One
        "com.eltima.cmd1.pro.mas",      // Commander One Pro (App Store)
        "org.yanex.marta",              // Marta
        "info.filesmanager.Files",      // Nimble Commander
        "com.jinghaoshe.qspace",        // QSpace
        "com.jinghaoshe.qspace.pro",    // QSpace Pro
    ]

    /// Ohne Einstellung: ForkLift, wenn installiert, sonst Finder - das
    /// Verhalten, bevor es die Auswahl gab.
    public static func automatic(isInstalled: (String) -> Bool) -> String {
        isInstalled(AppleDockPrefs.forkLift) ? AppleDockPrefs.forkLift : finder
    }

    /// Die gewaehlte App, solange es sie gibt. Deinstalliert: automatisch,
    /// statt dass oben ein leerer Platz bliebe. Die Einstellung selbst bleibt
    /// stehen - kommt die App zurueck, gilt sie wieder.
    public static func resolve(setting: String?, isInstalled: (String) -> Bool) -> String {
        if let setting, setting == finder || isInstalled(setting) { return setting }
        return automatic(isInstalled: isInstalled)
    }

    /// In der Leiste nie zeigen: Finder, wenn ein anderer ihn ersetzt (er
    /// laeuft immer und kaeme sonst unter "laufend" wieder). Steht Finder
    /// selbst oben, bleibt alles sichtbar.
    public static func hidden(for fileManager: String) -> Set<String> {
        fileManager == finder ? [] : [finder]
    }

    public enum Reveal: Equatable, Sendable {
        /// `activateFileViewerSelecting`: zeigt die Datei markiert - im
        /// Dateiviewer des Systems.
        case selectInFileViewer
        /// Den enthaltenden Ordner mit dieser App oeffnen (ohne Markierung;
        /// mehr bietet NSWorkspace fuer fremde Apps nicht).
        case openFolder(bundleID: String)
    }

    /// Markieren geht nur ueber den Dateiviewer des Systems. Ist das der
    /// gewaehlte Dateimanager (ohne Einstellung: Finder), also so; sonst
    /// oeffnete `activateFileViewerSelecting` eine andere App, als das Menue
    /// verspricht ("In Finder zeigen" oeffnete ForkLift) - dann den Ordner
    /// ausdruecklich mit der gewaehlten App.
    public static func reveal(fileManager: String, systemFileViewer: String?) -> Reveal {
        let viewer = systemFileViewer?.trimmingCharacters(in: .whitespaces) ?? ""
        let system = viewer.isEmpty ? finder : viewer
        return system.caseInsensitiveCompare(fileManager) == .orderedSame
            ? .selectInFileViewer
            : .openFolder(bundleID: fileManager)
    }

    /// Auswahl in Nexus: Finder, dann die installierten bekannten, dann eine
    /// von Hand gewaehlte andere App (auch wenn sie inzwischen fehlt - sonst
    /// saehe man nicht, was eingestellt ist).
    public static func choices(setting: String?, isInstalled: (String) -> Bool) -> [String] {
        var result = [finder] + known.filter(isInstalled)
        if let setting, !result.contains(setting) { result.append(setting) }
        return result
    }
}
