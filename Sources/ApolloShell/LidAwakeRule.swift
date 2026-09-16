import AppKit
import ApolloShellCore

/// Die sudo-Regel fuer "Wach halten, auch zugeklappt"
/// (`LidAwake.sudoersRule`) auf diesem Mac: ist sie da, und wieder weg damit.
@MainActor
enum LidAwakeRule {
    /// Der Ordner ist fuer alle lesbar, die Datei selbst nur fuer root - um
    /// zu sehen, ob es sie gibt, reicht das.
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: LidAwake.sudoersFile)
    }

    /// Fuer wen die Regel beim Einschalten angelegt werden soll; `nil`, wenn
    /// sie schon da ist.
    static var userToInstall: String? {
        isInstalled ? nil : NSUserName()
    }

    /// macOS fragt nach einem Administrator. `done` bekommt, ob die Regel
    /// danach weg ist (abgelehnt: nein).
    static func remove(done: @escaping @MainActor (Bool) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: LidAwake.osascript)
        process.arguments = LidAwake.removeRuleArguments()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            Task { @MainActor in done(!isInstalled) }
        }
        do {
            try process.run()
        } catch {
            done(false)
        }
    }
}
