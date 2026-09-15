/// Kennung der App an einer Stelle. Gleich der Bundle-ID in
/// Support/Info.plist (build.sh und scripts/assemble-app.sh signieren damit;
/// ein Test prueft, dass beide uebereinstimmen). Daraus abgeleitet: das
/// Log-Subsystem, Queue-Labels und eigene Pasteboard-Typen. Die
/// Log-Kategorien stehen weiter bei den Aufrufern.
public enum AppIdentity {
    public static let bundleID = "io.github.silvertree2010.apolloshell"

    /// Fuer `Logger(subsystem:category:)`, also auch fuer
    /// `log stream --predicate 'subsystem == "…"'`.
    public static let logSubsystem = bundleID

    /// Eine Kennung unterhalb der Bundle-ID, z. B. fuer Queue-Labels:
    /// `scoped("bluetooth")` = "<bundleID>.bluetooth".
    public static func scoped(_ name: String) -> String {
        bundleID + "." + name
    }
}
