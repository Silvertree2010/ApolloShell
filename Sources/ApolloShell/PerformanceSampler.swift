import Darwin
import Foundation
import IOKit
import IOKit.ps
import ApolloShellCore

/// Liest fuer den Reiter "Leistung", was SystemSampler nicht hat: GPU,
/// Netzwerk, Akku mit Restzeit. Alles oeffentliche Schnittstellen ohne
/// Freigabe (gemessen 14.09. auf dem M4 Pro). Temperaturen fehlen bewusst:
/// auf Apple Silicon gibt es sie nur ueber SMC/private Schnittstellen.
enum PerformanceSampler {
    /// Chipname fuer die Untertitel, z. B. "Apple M4 Pro".
    static let chipName: String = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "Mac" }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }()

    /// Anzahl GPU-Kerne aus der IORegistry ("gpu-core-count", M4 Pro: 20).
    static let gpuCores: Int? = accelerators { entry in
        IORegistryEntryCreateCFProperty(entry, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }.first

    /// GPU-Auslastung 0...1, wie der Treiber sie in "PerformanceStatistics"
    /// meldet. Nur diese eine Eigenschaft lesen: alle Eigenschaften des
    /// Beschleunigers kosten gemessen 1,2 ms, die eine 0,02 ms.
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

    /// Summe der 64-Bit-Byte-Zaehler (if_data64) ueber die gezaehlten
    /// Schnittstellen, siehe `NetworkMath.counts`. Gemessen 0,03 ms.
    static func networkCounters() -> NetCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        // Etwas Reserve: kommt zwischen den beiden Aufrufen eine Schnittstelle
        // dazu, schlaegt der zweite sonst mit ENOMEM fehl.
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

    /// Eingebauter Akku mit Restzeit in Minuten (beim Laden bis voll, sonst
    /// bis leer; IOKit meldet -1, solange es noch rechnet). `nil` auf
    /// Macs ohne Akku.
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

    /// Eingebauter Akku vorhanden oder nicht - fuer die Seite "Leistung"
    /// (Akku rechts oder nicht) ohne den ganzen Zustand zu lesen.
    static var hasInternalBattery: Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        return sources.contains { source in
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            else { return false }
            return (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
        }
    }

    /// Ruft `read` fuer jeden Grafikbeschleuniger auf (Apple Silicon: einer).
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
