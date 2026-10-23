import AppKit
import ApolloShellCore
import ServiceManagement

@MainActor
enum Uninstaller {
    static var kind: InstallKind { InstallKind.detect(resourcesURL: Bundle.main.resourceURL) }

    static func run() {
        (NSApp.delegate as? AppDelegate)?.prepareUninstall()
        guard LidAwakeRule.isInstalled else { return reset() }
        LidAwakeRule.remove { _ in reset() }
    }

    private static func reset() {
        if Subprocess.launch(Uninstall.tccutil, Uninstall.tccArguments(), onExit: { _ in finish() }) == nil { finish() }
    }

    private static func finish() {
        try? SMAppService.mainApp.unregister()
        UserDefaults.standard.removePersistentDomain(forName: AppIdentity.bundleID)
        let fm = FileManager.default
        for u in Uninstall.paths(home: fm.homeDirectoryForCurrentUser) { try? fm.removeItem(at: u) }
        if kind == .disk, Bundle.main.bundleURL.pathExtension == "app" {
            try? fm.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        }
        exit(0)
    }
}
