import Foundation

enum CPUTime {
    static func now() -> UInt64 {
        #if canImport(Darwin)
        clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        #else
        var time = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
        return UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec)
        #endif
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
