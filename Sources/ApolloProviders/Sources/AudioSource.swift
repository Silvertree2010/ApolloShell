import Foundation

public struct AudioDevice: Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct AudioSnapshot: Equatable, Sendable {
    public var volume: Double?
    public var muted: Bool
    public var output: AudioDevice?
    public var input: AudioDevice?
    public var inputVolume: Double?
    public var inputMuted: Bool?
    public var outputs: [AudioDevice]
    public var inputs: [AudioDevice]

    public init(
        volume: Double?,
        muted: Bool,
        output: AudioDevice?,
        input: AudioDevice? = nil,
        inputVolume: Double? = nil,
        inputMuted: Bool? = nil,
        outputs: [AudioDevice] = [],
        inputs: [AudioDevice] = []
    ) {
        self.volume = volume
        self.muted = muted
        self.output = output
        self.input = input
        self.inputVolume = inputVolume
        self.inputMuted = inputMuted
        self.outputs = outputs
        self.inputs = inputs
    }
}

@MainActor
public protocol AudioSource: AnyObject {
    func read() -> AudioSnapshot
    func observeChanges(_ handler: @escaping @MainActor () -> Void)
    func stopObserving()
    func setVolume(_ volume: Double) -> Bool
    func setMuted(_ muted: Bool) -> Bool
    func selectOutput(_ id: String) -> Bool
    func selectInput(_ id: String) -> Bool
    func setInputVolume(_ volume: Double) -> Bool
    func setInputMuted(_ muted: Bool) -> Bool
}
