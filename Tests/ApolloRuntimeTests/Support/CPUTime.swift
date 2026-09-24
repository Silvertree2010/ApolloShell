import Foundation

enum CPUTime {
    static func now() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    }

    static func measure(_ body: () -> Void) -> Double {
        let start = now()
        body()
        return Double(now() - start) / 1_000_000
    }

    static func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    #if DEBUG
    static let isDebug = true
    #else
    static let isDebug = false
    #endif
}
