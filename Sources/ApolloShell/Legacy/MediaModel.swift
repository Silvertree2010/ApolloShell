import AppKit
import CoreImage
import ApolloShellCore
import Observation
import os

struct MediaSource: Equatable {
    let name: String
    let icon: NSImage?
}

@MainActor
@Observable
final class MediaModel {
    private(set) var nowPlaying: MediaNowPlaying?
    private(set) var artwork: NSImage?
    private(set) var ambient: NSImage?
    private(set) var artworkID = 0
    private(set) var source: MediaSource?
    private(set) var isUnavailable = false

    @ObservationIgnored let fixedNow: Date?
    @ObservationIgnored private let live: Bool

    @ObservationIgnored private var state = MediaStreamState()
    @ObservationIgnored private var shownArtworkRevision = 0
    @ObservationIgnored private var stream: Process?
    @ObservationIgnored private var streamStartedAt = Date()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var wantsStream = false
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var emptyTask: Task<Void, Never>?
    @ObservationIgnored private var sources: [String: MediaSource] = [:]
    @ObservationIgnored private var loggedMissingAdapter = false
    @ObservationIgnored private let log = Logger(category: "media")

    init() {
        live = true
        fixedNow = nil
    }

    private init(fixedNow: Date) {
        live = false
        self.fixedNow = fixedNow
    }

    static func preview(
        nowPlaying: MediaNowPlaying?,
        artwork: NSImage? = nil,
        source: MediaSource? = nil,
        isUnavailable: Bool = false,
        now: Date
    ) -> MediaModel {
        let model = MediaModel(fixedNow: now)
        model.nowPlaying = nowPlaying
        model.artwork = artwork
        model.ambient = artwork.flatMap(MediaBlur.ambient(from:))
        model.source = source
        model.isUnavailable = isUnavailable
        return model
    }

    private struct AdapterFiles {
        let script: URL
        let framework: URL
    }

    private static let adapter: AdapterFiles? = {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let framework = Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: framework.path)
        else { return nil }
        return AdapterFiles(script: script, framework: framework)
    }()

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    func start() {
        guard live else { return }
        wantsStream = true
        failures = 0
        isUnavailable = false
        if stream == nil && restartTask == nil { launchStream() }
    }

    func stop() {
        guard live else { return }
        wantsStream = false
        restartTask?.cancel()
        restartTask = nil
        emptyTask?.cancel()
        emptyTask = nil
        stream?.terminate()
        stream = nil
        generation += 1
    }

    private func launchStream() {
        guard let adapter = Self.adapter else {
            isUnavailable = true
            if !loggedMissingAdapter {
                loggedMissingAdapter = true
                log.error("mediaremote-adapter fehlt im Bundle - build.sh baut ihn mit")
            }
            return
        }
        generation += 1
        let generation = generation
        state = MediaStreamState()

        let reader = MediaLineReader()
        let process = Subprocess.stream(
            Self.perl.path, [adapter.script.path, adapter.framework.path] + MediaAdapter.streamArguments,
            onData: { [weak self] chunk in
                let messages = reader.messages(from: chunk)
                guard !messages.isEmpty else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.receive(messages, generation: generation) }
                }
            },
            onExit: { [weak self] status in self?.streamEnded(status: status, generation: generation) }
        )
        guard let process else {
            streamEnded(status: -1, generation: generation)
            return
        }
        stream = process
        streamStartedAt = Date()
    }

    private func receive(_ messages: [MediaStreamMessage], generation: Int) {
        guard generation == self.generation else { return }
        for message in messages { state.apply(message) }
        if state.nowPlaying == nil && nowPlaying != nil {
            guard emptyTask == nil else { return }
            emptyTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let self else { return }
                self.emptyTask = nil
                self.publish()
            }
            return
        }
        emptyTask?.cancel()
        emptyTask = nil
        publish()
    }

    private func publish() {
        let next = state.nowPlaying
        if next != nowPlaying { nowPlaying = next }
        if state.artworkRevision != shownArtworkRevision {
            shownArtworkRevision = state.artworkRevision
            artwork = state.artwork.flatMap(NSImage.init(data:))
            ambient = artwork.flatMap(MediaBlur.ambient(from:))
            artworkID += 1
        }
        let nextSource = next?.sourceBundleIdentifier.map(source(for:))
        if nextSource != source { source = nextSource }
    }

    private func streamEnded(status: Int32, generation: Int) {
        guard generation == self.generation else { return }
        stream = nil
        guard wantsStream else { return }
        failures = MediaRestart.failures(previous: failures, runtime: Date().timeIntervalSince(streamStartedAt))
        guard let delay = MediaRestart.delay(afterFailures: failures) else {
            log.error("Adapter gibt auf: \(self.failures) fruehe Abbrueche, zuletzt Status \(status)")
            state = MediaStreamState()
            publish()
            isUnavailable = true
            return
        }
        log.notice("Adapter beendet (Status \(status)), neuer Versuch in \(delay, format: .fixed(precision: 0)) s")
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.restartTask = nil
            if self.wantsStream { self.launchStream() }
        }
    }

    func send(_ command: MediaCommand) {
        guard live, let adapter = Self.adapter else { return }
        Subprocess.launch(Self.perl.path, [adapter.script.path, adapter.framework.path] + command.arguments) {
            [weak self] status in self?.commandEnded(status: status, command: command)
        }
    }

    private func commandEnded(status: Int32, command: MediaCommand) {
        if status != 0 {
            log.error("Befehl \(command.rawValue) fehlgeschlagen, Status \(status)")
        }
    }

    private func source(for bundleIdentifier: String) -> MediaSource {
        if let cached = sources[bundleIdentifier] { return cached }
        let source: MediaSource
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            source = MediaSource(name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
        } else {
            source = MediaSource(name: bundleIdentifier, icon: nil)
        }
        sources[bundleIdentifier] = source
        return source
    }
}

@MainActor
enum MediaBlur {
    private static let context = CIContext()

    static func ambient(from image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        let longest = max(input.extent.width, input.extent.height)
        guard longest > 0 else { return nil }
        let scale = 96 / longest
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 8).cropped(to: small.extent)
        guard let output = context.createCGImage(blurred, from: small.extent) else { return nil }
        return NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
    }
}

private final class MediaLineReader: Sendable {
    private let buffer = OSAllocatedUnfairLock(initialState: MediaLineBuffer())

    func messages(from chunk: Data) -> [MediaStreamMessage] {
        let lines = buffer.withLock { $0.append(chunk) }
        return lines.compactMap(MediaStreamMessage.parse)
    }
}
