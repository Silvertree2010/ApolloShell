@testable import ApolloProviders

@MainActor
final class FakeBatterySource: BatterySource {
    var reading: BatteryReading?
    var details = BatteryDetails(cycles: 312, healthPercent: 91, lowPowerMode: false)
    var reads = 0
    var detailReads = 0
    var observing = false
    private var handler: (@MainActor () -> Void)?

    init(_ reading: BatteryReading?) {
        self.reading = reading
    }

    func read() -> BatteryReading? {
        reads += 1
        return reading
    }

    func readDetails() -> BatteryDetails {
        detailReads += 1
        return details
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        observing = true
        self.handler = handler
    }

    var lowPowerSets: [Bool] = []

    func setLowPowerMode(_ on: Bool) {
        lowPowerSets.append(on)
        details.lowPowerMode = on
    }

    func stopObserving() {
        observing = false
        handler = nil
    }

    func change(_ update: (inout BatteryReading) -> Void) {
        guard var reading else { return }
        update(&reading)
        self.reading = reading
        handler?()
    }
}
