import AppKit
import ApolloShellCore
import ServiceManagement
import ApolloBase
import ApolloRuntime

final class TerminationWatch: @unchecked Sendable {
    private var sources: [DispatchSourceSignal] = []
    private var observer: NSObjectProtocol?
    private weak var center: NotificationCenter?

    init(signals: [Int32] = [SIGTERM, SIGINT], queue: DispatchQueue = DispatchQueue(label: "apolloshell.termination"), center: NotificationCenter = .default, fallback: TimeInterval = 2, hop: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }, exitProcess: @escaping @Sendable (Int32) -> Void = { exit($0) }, onTerminate: @escaping @Sendable (Int32?) -> Void) {
        for number in signals {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                queue.asyncAfter(deadline: .now() + fallback) { exitProcess(0) }
                hop {
                    onTerminate(number)
                    exitProcess(0)
                }
            }
            source.resume()
            sources.append(source)
        }
        self.center = center
        observer = center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in onTerminate(nil) }
    }

    func cancel() {
        for source in sources { source.cancel() }
        sources.removeAll()
        if let observer { center?.removeObserver(observer) }
        observer = nil
    }

    deinit { cancel() }
}

final class KeyNameSource: @unchecked Sendable {
    private let lock = NSLock()
    private var current: @Sendable (UInt32) -> String? = KeyboardLayoutNames.keyName

    var keyName: @Sendable (UInt32) -> String? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func name(_ keyCode: UInt32) -> String? { keyName(keyCode) }
}

@MainActor
final class OSDShowAction: ActionImplementation {
    weak var shell: LiveShell?

    init(shell: LiveShell) {
        self.shell = shell
    }

    func perform(_ call: ResolvedActionCall, environment: ActionEnvironment, runtime: any ActionRuntime) async throws {
        guard case .string(let id)? = call.arguments.first, !id.isEmpty else { throw ActionFailure("osd.show needs an osd id") }
        shell?.showOSD(id)
    }
}

@MainActor
final class LoginItem {
    var status: @MainActor () -> OnboardingAutostart.Status
    var change: @MainActor (Bool) throws -> Void
    let launchdLabel: String?
    let isAppBundle: Bool
    private(set) var error: String?

    init(status: @escaping @MainActor () -> OnboardingAutostart.Status, change: @escaping @MainActor (Bool) throws -> Void, launchdLabel: String?, isAppBundle: Bool) {
        self.status = status
        self.change = change
        self.launchdLabel = launchdLabel
        self.isAppBundle = isAppBundle
    }

    static func live() -> LoginItem {
        LoginItem(status: {
            switch SMAppService.mainApp.status {
            case .enabled: .enabled
            case .requiresApproval: .requiresApproval
            case .notRegistered: .notRegistered
            default: .notFound
            }
        }, change: { on in
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        }, launchdLabel: OnboardingAutostart.launchdLabel(environment: ProcessInfo.processInfo.environment),
           isAppBundle: Bundle.main.bundleURL.pathExtension == "app")
    }

    var state: OnboardingAutostart.State {
        OnboardingAutostart.state(status: status(), launchdLabel: launchdLabel, isAppBundle: isAppBundle)
    }

    func setEnabled(_ on: Bool) {
        let current = state
        guard current.canToggle, on != current.isOn else { return }
        do {
            try change(on)
            error = nil
        } catch {
            self.error = "macOS declined: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class ClosureAction: ActionImplementation {
    let body: @MainActor (ResolvedActionCall) throws -> Void

    init(_ body: @escaping @MainActor (ResolvedActionCall) throws -> Void) {
        self.body = body
    }

    func perform(_ call: ResolvedActionCall, environment: ActionEnvironment, runtime: any ActionRuntime) async throws {
        try body(call)
    }
}

@MainActor
final class LoginItemAction: ActionImplementation {
    weak var shell: LiveShell?

    init(shell: LiveShell) {
        self.shell = shell
    }

    func perform(_ call: ResolvedActionCall, environment: ActionEnvironment, runtime: any ActionRuntime) async throws {
        guard case .bool(let on)? = call.arguments.first else { throw ActionFailure("shell.set-login-item needs #true or #false") }
        shell?.setLoginItem(on)
    }
}

extension FolderWatcher {
    static func existingAncestor(_ path: String) -> String {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        while !FileManager.default.fileExists(atPath: url.path), url.path != "/" {
            url = url.deletingLastPathComponent()
        }
        return url.path
    }
}
