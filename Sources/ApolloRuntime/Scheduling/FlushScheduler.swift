import Foundation

@MainActor
public protocol FlushScheduler: AnyObject {
    func requestFlush(_ flush: @escaping @MainActor () -> Void)
}

@MainActor
public final class ManualFlushScheduler: FlushScheduler {
    private var pending: (@MainActor () -> Void)?

    public init() {}

    public func requestFlush(_ flush: @escaping @MainActor () -> Void) {
        pending = flush
    }

    public func runPending() {
        guard let flush = pending else { return }
        pending = nil
        flush()
    }
}

@MainActor
public final class RunLoopFlushScheduler: FlushScheduler {
    private static let flushOrder: CFIndex = 1_000_000

    private var pending: (@MainActor () -> Void)?
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
        let shouldWake = pending == nil
        pending = flush
        if shouldWake {
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    private func runPending() {
        guard let flush = pending else { return }
        pending = nil
        flush()
    }
}
