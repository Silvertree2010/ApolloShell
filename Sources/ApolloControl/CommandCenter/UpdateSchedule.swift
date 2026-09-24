import Foundation

public enum UpdateSchedule {
    public static func isDue(lastCheck: Date?, now: Date, autoCheck: Bool, interval: TimeInterval) -> Bool {
        guard autoCheck else { return false }
        guard let lastCheck, lastCheck <= now else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}
