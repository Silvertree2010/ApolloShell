import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class MediaProvider: BaseProvider {
    static let elapsedInterval: Double = 0.5
    static let emptyDelay: Double = 0.6

    private let source: any MediaSource
    private var state = MediaStreamState()
    private var shown: MediaNowPlaying?
    private var generation = 0
    private var failures = 0
    private var startedAt = Date()
    private var trackIdentity: [String?]?
    private var artworkID: String?
    private var loggedMissingAdapter = false
    private var awaitingBaseline = true

    public init(source: any MediaSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("media"), clock: clock)
    }

    public func artworkData(_ id: String) -> Data? {
        id == artworkID ? state.artwork : nil
    }

    override func didStart() {
        failures = 0
        trackIdentity = nil
        publish("unavailable", .null)
        launch()
    }

    override func didChangeDemand() {
        updateElapsedTimer()
    }

    override func didStop() {
        generation += 1
        source.stopStream()
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        let action = arguments.action
        guard schema.actions.contains(where: { $0.name == action }) else {
            throw ProviderActionError.unknownAction(action)
        }
        guard source.adapterAvailable else {
            warn("\(action): the media adapter is missing")
            return .null
        }
        switch action {
        case "media.play-pause": source.send(.togglePlayPause)
        case "media.next": source.send(.nextTrack)
        case "media.previous": source.send(.previousTrack)
        case "media.seek":
            let seconds = try arguments.number(0)
            source.seek(microseconds: Int((max(seconds, 0) * 1_000_000).rounded()))
        default:
            guard let app = shown?.sourceBundleIdentifier else {
                note("\(action): nothing is playing")
                return .null
            }
            source.openApp(app)
        }
        return .null
    }

    private func launch() {
        guard isRunning else { return }
        guard source.adapterAvailable else {
            if !loggedMissingAdapter {
                loggedMissingAdapter = true
                note("mediaremote-adapter is missing from the bundle")
            }
            publish("available", .bool(false))
            publish("unavailable", .string("no-adapter"))
            publishNowPlaying()
            return
        }
        generation += 1
        let generation = generation
        state = MediaStreamState()
        awaitingBaseline = true
        startedAt = source.now
        let started = source.startStream { [weak self] event in
            guard let self, generation == self.generation else { return }
            self.receive(event)
        }
        guard started else {
            ended()
            return
        }
        publish("available", .bool(true))
        publish("unavailable", .null)
        publishNowPlaying()
    }

    private func receive(_ event: MediaStreamEvent) {
        switch event {
        case .messages(let messages):
            for message in messages { state.apply(message) }
            defer { awaitingBaseline = false }
            if state.nowPlaying == nil && shown != nil {
                guard !timers.isActive("empty") else { return }
                timers.once("empty", after: Self.emptyDelay) { [weak self] in
                    self?.publishNowPlaying()
                }
                return
            }
            timers.cancel("empty")
            publishNowPlaying()
        case .exited:
            ended()
        }
    }

    private func ended() {
        guard isRunning else { return }
        generation += 1
        failures = MediaRestart.failures(previous: failures, runtime: source.now.timeIntervalSince(startedAt))
        guard let delay = MediaRestart.delay(afterFailures: failures) else {
            note("media adapter gave up after \(failures) early exits")
            state = MediaStreamState()
            publishNowPlaying()
            publish("available", .bool(false))
            publish("unavailable", .string("adapter-crashed"))
            return
        }
        timers.once("restart", after: delay) { [weak self] in
            self?.launch()
        }
    }

    private func publishNowPlaying() {
        guard isRunning else { return }
        let playing = state.nowPlaying
        shown = playing
        let now = source.now
        publish("playing", .bool(playing?.isPlaying ?? false))
        publish("title", ProviderValue.string(playing?.title))
        publish("artist", ProviderValue.string(playing?.artist))
        publish("album", ProviderValue.string(playing?.album))
        if let current = playing, let data = state.artwork {
            let id = "artwork-\(generation)-\(state.artworkRevision)"
            artworkID = id
            publish("artwork", .image(ImageRef(source: "media", id: id)))
            publish("kind", .string(MediaKind.detect(current, artworkAspect: source.artworkAspect(data)).rawValue))
        } else {
            artworkID = nil
            publish("artwork", .null)
            publish("kind", .string(playing.map { MediaKind.detect($0, artworkAspect: nil).rawValue } ?? MediaKind.music.rawValue))
        }
        publish("duration", ProviderValue.number(playing?.duration))
        publishElapsed(playing, now: now)
        let app = playing?.sourceBundleIdentifier
        publish("app", ProviderValue.string(app))
        publish("app-name", ProviderValue.string(app.map { source.appName($0) ?? $0 }))
        publish("app-icon", app.map { .image(ImageRef(source: "app-icon", id: $0)) } ?? .null)
        let identity = [playing?.title, playing?.artist, playing?.album]
        if awaitingBaseline {
            trackIdentity = identity
        } else if let trackIdentity, trackIdentity != identity, playing != nil {
            emit("media.track-changed")
        }
        if playing != nil || trackIdentity == nil { trackIdentity = identity }
        updateElapsedTimer()
    }

    private func publishElapsed(_ playing: MediaNowPlaying?, now: Date) {
        let elapsed = playing?.elapsed(at: now)
        publish("elapsed", ProviderValue.number(elapsed))
        publish("progress", playing.flatMap { $0.duration != nil && elapsed != nil ? .number($0.progress(at: now)) : nil } ?? .null)
    }

    private func updateElapsedTimer() {
        let active = isRunning && (shown?.isPlaying ?? false) && demand.wantsAny(["elapsed", "progress"])
        timers.set("elapsed", every: Self.elapsedInterval, active: active) { [weak self] in
            guard let self else { return }
            self.publishElapsed(self.shown, now: self.source.now)
        }
    }
}
