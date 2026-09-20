import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Toasts: the battery warning levels")
struct BatteryToastTrackerTests {
    /// Only the level of the warning, 0 = no warning.
    private func warnedLevel(_ events: [BatteryToastEvent]) -> Int {
        for event in events {
            if case .warning(let level) = event { return level.level }
        }
        return 0
    }

    @Test("Crossing downwards on battery", arguments: [
        (100, 20, 20), (21, 20, 20), (20, 19, 0), (25, 8, 10), (11, 4, 5), (6, 5, 5), (5, 4, 0), (30, 25, 0),
    ])
    func crossing(last: Int, new: Int, expected: Int) {
        var tracker = BatteryToastTracker(percent: last, onBattery: true)
        let events = tracker.update(percent: new, onBattery: true)
        #expect(warnedLevel(events) == expected)
    }

    @Test("On the power adapter never a warning, not even below 5 %")
    func noWarningOnAC() {
        var tracker = BatteryToastTracker(percent: 30, onBattery: false)
        let events = tracker.update(percent: 4, onBattery: false)
        #expect(events.isEmpty)
        #expect(tracker.reference == 4)
    }

    @Test("Level 5 is critical and therefore an error, 20 and 10 are warnings")
    func kinds() {
        let levels = BatteryWarningLevel.caelestiaDefaults
        #expect(levels.map(\.level) == [20, 10, 5])
        #expect(levels.map(\.kind) == [.warning, .warning, .error])
    }

    @Test("The levels are sorted upwards, however they come")
    func sortedLevels() {
        let tracker = BatteryToastTracker(percent: 50, onBattery: true)
        #expect(tracker.levels.map(\.level) == [5, 10, 20])
    }

    @Test("The start is no event: at 15 % on battery no toast")
    func noToastForInitialState() {
        var tracker = BatteryToastTracker(percent: 15, onBattery: true)
        let events = tracker.update(percent: 15, onBattery: true)
        #expect(events.isEmpty)
    }

    @Test("The same state reported again: nothing")
    func samePercentIgnored() {
        var tracker = BatteryToastTracker(percent: 21, onBattery: true)
        let first = tracker.update(percent: 20, onBattery: true)
        let again = tracker.update(percent: 20, onBattery: true)
        #expect(warnedLevel(first) == 20)
        #expect(again.isEmpty)
    }

    @Test("Plugging in reports the charger and sets the comparison to 100")
    func plugResets() {
        var tracker = BatteryToastTracker(percent: 15, onBattery: true)
        let plugged = tracker.update(percent: 15, onBattery: false)
        #expect(plugged == [.chargerConnected])
        #expect(tracker.reference == 100)
        // Unplugging right away again: the warning for 15 % comes once more.
        let events = tracker.update(percent: 15, onBattery: true)
        #expect(events.first == .chargerDisconnected)
        #expect(warnedLevel(events) == 20)
    }

    @Test("When it goes on charging after plugging in, the new state counts (as in Caelestia)")
    func chargingMovesReference() {
        var tracker = BatteryToastTracker(percent: 15, onBattery: true)
        _ = tracker.update(percent: 15, onBattery: false)
        _ = tracker.update(percent: 16, onBattery: false)
        let events = tracker.update(percent: 16, onBattery: true)
        #expect(events == [.chargerDisconnected])
    }

    @Test("Unplugging with a full battery: only the toast, no warning")
    func unplugHigh() {
        var tracker = BatteryToastTracker(percent: 80, onBattery: false)
        let events = tracker.update(percent: 80, onBattery: true)
        #expect(events == [.chargerDisconnected])
    }
}

@Suite("Toasts: the queue")
struct ToastQueueTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func queue(count: Int) -> ToastQueue {
        var queue = ToastQueue()
        for index in 0..<count {
            queue.push(title: "T\(index)", message: "", symbol: nil, kind: .info,
                       now: start.addingTimeInterval(Double(index)))
        }
        return queue
    }

    @Test("The newest first, at most 4 visible")
    func maxVisible() {
        let queue = queue(count: 6)
        #expect(queue.visible().map(\.title) == ["T5", "T4", "T3", "T2"])
        #expect(queue.entries.count == 6)
    }

    @Test("Whoever falls out of the visible area is marked as hidden")
    func hiddenFlag() {
        let queue = queue(count: 5)
        #expect(queue.entries.map(\.hasBeenHidden) == [false, false, false, false, true])
    }

    @Test("All of them live 5 s, warnings and errors too (Caelestia's default value)")
    func timeout() {
        var queue = ToastQueue()
        let warning = queue.push(title: "W", message: "", symbol: nil, kind: .warning, now: start)
        let error = queue.push(title: "E", message: "", symbol: nil, kind: .error, now: start)
        #expect(warning.deadline == start.addingTimeInterval(5))
        #expect(error.deadline == start.addingTimeInterval(5))
    }

    @Test("The oldest run out first, the hidden ones run out along with them")
    func expiryOrder() {
        var queue = queue(count: 6) // T0 bei +0 s ... T5 bei +5 s
        #expect(queue.nextDeadline == start.addingTimeInterval(5))
        let changed = queue.expire(now: start.addingTimeInterval(6))
        #expect(changed)
        #expect(queue.entries.map(\.title) == ["T5", "T4", "T3", "T2"])
        let changedAgain = queue.expire(now: start.addingTimeInterval(6))
        #expect(!changedAgain)
        #expect(queue.nextDeadline == start.addingTimeInterval(7))
    }

    @Test("A click closes it, the next one moves up and is marked as having been hidden")
    func dismissPromotes() {
        var queue = queue(count: 5)
        let middle = queue.visible()[1].id
        let removed = queue.dismiss(id: middle)
        #expect(removed)
        let visible = queue.visible()
        #expect(visible.map(\.title) == ["T4", "T2", "T1", "T0"])
        #expect(visible.last?.hasBeenHidden == true)
        let removedAgain = queue.dismiss(id: middle)
        #expect(!removedAgain)
    }

    @Test("Full screen: nothing visible, the list stays")
    func fullscreen() {
        let queue = queue(count: 2)
        #expect(queue.visible(fullscreen: true).isEmpty)
        #expect(queue.entries.count == 2)
    }

    @Test("Without a symbol the one of the kind", arguments: [
        (ToastKind.info, "info.circle.fill"),
        (ToastKind.success, "checkmark.circle.fill"),
        (ToastKind.warning, "exclamationmark.triangle.fill"),
        (ToastKind.error, "exclamationmark.circle.fill"),
    ])
    func defaultSymbol(kind: ToastKind, symbol: String) {
        var queue = ToastQueue()
        let plain = queue.push(title: "", message: "", symbol: nil, kind: kind, now: start)
        let custom = queue.push(title: "", message: "", symbol: "mic.fill", kind: kind, now: start)
        #expect(plain.symbol == symbol)
        #expect(custom.symbol == "mic.fill")
    }

    @Test("The stack height: the toasts plus the gaps between them", arguments: [
        (0, 0.0), (1, 56.0), (3, 184.0), (4, 248.0),
    ])
    func stackHeight(count: Int, height: Double) {
        #expect(ToastLayout.stackHeight(count: count) == height)
    }
}

@Suite("Toasts: texts and devices")
struct ToastTextTests {
    @Test("The charger on and off")
    func charger() {
        #expect(ToastText.chargerConnected.title == "Charger Connected")
        #expect(ToastText.chargerConnected.message == "Battery is charging")
        #expect(ToastText.chargerDisconnected.title == "Charger Unplugged")
        #expect(ToastText.chargerDisconnected.message == "Battery is discharging")
    }

    @Test("Audio: the device name in the message, empty = unknown")
    func audio() {
        #expect(ToastText.audioOutput("AirPods Pro").message == "Now using AirPods Pro")
        #expect(ToastText.audioOutput("AirPods Pro").symbol == "speaker.wave.2.fill")
        #expect(ToastText.audioInput("  ").message == "Now using Unknown Device")
        #expect(ToastText.audioInput("X").title == "Audio Input Changed")
    }

    @Test("Battery events become texts, level 5 as an error")
    func batteryTexts() {
        #expect(ToastText.battery(.chargerConnected) == ToastText.chargerConnected)
        let critical = BatteryWarningLevel.caelestiaDefaults[2]
        let content = ToastText.battery(.warning(critical))
        #expect(content.title == "Battery Almost Empty" && content.kind == .error)
        #expect(ToastText.battery(.warning(BatteryWarningLevel.caelestiaDefaults[0])).kind == .warning)
    }

    @Test("A device change: the first name does not count, the same one does not either")
    func deviceTracker() {
        var tracker = ToastDeviceTracker()
        let initial = tracker.update(name: "MacBook Pro-Lautsprecher")
        let same = tracker.update(name: "MacBook Pro-Lautsprecher")
        let changed = tracker.update(name: "AirPods")
        #expect(!initial && !same && changed)
        #expect(tracker.name == "AirPods")
    }
}
