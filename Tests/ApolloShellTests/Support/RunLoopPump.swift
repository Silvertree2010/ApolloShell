import Foundation

@MainActor
enum RunLoopPump {
    static func run(_ seconds: TimeInterval) {
        let wake = Timer(timeInterval: 0.002, repeats: true) { _ in }
        RunLoop.main.add(wake, forMode: .default)
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        wake.invalidate()
    }
}
