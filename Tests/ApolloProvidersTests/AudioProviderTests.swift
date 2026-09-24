import Testing
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Provider audio")
struct AudioProviderTests {
    func make() -> (ProviderHarness, FakeAudioSource) {
        let harness = ProviderHarness()
        let source = FakeAudioSource()
        harness.register(AudioProvider(source: source, clock: harness.clock))
        return (harness, source)
    }

    @Test("Liefert jedes Registry-Feld mit Geräten und Symbol")
    func deliversAllFields() {
        let (harness, _) = make()
        harness.demand("audio")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("audio")).isEmpty)
        #expect(harness.value("audio", "volume") == .number(0.35))
        #expect(harness.value("audio", "output.name") == .string("MacBook Pro Speakers"))
        #expect(harness.value("audio", "input.volume") == .number(0.8))
        #expect(harness.value("audio", "input.muted") == .bool(false))
        #expect(harness.value("audio", "symbol") == .string("speaker.wave.2.fill"))
        guard case .list(let outputs) = harness.value("audio", "outputs") else {
            Issue.record("outputs fehlt")
            return
        }
        #expect(outputs == [
            .record(Record([("id", .string("builtin")), ("name", .string("MacBook Pro Speakers")), ("active", .bool(true))])),
            .record(Record([("id", .string("airpods")), ("name", .string("AirPods Pro")), ("active", .bool(false))])),
        ])
    }

    @Test("Aktionen schalten über die Quelle und begrenzen auf 0…1")
    func actions() async throws {
        let (harness, source) = make()
        harness.demand("audio", "volume", "muted", "output", "input")
        _ = try await harness.perform("audio", "audio.set-volume", [.number(0.6)])
        #expect(harness.value("audio", "volume") == .number(0.6))
        _ = try await harness.perform("audio", "audio.change-volume", [.number(0.7)])
        #expect(harness.value("audio", "volume") == .number(1))
        _ = try await harness.perform("audio", "audio.change-volume", [.number(-2)])
        #expect(harness.value("audio", "volume") == .number(0))
        _ = try await harness.perform("audio", "audio.toggle-mute")
        #expect(harness.value("audio", "muted") == .bool(true))
        _ = try await harness.perform("audio", "audio.set-muted", [.bool(false)])
        #expect(harness.value("audio", "muted") == .bool(false))
        _ = try await harness.perform("audio", "audio.select-output", [.string("airpods")])
        #expect(harness.value("audio", "output.id") == .string("airpods"))
        _ = try await harness.perform("audio", "audio.set-input-volume", [.number(0.25)])
        #expect(harness.value("audio", "input.volume") == .number(0.25))
        _ = try await harness.perform("audio", "audio.set-input-muted", [.bool(true)])
        #expect(harness.value("audio", "input.muted") == .bool(true))
        _ = try await harness.perform("audio", "audio.select-input", [.string("mic")])
        await #expect(throws: ProviderActionError.self) {
            try await harness.perform("audio", "audio.select-output", [.string("nope")])
        }
        await #expect(throws: ProviderActionError.self) {
            try await harness.perform("audio", "audio.set-volume", [.string("laut")])
        }
        source.volumeSettable = false
        _ = try await harness.perform("audio", "audio.set-volume", [.number(0.5)])
        #expect(harness.warnings.count == 1)
    }

    @Test("Ereignisse: Lautstärke bei jeder Änderung, Geräte erst nach bekanntem Gerät")
    func events() {
        let (harness, source) = make()
        let awake = harness.keepAwake("audio")
        #expect(harness.events.isEmpty)
        source.change { $0.volume = 0.5 }
        #expect(harness.eventNames() == ["audio.volume-changed"])
        #expect(harness.events[0].fields["volume"] == .number(0.5))
        #expect(harness.events[0].fields["muted"] == .bool(false))
        source.change { $0.muted = true }
        source.change { $0.output = FakeAudioSource.headphones }
        #expect(harness.eventNames() == ["audio.volume-changed", "audio.volume-changed", "audio.output-changed"])
        #expect(harness.events[2].fields["name"] == .string("AirPods Pro"))
        source.change { $0.input = AudioDevice(id: "usb", name: "USB Mic") }
        #expect(harness.eventNames().last == "audio.input-changed")
        harness.releaseAwake(awake)
        #expect(!source.observing)
    }

    @Test("Start nur bei Nachfrage, push ohne Polling")
    func startsOnDemandWithoutPolling() {
        let (harness, source) = make()
        #expect(source.reads == 0)
        let token = harness.demand("audio", "volume")
        #expect(source.observing)
        let reads = source.reads
        harness.advance(600)
        #expect(source.reads == reads)
        harness.release(token)
        #expect(!source.observing)
    }
}
