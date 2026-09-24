import AppKit
import ApplicationServices
import ApolloProviders
import ApolloShellCore

@MainActor
final class SystemWindowSource: WindowSource {
    private var worker: FrontWindowWorker?
    private var observer: NSObjectProtocol?

    func start(_ handler: @escaping @MainActor (FrontWindowState?) -> Void) {
        stop()
        let worker = FrontWindowWorker { state in
            Task { @MainActor in handler(state) }
        }
        self.worker = worker
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        follow()
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        worker?.stop()
        worker = nil
    }

    private func follow() {
        let app = NSWorkspace.shared.frontmostApplication
        worker?.follow(FrontApp(
            pid: app?.processIdentifier ?? 0,
            bundleID: app?.bundleIdentifier,
            name: app?.localizedName,
            path: app?.bundleURL?.path
        ), trusted: AXIsProcessTrusted())
    }
}

struct FrontApp: Sendable, Equatable {
    let pid: pid_t
    let bundleID: String?
    let name: String?
    let path: String?
}

final class FrontWindowWorker: @unchecked Sendable {
    private static let notifications = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXTitleChangedNotification, kAXWindowResizedNotification]

    private let queue = DispatchQueue(label: AppIdentity.scoped("window"))
    private let deliver: @Sendable (FrontWindowState?) -> Void
    private var app: FrontApp?
    private var trusted = false
    private var observer: AXObserver?
    private var running = true

    init(deliver: @escaping @Sendable (FrontWindowState?) -> Void) {
        self.deliver = deliver
    }

    func follow(_ app: FrontApp, trusted: Bool) {
        queue.async { [self] in
            guard running else { return }
            if app != self.app || trusted != self.trusted {
                unwatch()
                self.app = app
                self.trusted = trusted
                if trusted { watch(app.pid) }
            }
            read()
        }
    }

    func stop() {
        queue.async { [self] in
            running = false
            unwatch()
            app = nil
        }
    }

    fileprivate func changed() {
        queue.async { [self] in
            guard running else { return }
            read()
        }
    }

    private func read() {
        guard let app, app.pid > 0 else { return deliver(nil) }
        var title: String?
        var fullscreen = false
        if trusted {
            let element = AXUIElementCreateApplication(app.pid)
            if let window = AX.element(element, kAXFocusedWindowAttribute) ?? AX.element(element, kAXMainWindowAttribute) {
                title = AX.string(window, kAXTitleAttribute)
                fullscreen = AX.bool(window, AX.fullScreenAttribute) ?? false
            }
        }
        deliver(FrontWindowState(bundleID: app.bundleID, appName: app.name, appPath: app.path, title: title, fullscreen: fullscreen))
    }

    private func watch(_ pid: pid_t) {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return }
        var created: AXObserver?
        let status = AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<FrontWindowWorker>.fromOpaque(refcon).takeUnretainedValue().changed()
        }, &created)
        guard status == .success, let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let element = AXUIElementCreateApplication(pid)
        for name in Self.notifications {
            AXObserverAddNotification(created, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
    }

    private func unwatch() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
    }
}
