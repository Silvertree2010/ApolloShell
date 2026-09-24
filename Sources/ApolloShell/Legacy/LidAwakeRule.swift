import AppKit
import ApolloShellCore

@MainActor
enum LidAwakeRule {
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: LidAwake.sudoersFile)
    }

    static var userToInstall: String? {
        isInstalled ? nil : NSUserName()
    }

    static func remove(done: @escaping @MainActor (Bool) -> Void) {
        let started = Subprocess.launch(LidAwake.osascript, LidAwake.removeRuleArguments()) { _ in
            done(!isInstalled)
        }
        if started == nil { done(false) }
    }
}
