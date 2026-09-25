import Foundation
import ApolloShellCore

@MainActor
final class MainBlockObserver {
    static let shared = MainBlockObserver()

    private var meter = BlockMeter()
    private var observers: [CFRunLoopObserver] = []

    func takeLongest() -> Double {
        install()
        return meter.take(now: Self.now())
    }

    private func install() {
        guard observers.isEmpty else { return }
        let woke = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { _, _ in
            MainActor.assumeIsolated { MainBlockObserver.shared.meter.began(at: MainBlockObserver.now()) }
        }
        let sleeps = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { _, _ in
            MainActor.assumeIsolated { MainBlockObserver.shared.meter.ended(at: MainBlockObserver.now()) }
        }
        for observer in [woke, sleeps].compactMap({ $0 }) {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            observers.append(observer)
        }
        meter.began(at: Self.now())
    }

    nonisolated static func now() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }
}
