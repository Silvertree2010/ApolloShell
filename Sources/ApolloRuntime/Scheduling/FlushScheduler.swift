import Foundation

@MainActor
public protocol FlushScheduler: AnyObject {
    func requestFlush(_ flush: @escaping @MainActor () -> Void)
}

@MainActor
public final class ManualFlushScheduler: FlushScheduler {
    private var pending: [@MainActor () -> Void] = []

    public init() {}

    public func requestFlush(_ flush: @escaping @MainActor () -> Void) {
        pending.append(flush)
    }

    public func runPending() {
        let flushes = pending
        pending.removeAll()
        for flush in flushes {
            flush()
        }
    }
}

#if canImport(Darwin)
@MainActor
public final class RunLoopFlushScheduler: FlushScheduler {
    private static let flushOrder: CFIndex = 1_000_000

    private var pending: [@MainActor () -> Void] = []
    private nonisolated(unsafe) var observer: CFRunLoopObserver?

    public init() {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            Self.flushOrder
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.runPending()
            }
        }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    deinit {
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    public func requestFlush(_ flush: @escaping @MainActor () -> Void) {
        let shouldWake = pending.isEmpty
        pending.append(flush)
        if shouldWake {
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    private func runPending() {
        let flushes = pending
        pending.removeAll()
        for flush in flushes {
            flush()
        }
    }
}
#endif
