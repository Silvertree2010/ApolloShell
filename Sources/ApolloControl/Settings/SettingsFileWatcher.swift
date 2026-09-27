#if canImport(Darwin)
import Foundation

public final class SettingsFileWatcher: @unchecked Sendable {
    private let store: SettingsStore
    private let queue = DispatchQueue(label: "apollo.control.settings-watch")
    private var source: (any DispatchSourceFileSystemObject)?
    private var fileSource: (any DispatchSourceFileSystemObject)?
    private var watched: String?
    private var running = false

    public init(store: SettingsStore) {
        self.store = store
    }

    public func start() {
        queue.sync {
            running = true
            arm()
        }
    }

    public func stop() {
        queue.sync {
            running = false
            source?.cancel()
            source = nil
            fileSource?.cancel()
            fileSource = nil
            watched = nil
        }
    }

    private func arm() {
        guard running else { return }
        armFile()
        while true {
            let target = nearestExistingFolder(store.file.deletingLastPathComponent())
            guard target != watched else { return }
            source?.cancel()
            source = nil
            watched = nil
            let fd = open(target, O_EVTONLY)
            guard fd >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link], queue: queue)
            source.setEventHandler { [weak self] in self?.changed() }
            source.setCancelHandler { close(fd) }
            self.source = source
            watched = target
            source.resume()
        }
    }

    private func armFile() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(store.file.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(fd) }
        fileSource = source
        source.resume()
    }

    private func changed() {
        watched = nil
        arm()
        store.reload()
    }

    private func nearestExistingFolder(_ url: URL) -> String {
        var candidate = url
        while candidate.path != "/" {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate.path
            }
            candidate = candidate.deletingLastPathComponent()
        }
        return "/"
    }
}
#endif
