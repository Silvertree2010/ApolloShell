import AppKit
import CoreImage
import ApolloShellCore
import Observation
import os

/// App, die gerade abspielt: Name und Symbol fuer die Anzeige.
struct MediaSource: Equatable {
    let name: String
    let icon: NSImage?
}

/// "Now Playing" fuer die Medien-Karte und den Reiter Medien.
///
/// MediaRemote liefert Apps ohne Apple-Berechtigung seit macOS 15.4 nichts
/// mehr. Der mediaremote-adapter (extras/mediaremote-adapter) umgeht das
/// ohne Dialog: er laedt sein Framework in das Apple-signierte
/// /usr/bin/perl, das noch darf, und streamt JSON-Zeilen (Logik in
/// ApolloShellCore/MediaNowPlaying.swift).
///
/// Der Stream laeuft nur, solange das Dashboard offen ist: `start` beim
/// Oeffnen, `stop` beim Schliessen und beim Beenden der App. Stirbt er
/// unterwegs, startet er mit wachsenden Pausen neu (`MediaRestart`).
/// Steuerbefehle gehen als eigene kurze Aufrufe raus; die Anzeige folgt
/// danach aus dem Stream, nicht aus einer Vermutung.
@MainActor
@Observable
final class MediaModel {
    private(set) var nowPlaying: MediaNowPlaying?
    private(set) var artwork: NSImage?
    /// Das Cover klein und weichgezeichnet, als Hintergrund des Reiters.
    private(set) var ambient: NSImage?
    /// Zaehlt Coverwechsel - die Ansicht blendet damit ueber.
    private(set) var artworkID = 0
    private(set) var source: MediaSource?
    /// Adapter fehlt im Bundle (z. B. `swift run`) oder ist mehrmals
    /// hintereinander gestorben.
    private(set) var isUnavailable = false

    /// Feste Uhr fuer Bildproben; `nil` = echte Zeit.
    @ObservationIgnored let fixedNow: Date?
    /// `false` fuer Bildproben: dann startet das Modell keinen Prozess.
    @ObservationIgnored private let live: Bool

    @ObservationIgnored private var state = MediaStreamState()
    @ObservationIgnored private var shownArtworkRevision = 0
    @ObservationIgnored private var stream: Process?
    @ObservationIgnored private var streamStartedAt = Date()
    /// Jeder Stream-Prozess bekommt eine Nummer; spaete Zeilen oder ein
    /// spaetes Ende eines alten Prozesses werden daran erkannt und verworfen.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var wantsStream = false
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var emptyTask: Task<Void, Never>?
    /// Laufende Steuerbefehle, bis sie fertig sind.
    @ObservationIgnored private var commands: [ObjectIdentifier: Process] = [:]
    @ObservationIgnored private var sources: [String: MediaSource] = [:]
    @ObservationIgnored private var loggedMissingAdapter = false
    @ObservationIgnored private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "media")

    init() {
        live = true
        fixedNow = nil
    }

    private init(fixedNow: Date) {
        live = false
        self.fixedNow = fixedNow
    }

    /// Modell mit festem Inhalt, das nichts startet - fuer Bildproben.
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

    // MARK: - Adapter im Bundle

    private struct AdapterFiles {
        let script: URL
        let framework: URL
    }

    /// build.sh legt das Framework nach Contents/Frameworks (verschachtelter
    /// Code gehoert fuer codesign dorthin) und das Skript nach Resources.
    private static let adapter: AdapterFiles? = {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let framework = Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: framework.path)
        else { return nil }
        return AdapterFiles(script: script, framework: framework)
    }()

    /// Das Apple-signierte perl ist der Kern des Tricks: nur ihm gibt
    /// MediaRemote noch Auskunft. Nie ein perl aus nix oder Homebrew.
    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    // MARK: - Stream

    func start() {
        guard live else { return }
        wantsStream = true
        // Jedes Oeffnen ist ein neuer Anlauf, auch nach "gibt auf".
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
        // SIGTERM: der Adapter faengt es ab und beendet seine Run-Loop sauber
        // (gemessen: Exit-Status 0).
        stream?.terminate()
        stream = nil
        // Was jetzt noch vom alten Prozess kommt, gilt nicht mehr. Der
        // letzte Stand bleibt stehen, bis der naechste Stream ihn ersetzt.
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
        // Diffs gelten nur innerhalb eines Prozesses.
        state = MediaStreamState()

        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [adapter.script.path, adapter.framework.path] + MediaAdapter.streamArguments
        process.standardInput = FileHandle.nullDevice
        // stderr sind laut README nicht-fatale Meldungen. Ungelesen in eine
        // Pipe koennten sie den Prozess blockieren, sobald sie voll ist.
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        let reader = MediaLineReader()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            // JSON hier dekodieren, abseits des Hauptthreads: eine Zeile mit
            // Cover ist einige hundert KB gross.
            let messages = reader.messages(from: chunk)
            guard !messages.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(messages, generation: generation) }
            }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.streamEnded(status: status, generation: generation) }
            }
        }

        do {
            try process.run()
            stream = process
            streamStartedAt = Date()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            log.error("Adapter nicht gestartet: \(error.localizedDescription, privacy: .public)")
            streamEnded(status: -1, generation: generation)
        }
    }

    private func receive(_ messages: [MediaStreamMessage], generation: Int) {
        guard generation == self.generation else { return }
        for message in messages { state.apply(message) }
        if state.nowPlaying == nil && nowPlaying != nil {
            // Beim Start schreibt der Adapter zuerst eine leere Zeile, bevor
            // seine Abfragen zurueck sind (gemessen: `{}` und Millisekunden
            // spaeter die Daten), und zwischen zwei Titeln kann es kurz leer
            // sein. Sofort "Nichts laeuft" zu zeigen, wuerde bei jedem Oeffnen
            // flackern - also kurz abwarten, ob noch etwas kommt.
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

    /// Zustand auf die beobachteten Eigenschaften uebertragen - nur was sich
    /// aendert, damit SwiftUI nicht bei jedem Diff alles neu zeichnet.
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
            // Alte Daten wuerden jetzt nie mehr aktualisiert - lieber ehrlich leer.
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

    // MARK: - Steuern

    /// Eigener kurzer Aufruf (`send N`), der Stream laeuft weiter.
    func send(_ command: MediaCommand) {
        guard live, let adapter = Self.adapter else { return }
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [adapter.script.path, adapter.framework.path] + command.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let id = ObjectIdentifier(process)
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.commandEnded(id: id, status: status, command: command) }
            }
        }
        do {
            try process.run()
            commands[id] = process
        } catch {
            log.error("Befehl \(command.rawValue) nicht gestartet: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func commandEnded(id: ObjectIdentifier, status: Int32, command: MediaCommand) {
        commands[id] = nil
        if status != 0 {
            log.error("Befehl \(command.rawValue) fehlgeschlagen, Status \(status)")
        }
    }

    // MARK: - Quelle

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

/// Hintergrund aus dem Cover, einmal pro Cover gerechnet: klein skaliert
/// und weichgezeichnet. Ein SwiftUI-`.blur` mit grossem Radius wuerde bei
/// jedem Neuzeichnen des Reiters mitlaufen.
@MainActor
enum MediaBlur {
    private static let context = CIContext()

    static func ambient(from image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        let longest = max(input.extent.width, input.extent.height)
        guard longest > 0 else { return nil }
        // 96 px reichen fuer einen weichen Hintergrund und halten den Blur billig.
        let scale = 96 / longest
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        // Rand fortsetzen, sonst zieht der Blur von aussen Transparenz herein.
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 8).cropped(to: small.extent)
        guard let output = context.createCGImage(blurred, from: small.extent) else { return nil }
        return NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
    }
}

/// Zeilenpuffer fuer den Lese-Handler der Pipe. Der Handler laeuft auf
/// einer Hintergrund-Queue; die Sperre macht den Zugriff ausdruecklich
/// sicher, statt sich darauf zu verlassen, dass die Aufrufe nacheinander
/// kommen.
private final class MediaLineReader: Sendable {
    private let buffer = OSAllocatedUnfairLock(initialState: MediaLineBuffer())

    func messages(from chunk: Data) -> [MediaStreamMessage] {
        let lines = buffer.withLock { $0.append(chunk) }
        return lines.compactMap(MediaStreamMessage.parse)
    }
}
