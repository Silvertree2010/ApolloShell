import Foundation
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
final class FakeMediaSource: MediaSource {
    let clock: ManualRuntimeClock
    let base = Date(timeIntervalSince1970: 1_790_000_000)
    var adapterAvailable = true
    var launchSucceeds = true
    var launches = 0
    var stops = 0
    var commands: [MediaCommand] = []
    var seeks: [Int] = []
    var opened: [String] = []
    private var handler: (@MainActor (MediaStreamEvent) -> Void)?

    init(clock: ManualRuntimeClock) {
        self.clock = clock
    }

    var now: Date { base.addingTimeInterval(clock.now) }

    var streaming: Bool { handler != nil }

    func startStream(_ handler: @escaping @MainActor (MediaStreamEvent) -> Void) -> Bool {
        launches += 1
        guard launchSucceeds else { return false }
        self.handler = handler
        return true
    }

    func stopStream() {
        stops += 1
        handler = nil
    }

    func send(_ command: MediaCommand) {
        commands.append(command)
    }

    func seek(microseconds: Int) {
        seeks.append(microseconds)
    }

    func appName(_ bundleIdentifier: String) -> String? {
        bundleIdentifier == "com.spotify.client" ? "Spotify" : nil
    }

    func artworkAspect(_ data: Data) -> Double? {
        1
    }

    func openApp(_ bundleIdentifier: String) {
        opened.append(bundleIdentifier)
    }

    func deliver(_ json: String) {
        guard let message = MediaStreamMessage.parse(json) else { return }
        handler?(.messages([message]))
    }

    func crash() {
        let current = handler
        handler = nil
        current?(.exited(1))
    }

    func playing(title: String = "Starboy", elapsed: Double = 10, playing: Bool = true) {
        let micros = Int(now.timeIntervalSince1970 * 1_000_000)
        deliver("""
        {"type":"data","diff":false,"payload":{"title":"\(title)","artist":"The Weeknd","album":"Starboy","bundleIdentifier":"com.spotify.client","playing":\(playing),"playbackRate":1,"durationMicros":200000000,"elapsedTimeMicros":\(Int(elapsed * 1_000_000)),"timestampEpochMicros":\(micros),"artworkData":"AAAA"}}
        """)
    }
}
