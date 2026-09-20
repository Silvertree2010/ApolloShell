import Foundation

/// Which file manager stands at the top of the Dock of the bar (the Finder's
/// place), and how "Show in …" shows a file there. The app only asks whether
/// something is installed; the decision is made here, and tested.
///
/// The system-wide default (`NSFileViewer`, which "Show in Finder" in other
/// apps takes) is only read, never changed: the choice holds for the bar, not
/// for the system.
public enum ProviderFileManager {
    public static let finder = AppleDockPrefs.finder

    /// The known file managers, suggested in Nexus in this order when they are
    /// installed. The bundle IDs looked up 14.09.2026 (ForkLift measured on an
    /// installation); what is missing goes through "Other App …".
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

    /// Without a setting: ForkLift when it is installed, otherwise the Finder -
    /// the behavior before the choice existed.
    public static func automatic(isInstalled: (String) -> Bool) -> String {
        isInstalled(AppleDockPrefs.forkLift) ? AppleDockPrefs.forkLift : finder
    }

    /// The chosen app as long as it exists. Uninstalled: automatic, instead of
    /// an empty place staying at the top. The setting itself stays - when the
    /// app comes back, it holds again.
    public static func resolve(setting: String?, isInstalled: (String) -> Bool) -> String {
        if let setting, setting == finder || isInstalled(setting) { return setting }
        return automatic(isInstalled: isInstalled)
    }

    /// Never show it in the bar: the Finder, when another one replaces it (it
    /// always runs and would otherwise come back under "running"). When the
    /// Finder stands at the top itself, everything stays visible.
    public static func hidden(for fileManager: String) -> Set<String> {
        fileManager == finder ? [] : [finder]
    }

    public enum Reveal: Equatable, Sendable {
        /// `activateFileViewerSelecting`: shows the file selected - in the file
        /// viewer of the system.
        case selectInFileViewer
        /// Open the enclosing folder with this app (without a selection;
        /// NSWorkspace offers no more for other apps).
        case openFolder(bundleID: String)
    }

    /// Selecting only works through the file viewer of the system. When that is
    /// the chosen file manager (without a setting: the Finder), then that way;
    /// otherwise `activateFileViewerSelecting` would open a different app than
    /// the menu promises ("Show in Finder" opened ForkLift) - then open the
    /// folder with the chosen app on purpose.
    public static func reveal(fileManager: String, systemFileViewer: String?) -> Reveal {
        let viewer = systemFileViewer?.trimmingCharacters(in: .whitespaces) ?? ""
        let system = viewer.isEmpty ? finder : viewer
        return system.caseInsensitiveCompare(fileManager) == .orderedSame
            ? .selectInFileViewer
            : .openFolder(bundleID: fileManager)
    }

    /// The choice in Nexus: the Finder, then the known installed ones, then an
    /// other app chosen by hand (even when it is missing by now - otherwise one
    /// would not see what is set).
    public static func choices(setting: String?, isInstalled: (String) -> Bool) -> [String] {
        var result = [finder] + known.filter(isInstalled)
        if let setting, !result.contains(setting) { result.append(setting) }
        return result
    }
}
