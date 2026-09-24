import Foundation

@MainActor
public protocol ClockSource: AnyObject {
    var now: Date { get }
    var timeZone: TimeZone { get }
    func observeChanges(_ handler: @escaping @MainActor () -> Void)
    func stopObserving()
}
