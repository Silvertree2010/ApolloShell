@testable import ApolloProviders

@MainActor
final class FakeAudioSource: AudioSource {
    static let speakers = AudioDevice(id: "builtin", name: "MacBook Pro Speakers")
    static let headphones = AudioDevice(id: "airpods", name: "AirPods Pro")
    static let microphone = AudioDevice(id: "mic", name: "MacBook Pro Microphone")

    var state = AudioSnapshot(
        volume: 0.35, muted: false, output: speakers, input: microphone, inputVolume: 0.8, inputMuted: false,
        outputs: [speakers, headphones], inputs: [microphone]
    )
    var reads = 0
    var observing = false
    var volumeSettable = true
    var calls: [String] = []
    private var handler: (@MainActor () -> Void)?

    func read() -> AudioSnapshot {
        reads += 1
        return state
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        observing = true
        self.handler = handler
    }

    func stopObserving() {
        observing = false
        handler = nil
    }

    func change(_ update: (inout AudioSnapshot) -> Void) {
        update(&state)
        handler?()
    }

    func setVolume(_ volume: Double) -> Bool {
        calls.append("volume \(volume)")
        guard volumeSettable else { return false }
        change { $0.volume = volume; if volume > 0 { $0.muted = false } }
        return true
    }

    func setMuted(_ muted: Bool) -> Bool {
        calls.append("muted \(muted)")
        change { $0.muted = muted }
        return true
    }

    func selectOutput(_ id: String) -> Bool {
        guard let device = state.outputs.first(where: { $0.id == id }) else { return false }
        change { $0.output = device }
        return true
    }

    func selectInput(_ id: String) -> Bool {
        guard let device = state.inputs.first(where: { $0.id == id }) else { return false }
        change { $0.input = device }
        return true
    }

    func setInputVolume(_ volume: Double) -> Bool {
        change { $0.inputVolume = volume }
        return true
    }

    func setInputMuted(_ muted: Bool) -> Bool {
        change { $0.inputMuted = muted }
        return true
    }
}
