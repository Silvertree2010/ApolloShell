import AppKit
import CoreImage
import ApolloShellCore
import Observation
import os

/// The app that is playing right now: name and symbol for the display.
struct MediaSource: Equatable {
    let name: String
    let icon: NSImage?
}

/// "Now Playing" for the media card and the media tab.
///
/// MediaRemote has delivered nothing to apps without an Apple entitlement
/// since macOS 15.4. The mediaremote-adapter (extras/mediaremote-adapter)
/// gets around that without a dialog: it loads its framework into the
/// Apple-signed /usr/bin/perl, which is still allowed to, and streams JSON
/// lines (the logic sits in ApolloShellCore/MediaNowPlaying.swift).
///
/// The stream only runs while the dashboard is open: `start` on opening,
/// `stop` on closing and when the app ends. If it dies along the way, it
/// starts again with growing pauses (`MediaRestart`). Control commands go out
/// as short calls of their own; the display follows from the stream
/// afterwards, not from a guess.
@MainActor
@Observable
final class MediaModel {
    private(set) var nowPlaying: MediaNowPlaying?
    private(set) var artwork: NSImage?
    /// The cover small and blurred, as the background of the tab.
    private(set) var ambient: NSImage?
    /// Counts cover changes - the view cross-fades with it.
    private(set) var artworkID = 0
    private(set) var source: MediaSource?
    /// The adapter is missing from the bundle (`swift run`, say) or has died
    /// several times in a row.
    private(set) var isUnavailable = false

    /// A fixed clock for image samples; `nil` = the real time.
    @ObservationIgnored let fixedNow: Date?
    /// `false` for image samples: then the model starts no process.
    @ObservationIgnored private let live: Bool

    @ObservationIgnored private var state = MediaStreamState()
    @ObservationIgnored private var shownArtworkRevision = 0
    @ObservationIgnored private var stream: Process?
    @ObservationIgnored private var streamStartedAt = Date()
    /// Every stream process gets a number; late lines or a late end of an old
    /// process are recognised by it and thrown away.
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

    /// A model with fixed content that starts nothing - for image samples.
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

    // MARK: - The adapter in the bundle

    private struct AdapterFiles {
        let script: URL
        let framework: URL
    }

    /// build.sh puts the framework into Contents/Frameworks (nested code
    /// belongs there for codesign) and the script into Resources.
    private static let adapter: AdapterFiles? = {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let framework = Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: framework.path)
        else { return nil }
        return AdapterFiles(script: script, framework: framework)
    }()

    /// The Apple-signed perl is the heart of the trick: only it still gets an
    /// answer out of MediaRemote. Never a perl out of nix or Homebrew.
    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    // MARK: - Stream

    func start() {
        guard live else { return }
        wantsStream = true
        // Every opening is a new attempt, even after "gives up".
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
        // SIGTERM: the adapter catches it and ends its run loop cleanly
        // (measured: exit status 0).
        stream?.terminate()
        stream = nil
        // Whatever still comes from the old process no longer counts. The last
        // state stays standing until the next stream replaces it.
        generation += 1
    }

    private func launchStream() {
        guard let adapter = Self.adapter else {
            isUnavailable = true
            if !loggedMissingAdapter {
                loggedMissingAdapter = true
                log.error("mediaremote-adapter missing from the bundle - build.sh builds it in")
            }
            return
        }
        generation += 1
        let generation = generation
        // Diffs only hold inside one process.
        state = MediaStreamState()

        // According to the README, stderr holds non-fatal messages;
        // `Subprocess` throws them away, and unread the pipe would fill up.
        let reader = MediaLineReader()
        let process = Subprocess.stream(
            Self.perl.path, [adapter.script.path, adapter.framework.path] + MediaAdapter.streamArguments,
            onData: { [weak self] chunk in
                // Decode the JSON here, off the main thread: one line with a
                // cover is a few hundred KB.
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
            // On the start the adapter writes an empty line first, before its
            // queries are back (measured: `{}` and milliseconds later the
            // data), and between two tracks it can be empty for a moment.
            // Showing "Nothing is playing" right away would flicker on every
            // opening - so wait briefly to see whether something else comes.
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

    /// Carry the state over to the observed properties - only what changes, so
    /// that SwiftUI does not redraw everything on every diff.
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
            log.error("Adapter gives up: \(self.failures) early aborts, last status \(status)")
            // Old data would never be updated again - better honestly empty.
            state = MediaStreamState()
            publish()
            isUnavailable = true
            return
        }
        log.notice("Adapter ended (status \(status)), next attempt in \(delay, format: .fixed(precision: 0)) s")
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.restartTask = nil
            if self.wantsStream { self.launchStream() }
        }
    }

    // MARK: - Controlling

    /// A short call of its own (`send N`), the stream goes on running.
    func send(_ command: MediaCommand) {
        guard live, let adapter = Self.adapter else { return }
        Subprocess.launch(Self.perl.path, [adapter.script.path, adapter.framework.path] + command.arguments) {
            [weak self] status in self?.commandEnded(status: status, command: command)
        }
    }

    private func commandEnded(status: Int32, command: MediaCommand) {
        if status != 0 {
            log.error("Command \(command.rawValue) failed, status \(status)")
        }
    }

    // MARK: - Source

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

/// The background out of the cover, worked out once per cover: scaled down
/// and blurred. A SwiftUI `.blur` with a large radius would run along on
/// every redraw of the tab.
@MainActor
enum MediaBlur {
    private static let context = CIContext()

    static func ambient(from image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        let longest = max(input.extent.width, input.extent.height)
        guard longest > 0 else { return nil }
        // 96 px is enough for a soft background and keeps the blur cheap.
        let scale = 96 / longest
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        // Continue the edge, otherwise the blur pulls transparency in from outside.
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 8).cropped(to: small.extent)
        guard let output = context.createCGImage(blurred, from: small.extent) else { return nil }
        return NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
    }
}

/// A line buffer for the read handler of the pipe. The handler runs on a
/// background queue; the lock makes the access safe on purpose, instead of
/// relying on the calls arriving one after another, which is not
/// guaranteed.
private final class MediaLineReader: Sendable {
    private let buffer = OSAllocatedUnfairLock(initialState: MediaLineBuffer())

    func messages(from chunk: Data) -> [MediaStreamMessage] {
        let lines = buffer.withLock { $0.append(chunk) }
        return lines.compactMap(MediaStreamMessage.parse)
    }
}
