import AppKit
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

extension FolderWatcher {
    static func existingAncestor(_ path: String) -> String {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        while !FileManager.default.fileExists(atPath: url.path), url.path != "/" {
            url = url.deletingLastPathComponent()
        }
        return url.path
    }
}
