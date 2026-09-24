import Foundation
import Synchronization

@MainActor
public protocol RuntimeClock: AnyObject {
    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> ScheduledWork
}

@MainActor
public final class ScheduledWork {
    private var cancelled = false
    private let onCancel: () -> Void

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        guard !cancelled else { return }
        cancelled = true
        onCancel()
    }
}

@MainActor
public final class ManualRuntimeClock: RuntimeClock {
    private struct Entry {
        let id: Int
        let fireAt: Double
        let action: @MainActor () -> Void
    }

    private var entries: [Entry] = []
    private var nextID = 0
    public private(set) var now: Double = 0

    public init() {}

    public func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> ScheduledWork {
        let id = nextID
        nextID += 1
        entries.append(Entry(id: id, fireAt: now + seconds, action: action))
        return ScheduledWork { [weak self] in
            self?.entries.removeAll { $0.id == id }
        }
    }

    public func advance(by seconds: Double) {
        now += seconds
        while true {
            guard let index = entries.firstIndex(where: { $0.fireAt <= now }) else { break }
            let entry = entries.remove(at: index)
            entry.action()
        }
    }
}

@MainActor
public final class DispatchRuntimeClock: RuntimeClock {
    public init() {}

    public func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> ScheduledWork {
        let cancelled = Mutex(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard !cancelled.withLock({ $0 }) else { return }
            MainActor.assumeIsolated {
                action()
            }
        }
        return ScheduledWork {
            cancelled.withLock { $0 = true }
        }
    }
}
