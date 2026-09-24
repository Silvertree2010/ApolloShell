import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class AudioProvider: BaseProvider {
    private let source: any AudioSource
    private var last: AudioSnapshot?
    private var outputTracker = ToastDeviceTracker()
    private var inputTracker = ToastDeviceTracker()

    public init(source: any AudioSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("audio"), clock: clock)
    }

    override func didStart() {
        last = nil
        outputTracker = ToastDeviceTracker()
        inputTracker = ToastDeviceTracker()
        source.observeChanges { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    override func didStop() {
        source.stopObserving()
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        let ok: Bool
        switch arguments.action {
        case "audio.set-volume":
            ok = source.setVolume(Self.clamp(try arguments.number(0)))
        case "audio.change-volume":
            let current = source.read().volume ?? 0
            ok = source.setVolume(Self.clamp(current + (try arguments.number(0))))
        case "audio.set-muted":
            ok = source.setMuted(try arguments.bool(0))
        case "audio.toggle-mute":
            ok = source.setMuted(!source.read().muted)
        case "audio.select-output":
            let id = try arguments.string(0)
            guard source.read().outputs.contains(where: { $0.id == id }) else {
                throw ProviderActionError.invalidArgument(action: arguments.action, message: "unknown output device \"\(id)\"")
            }
            ok = source.selectOutput(id)
        case "audio.select-input":
            let id = try arguments.string(0)
            guard source.read().inputs.contains(where: { $0.id == id }) else {
                throw ProviderActionError.invalidArgument(action: arguments.action, message: "unknown input device \"\(id)\"")
            }
            ok = source.selectInput(id)
        case "audio.set-input-volume":
            ok = source.setInputVolume(Self.clamp(try arguments.number(0)))
        case "audio.set-input-muted":
            ok = source.setInputMuted(try arguments.bool(0))
        default:
            throw ProviderActionError.unknownAction(arguments.action)
        }
        if !ok {
            warn("\(arguments.action): the current audio device does not allow this")
        }
        refresh()
        return .null
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func refresh() {
        guard isRunning else { return }
        let snapshot = source.read()
        publish("volume", ProviderValue.number(snapshot.volume))
        publish("muted", .bool(snapshot.muted))
        publish("output", snapshot.output.map { .record(Record([("id", .string($0.id)), ("name", .string($0.name))])) } ?? .null)
        publish("input", snapshot.input.map {
            .record(Record([
                ("id", .string($0.id)), ("name", .string($0.name)),
                ("volume", ProviderValue.number(snapshot.inputVolume)), ("muted", ProviderValue.bool(snapshot.inputMuted)),
            ]))
        } ?? .null)
        publish("outputs", Self.list(snapshot.outputs, active: snapshot.output?.id))
        publish("inputs", Self.list(snapshot.inputs, active: snapshot.input?.id))
        publish("symbol", .string(VolumeGlyphs.symbol(volume: Float(snapshot.volume ?? 0), muted: snapshot.muted)))
        emitChanges(snapshot)
        last = snapshot
    }

    private func emitChanges(_ snapshot: AudioSnapshot) {
        if let last, last.volume != snapshot.volume || last.muted != snapshot.muted {
            emit("audio.volume-changed", Record([("volume", ProviderValue.number(snapshot.volume)), ("muted", .bool(snapshot.muted))]))
        }
        if let output = snapshot.output, outputTracker.update(name: output.name) {
            emit("audio.output-changed", Record([("name", ProviderValue.string(outputTracker.name))]))
        }
        if let input = snapshot.input, inputTracker.update(name: input.name) {
            emit("audio.input-changed", Record([("name", ProviderValue.string(inputTracker.name))]))
        }
    }

    private static func list(_ devices: [AudioDevice], active: String?) -> Value {
        .list(devices.map { device in
            .record(Record([("id", .string(device.id)), ("name", .string(device.name)), ("active", .bool(device.id == active))]))
        })
    }
}
