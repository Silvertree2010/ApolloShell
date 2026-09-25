import Foundation
import ApolloBase
import ApolloConfig
import ApolloShellCore

public struct SettingsStoreError: Error, Sendable, Hashable, CustomStringConvertible {
    public var message: String

    public var description: String { message }
}

public final class ObservationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (@Sendable () -> Void)?

    init(_ onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        let action = lock.withLock { () -> (@Sendable () -> Void)? in
            defer { onCancel = nil }
            return onCancel
        }
        action?()
    }
}

public final class SettingsStore: @unchecked Sendable {
    public typealias Observer = @Sendable (ShellSettingsFile, ShellSettingsFile) -> Void

    public let file: URL
    private let fileSystem: any ConfigFileSystem
    private let lock = NSLock()
    private let writeLock = NSLock()
    private var text: String?
    private var current = ShellSettingsFile()
    private var currentDiagnostics: [Diagnostic] = []
    private var observers: [Int: Observer] = [:]
    private var nextObserver = 0

    public init(file: URL, fileSystem: any ConfigFileSystem = DiskFileSystem()) {
        self.file = file
        self.fileSystem = fileSystem
        _ = reload()
    }

    public var settings: ShellSettingsFile { lock.withLock { current } }

    public var diagnostics: [Diagnostic] { lock.withLock { currentDiagnostics } }

    public var crashReportMode: CrashReportSettings.Mode {
        CrashReportSettings.Mode(rawValue: settings.crashReports) ?? .ask
    }

    public func observe(_ observer: @escaping Observer) -> ObservationToken {
        let key = lock.withLock { () -> Int in
            nextObserver += 1
            observers[nextObserver] = observer
            return nextObserver
        }
        return ObservationToken { [weak self] in
            guard let self else { return }
            _ = self.lock.withLock { self.observers.removeValue(forKey: key) }
        }
    }

    @discardableResult
    public func reload() -> Bool {
        let latest = fileSystem.exists(file) ? try? fileSystem.read(file) : nil
        return adopt(latest)
    }

    public func apply(_ change: ShellSettingsChange) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        let base = fileSystem.exists(file) ? try fileSystem.read(file) : ""
        let updated: String
        do {
            updated = try ShellSettingsFile.updating(base, file: file.path, set: change)
        } catch {
            throw SettingsStoreError(message: "settings.kdl has syntax errors, fix it before changing settings: \(file.path)")
        }
        if updated != base || !fileSystem.exists(file) {
            try fileSystem.write(updated, to: file)
        }
        adopt(updated)
    }

    @discardableResult
    private func adopt(_ latest: String?) -> Bool {
        let (old, new, notify) = lock.withLock { () -> (ShellSettingsFile, ShellSettingsFile, [Observer]) in
            let old = current
            guard latest != text else {
                return (old, old, [])
            }
            text = latest
            let (parsed, diagnostics) = ShellSettingsFile.parse(latest ?? "", file: file.path)
            current = parsed
            currentDiagnostics = diagnostics
            return (old, parsed, parsed == old ? [] : Array(observers.values))
        }
        for observer in notify {
            observer(old, new)
        }
        return old != new
    }
}
