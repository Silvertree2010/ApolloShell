import Foundation
import IOKit
import IOKit.ps
import ApolloProviders
import ApolloShellCore

@MainActor
final class SystemBatterySource: BatterySource {
    private var runLoopSource: CFRunLoopSource?
    private var handler: (@MainActor () -> Void)?

    func read() -> BatteryReading? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return BatteryReading(
                level: Int((Double(current) / Double(max) * 100).rounded()),
                charging: (d[kIOPSIsChargingKey] as? Bool) ?? false,
                onAC: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
                charged: (d[kIOPSIsChargedKey] as? Bool) ?? false,
                minutesToEmpty: d[kIOPSTimeToEmptyKey] as? Int ?? 0,
                minutesToFull: d[kIOPSTimeToFullChargeKey] as? Int ?? 0
            )
        }
        return nil
    }

    func readDetails() -> BatteryDetails {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        defer { if service != 0 { IOObjectRelease(service) } }
        func int(_ key: String) -> Int? {
            guard service != 0 else { return nil }
            return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
        }
        return BatteryDetails(
            cycles: int("CycleCount"),
            healthPercent: StatusPopoutBatteryHealth.percent(
                rawMax: int("AppleRawMaxCapacity"), nominal: int("NominalChargeCapacity"), design: int("DesignCapacity")
            ),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        stopObserving()
        self.handler = handler
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let owner = Unmanaged<SystemBatterySource>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { owner.handler?() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    func stopObserving() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        handler = nil
    }
}
