import Testing
import Foundation
import ApolloConfig
@testable import ApolloShellCore
@testable import ApolloRuntime
@testable import ApolloProviders
@testable import ApolloShell

@MainActor
final class StreamOnlyMediaSource: MediaSource {
    var adapterAvailable = true
    var now: Date { Date(timeIntervalSince1970: 1_790_000_000) }
    var handler: (@MainActor (MediaStreamEvent) -> Void)?

    func startStream(_ handler: @escaping @MainActor (MediaStreamEvent) -> Void) -> Bool {
        self.handler = handler
        return true
    }
    func stopStream() { handler = nil }
    func send(_ command: MediaCommand) {}
    func seek(microseconds: Int) {}
    func appName(_ bundleIdentifier: String) -> String? { nil }
    func artworkAspect(_ data: Data) -> Double? { 1 }
    func openApp(_ bundleIdentifier: String) {}
}

@MainActor
@Suite("Live: media.artwork kommt aus dem MediaProvider")
struct ProviderImageTests {
    @Test("imageData leitet media-Bilder an MediaProvider.artworkData weiter, andere Quellen nicht")
    func mediaArtwork() throws {
        let source = StreamOnlyMediaSource()
        let provider = MediaProvider(source: source, clock: ManualRuntimeClock())
        var published: [[String]: Value] = [:]
        provider.start(ProviderContext(publish: { published[$0] = $1 }, emit: { _, _ in }, warn: { _ in }))
        provider.demandChanged([DependencyPath("media")])
        let json = #"{"type":"data","diff":false,"payload":{"title":"T","bundleIdentifier":"com.x","playing":true,"playbackRate":1,"durationMicros":200000000,"elapsedTimeMicros":0,"timestampEpochMicros":1790000000000000,"artworkData":"AAAA"}}"#
        source.handler?(.messages([try #require(MediaStreamMessage.parse(json))]))
        guard case .image(let artwork)? = published[["artwork"]] else {
            Issue.record("kein artwork veröffentlicht: \(published.keys)")
            return
        }
        let data = LiveShell.imageData([provider])
        #expect(data(artwork) == Data(base64Encoded: "AAAA"))
        #expect(data(ImageRef(source: "user-image", id: artwork.id)) == nil)
        #expect(LiveShell.imageData([])(artwork) == nil)
    }
}
