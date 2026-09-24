import Foundation

public enum ProviderFileManager {
    public static let finder = AppleDockPrefs.finder

    public static let known: [String] = [
        AppleDockPrefs.forkLift,
        "com.cocoatech.PathFinder",
        "com.eltima.cmd1",
        "com.eltima.cmd1.pro.mas",
        "org.yanex.marta",
        "info.filesmanager.Files",
        "com.jinghaoshe.qspace",
        "com.jinghaoshe.qspace.pro",
    ]

    public static func automatic(isInstalled: (String) -> Bool) -> String {
        isInstalled(AppleDockPrefs.forkLift) ? AppleDockPrefs.forkLift : finder
    }

    public static func resolve(setting: String?, isInstalled: (String) -> Bool) -> String {
        if let setting, setting == finder || isInstalled(setting) { return setting }
        return automatic(isInstalled: isInstalled)
    }

    public static func hidden(for fileManager: String) -> Set<String> {
        fileManager == finder ? [] : [finder]
    }

    public enum Reveal: Equatable, Sendable {
        case selectInFileViewer
        case openFolder(bundleID: String)
    }

    public static func reveal(fileManager: String, systemFileViewer: String?) -> Reveal {
        let viewer = systemFileViewer?.trimmingCharacters(in: .whitespaces) ?? ""
        let system = viewer.isEmpty ? finder : viewer
        return system.caseInsensitiveCompare(fileManager) == .orderedSame
            ? .selectInFileViewer
            : .openFolder(bundleID: fileManager)
    }

    public static func choices(setting: String?, isInstalled: (String) -> Bool) -> [String] {
        var result = [finder] + known.filter(isInstalled)
        if let setting, !result.contains(setting) { result.append(setting) }
        return result
    }
}
