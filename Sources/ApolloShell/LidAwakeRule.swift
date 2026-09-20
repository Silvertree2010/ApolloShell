import AppKit
import ApolloShellCore

/// The sudo rule for "Keep Awake" with the lid closed too
/// (`LidAwake.sudoersRule`) on this Mac: is it there, and getting rid of it.
@MainActor
enum LidAwakeRule {
    /// The directory is readable by everyone, the file itself only by root -
    /// that's enough to see whether it exists.
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: LidAwake.sudoersFile)
    }

    /// Who to install the rule for when turning it on; `nil` if it's
    /// already there.
    static var userToInstall: String? {
        isInstalled ? nil : NSUserName()
    }

    /// macOS asks for an administrator. `done` gets whether the rule is
    /// gone afterward (refused: no).
    static func remove(done: @escaping @MainActor (Bool) -> Void) {
        let started = Subprocess.launch(LidAwake.osascript, LidAwake.removeRuleArguments()) { _ in
            done(!isInstalled)
        }
        if started == nil { done(false) }
    }
}
