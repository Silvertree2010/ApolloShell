import Darwin
import Foundation
import IOKit
import IOKit.ps
import ApolloShellCore

/// Reads for the "Performance" tab what SystemSampler does not have: the GPU,
/// the network, the battery with the time left. All public interfaces without
/// a permission (measured 14.09. on the M4 Pro). Temperatures are missing on
/// purpose: on Apple Silicon they only exist through SMC/private interfaces.
enum PerformanceSampler {
    /// The chip name for the subtitles, "Apple M4 Pro" for instance.
    static let chipName: String = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "Mac" }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }()

    /// The number of GPU cores out of the IORegistry ("gpu-core-count", M4 Pro: 20).
    static let gpuCores: Int? = accelerators { entry in
        IORegistryEntryCreateCFProperty(entry, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }.first

    /// The GPU load 0...1, the way the driver reports it in "PerformanceStatistics".
    /// Read only this one property: all the properties of the accelerator cost
    /// a measured 1.2 ms, this one 0.02 ms.
    static func gpuUsage() -> Double? {
        let values = accelerators { entry -> Int? in
            guard let stats = IORegistryEntryCreateCFProperty(
                entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { return nil }
            return stats["Device Utilization %"] as? Int
        }
        guard let busiest = values.max() else { return nil }
        return min(max(Double(busiest) / 100, 0), 1)
    }

    /// The sum of the 64-bit byte counters (if_data64) over the counted
    /// interfaces, see `NetworkMath.counts`. Measured 0.03 ms.
    static func networkCounters() -> NetCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        // Some reserve: when an interface is added between the two calls, the
        // second one would otherwise fail with ENOMEM.
        var buffer = [UInt8](repeating: 0, count: length + 2048)
        length = buffer.count
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var total = NetCounters.zero
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let size = Int(header.ifm_msglen)
                guard size > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if NetworkMath.counts(flags: message.ifm_flags, type: message.ifm_data.ifi_type) {
                        total.received &+= message.ifm_data.ifi_ibytes
                        total.sent &+= message.ifm_data.ifi_obytes
                    }
                }
                offset += size
            }
        }
        return total
    }

    /// The built-in battery with the time left in minutes (to full while
    /// charging, otherwise to empty; IOKit reports -1 while it is still working
    /// it out). `nil` on Macs without a battery.
    static func battery() -> (state: BatteryState, minutes: Int?)? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            let state = BatteryState(
                level: Int((Double(current) / Double(max) * 100).rounded()),
                charging: charging,
                onAC: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            )
            return (state, d[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int)
        }
        return nil
    }

    /// A built-in battery there or not - for the "Performance" page (the
    /// battery on the right or not) without reading the whole state.
    static var hasInternalBattery: Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        return sources.contains { source in
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            else { return false }
            return (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
        }
    }

    /// Calls `read` for every graphics accelerator (Apple Silicon: one).
    private static func accelerators<T>(_ read: (io_registry_entry_t) -> T?) -> [T] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var results: [T] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if let value = read(entry) { results.append(value) }
            IOObjectRelease(entry)
        }
        return results
    }
}
