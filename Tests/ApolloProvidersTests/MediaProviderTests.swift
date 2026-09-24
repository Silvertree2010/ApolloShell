import Testing
import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
@Suite("Provider media")
struct MediaProviderTests {
    func make() -> (ProviderHarness, FakeMediaSource, MediaProvider) {
        let harness = ProviderHarness()
        let source = FakeMediaSource(clock: harness.clock)
        let provider = MediaProvider(source: source, clock: harness.clock)
        harness.register(provider)
        return (harness, source, provider)
    }

    @Test("Liefert jedes Registry-Feld aus dem Adapter-Strom")
    func deliversAllFields() {
        let (harness, source, provider) = make()
        harness.demand("media")
        source.playing()
        harness.flush()
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("media")).isEmpty)
        #expect(harness.value("media", "available") == .bool(true))
        #expect(harness.value("media", "playing") == .bool(true))
        #expect(harness.value("media", "title") == .string("Starboy"))
        #expect(harness.value("media", "duration") == .number(200))
        #expect(harness.value("media", "elapsed") == .number(10))
        #expect(harness.value("media", "progress") == .number(0.05))
        #expect(harness.value("media", "app") == .string("com.spotify.client"))
        #expect(harness.value("media", "app-name") == .string("Spotify"))
        #expect(harness.value("media", "app-icon") == .image(ImageRef(source: "app-icon", id: "com.spotify.client")))
        #expect(harness.value("media", "kind") == .string("music"))
        #expect(harness.value("media", "unavailable") == .null)
        guard case .image(let artwork) = harness.value("media", "artwork") else {
            Issue.record("Cover fehlt")
            return
        }
        #expect(provider.artworkData(artwork.id) == Data(base64Encoded: "AAAA"))
    }

    @Test("elapsed läuft alle 0,5 s nur bei Nachfrage und Wiedergabe")
    func elapsedTicks() {
        let (harness, source, _) = make()
        harness.demand("media", "title")
        source.playing()
        harness.advance(1)
        #expect(harness.value("media", "elapsed") == .number(10))
        let token = harness.demand("media", "elapsed")
        harness.advance(0.5)
        #expect(harness.value("media", "elapsed") == .number(11.5))
        harness.release(token)
        harness.advance(2)
        #expect(harness.value("media", "elapsed") == .number(11.5))
        harness.demand("media", "elapsed")
        source.playing(elapsed: 50, playing: false)
        harness.advance(2)
        #expect(harness.value("media", "elapsed") == .number(50))
    }

    @Test("Adapter nur bei Nachfrage, Neustart 2/4/8/16/32 s, danach adapter-crashed")
    func restartsWithBackoff() {
        let (harness, source, _) = make()
        harness.advance(10)
        #expect(source.launches == 0)
        let token = harness.demand("media", "title")
        #expect(source.launches == 1)
        var expected = 1
        for delay in [2.0, 4, 8, 16, 32] {
            source.crash()
            harness.advance(delay - 0.25)
            #expect(source.launches == expected)
            harness.advance(0.25)
            expected += 1
            #expect(source.launches == expected)
        }
        source.crash()
        harness.advance(100)
        #expect(source.launches == 6)
        #expect(harness.value("media", "unavailable") == .string("adapter-crashed"))
        #expect(harness.value("media", "available") == .bool(false))
        harness.release(token)
        #expect(source.streaming == false)
        harness.demand("media", "title")
        #expect(source.launches == 7)
        #expect(harness.value("media", "unavailable") == .null)
    }

    @Test("Fehlender Adapter: no-adapter, Aktionen tun nichts und warnen")
    func missingAdapter() async throws {
        let (harness, source, _) = make()
        source.adapterAvailable = false
        harness.demand("media")
        #expect(harness.value("media", "unavailable") == .string("no-adapter"))
        #expect(harness.value("media", "available") == .bool(false))
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("media"), strict: false).isEmpty)
        _ = try await harness.perform("media", "media.play-pause")
        #expect(source.commands.isEmpty)
        #expect(harness.warnings.filter { $0.severity == .warning }.count == 1)
    }

    @Test("Aktionen und Ereignis bei neuem Titel")
    func actionsAndEvents() async throws {
        let (harness, source, _) = make()
        harness.demand("media", "title")
        source.playing()
        #expect(harness.events.isEmpty)
        source.playing(title: "Blinding Lights")
        #expect(harness.eventNames() == ["media.track-changed"])
        _ = try await harness.perform("media", "media.play-pause")
        _ = try await harness.perform("media", "media.next")
        _ = try await harness.perform("media", "media.previous")
        _ = try await harness.perform("media", "media.seek", [.number(12.5)])
        _ = try await harness.perform("media", "media.open-app")
        #expect(source.commands == [.togglePlayPause, .nextTrack, .previousTrack])
        #expect(source.seeks == [12_500_000])
        #expect(source.opened == ["com.spotify.client"])
    }

    @Test("Leere Nachricht räumt erst nach 0,6 s ab")
    func emptyAfterDelay() {
        let (harness, source, _) = make()
        harness.demand("media", "title")
        source.playing()
        source.deliver(#"{"type":"data","diff":false,"payload":{}}"#)
        harness.flush()
        #expect(harness.value("media", "title") == .string("Starboy"))
        harness.advance(0.75)
        #expect(harness.value("media", "title") == .null)
        #expect(harness.value("media", "playing") == .bool(false))
    }
}
