import Foundation

/// Woher diese Installation stammt. Davon haengt ab, wie ein Update
/// eingespielt wird.
///
/// - `.disk`: aus dem DMG (oder ein eigener Build). Die App darf sich selbst
///   erneuern, Sparkle uebernimmt das.
/// - `.homebrew`: von `brew install`. Die App liegt im Cellar und gehoert
///   Homebrew. Wuerde sie sich dort selbst ersetzen, stimmte der Bestand von
///   Homebrew nicht mehr, und das naechste `brew upgrade` machte es wieder
///   rueckgaengig. Die App meldet neue Fassungen deshalb nur und nennt den
///   Befehl.
///
/// Erkannt wird das nicht am Pfad - der kann ueberall liegen, und Symlinks
/// machen Pfadraten unzuverlaessig (siehe `~/Applications/ApolloShell.app`
/// als Link in den Cellar) -, sondern an einer Markierungsdatei, die die
/// Formel beim Bauen ins Bundle legt.
public enum InstallKind: String, Equatable, Hashable, Sendable, CaseIterable {
    case disk
    case homebrew

    /// Name der Markierungsdatei in `Contents/Resources`. Ihr Inhalt spielt
    /// keine Rolle; dass sie da ist, genuegt.
    public static let markerName = "installed-by-homebrew"

    /// Der Befehl, der eine Homebrew-Installation aktualisiert.
    public static let homebrewUpgradeCommand = "brew upgrade apolloshell"

    /// Entscheidet anhand des Bundles. `resourcesURL` ist
    /// `Bundle.main.resourceURL`; ohne Bundle (z. B. `swift run`) gilt `.disk`.
    public static func detect(resourcesURL: URL?,
                              fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> InstallKind {
        guard let resourcesURL else { return .disk }
        return fileExists(resourcesURL.appendingPathComponent(markerName)) ? .homebrew : .disk
    }

    /// Darf sich diese Installation selbst erneuern?
    public var updatesItself: Bool { self == .disk }
}
