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
final class PictureSystemSource: SystemSource {
    var darkMode = false
    var nightShift: Bool? = nil
    var microphoneMuted: Bool? = nil
    var showDesktopAvailable = false
    var accentColor = "blue"
    var reduceMotion = false
    var reduceTransparency = false
    var info = SystemInfo(userName: "andrin", fullName: "A", hasUserImage: true, hostName: "h", model: "m", chip: "c", macosVersion: "26", kernelVersion: "25")
    var uptime: Double = 1
    var appleDockHidden = false
    var reads = 0
    func setDarkMode(_ on: Bool) {}
    func setNightShift(_ on: Bool) -> Bool { false }
    func setMicrophoneMuted(_ muted: Bool) -> Bool { false }
    func setAppleDockHidden(_ hidden: Bool) {}
    func run(_ command: SystemCommand) {}
    func pickColor(_ completion: @escaping @MainActor (String?) -> Void) {}
    func observeChanges(_ handler: @escaping @MainActor () -> Void) {}
    func stopObserving() {}
    func userImageData() -> Data? {
        reads += 1
        return Data([0xFF, 0xD8, 0xFF])
    }
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

    @Test("system.user-image kommt über imageData aus der Systemquelle, nur für den eigenen User")
    func userImage() throws {
        let source = PictureSystemSource()
        let provider = SystemProvider(source: source, clock: ManualRuntimeClock())
        let data = LiveShell.imageData([provider])
        #expect(data(ImageRef(source: "user-image", id: "andrin")) == Data([0xFF, 0xD8, 0xFF]))
        #expect(data(ImageRef(source: "user-image", id: "someone")) == nil)
        #expect(data(ImageRef(source: "media", id: "andrin")) == nil)
        #expect(source.reads == 1)
    }

    @Test("dscl-Ausgabe von JPEGPhoto wird zu Bytes")
    func dsclHex() {
        #expect(SystemMacSource.photoData("JPEGPhoto:\n ffd8ffe0 00104a46\n 49460001\n") == Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01]))
        #expect(SystemMacSource.photoData("No such key: JPEGPhoto") == nil)
    }
}
