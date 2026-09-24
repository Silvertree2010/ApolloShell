import Foundation
import CoreServices

@MainActor
final class ReloadDebouncer {
    let delay: TimeInterval
    private var generation = 0
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    var fire: @MainActor () -> Void = {}
    private(set) var fired = 0
    private(set) var pokes = 0

    init(delay: TimeInterval = 0.15, schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
    }) {
        self.delay = delay
        self.schedule = schedule
    }

    func poke() {
        pokes += 1
        generation += 1
        let current = generation
        schedule(delay) { [weak self] in
            guard let self, self.generation == current else { return }
            self.fired += 1
            self.fire()
        }
    }
}

final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @Sendable ([String]) -> Void

    init(onChange: @escaping @Sendable ([String]) -> Void) {
        self.onChange = onChange
    }

    func watch(_ paths: [String]) {
        stop()
        let unique = Array(Set(paths.filter { FileManager.default.fileExists(atPath: $0) })).sorted()
        guard !unique.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let paths = (Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String]) ?? []
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange(paths)
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, unique as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
