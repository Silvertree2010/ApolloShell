import Foundation

public struct BatteryReading: Equatable, Sendable {
    public var level: Int
    public var charging: Bool
    public var onAC: Bool
    public var charged: Bool
    public var minutesToEmpty: Int
    public var minutesToFull: Int

    public init(level: Int, charging: Bool, onAC: Bool, charged: Bool = false, minutesToEmpty: Int = 0, minutesToFull: Int = 0) {
        self.level = level
        self.charging = charging
        self.onAC = onAC
        self.charged = charged
        self.minutesToEmpty = minutesToEmpty
        self.minutesToFull = minutesToFull
    }
}

public struct BatteryDetails: Equatable, Sendable {
    public var cycles: Int?
    public var healthPercent: Int?
    public var lowPowerMode: Bool

    public init(cycles: Int?, healthPercent: Int?, lowPowerMode: Bool) {
        self.cycles = cycles
        self.healthPercent = healthPercent
        self.lowPowerMode = lowPowerMode
    }
}

@MainActor
public protocol BatterySource: AnyObject {
    func read() -> BatteryReading?
    func readDetails() -> BatteryDetails
    func observeChanges(_ handler: @escaping @MainActor () -> Void)
    func stopObserving()
    func setLowPowerMode(_ on: Bool)
}

extension BatterySource {
    public func setLowPowerMode(_ on: Bool) {}
}
