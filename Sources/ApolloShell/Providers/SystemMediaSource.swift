import AppKit
import ApolloProviders
import ApolloShellCore
import os

@MainActor
final class SystemMediaSource: MediaSource {
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

    private static let perl = "/usr/bin/perl"

    private let log = Logger(category: "media")
    private var stream: Process?
    private var names: [String: String] = [:]

    var adapterAvailable: Bool { Self.adapter != nil }

    var now: Date { Date() }

    func startStream(_ handler: @escaping @MainActor (MediaStreamEvent) -> Void) -> Bool {
        guard let adapter = Self.adapter else { return false }
        stopStream()
        let reader = MediaLineReader()
        let process = Subprocess.stream(
            Self.perl, [adapter.script.path, adapter.framework.path] + MediaAdapter.streamArguments,
            onData: { chunk in
                let messages = reader.messages(from: chunk)
                guard !messages.isEmpty else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { handler(.messages(messages)) }
                }
            },
            onExit: { [weak self] status in
                self?.stream = nil
                handler(.exited(status))
            }
        )
        stream = process
        return process != nil
    }

    func stopStream() {
        stream?.terminate()
        stream = nil
    }

    func send(_ command: MediaCommand) {
        run(command.arguments, label: "send \(command.rawValue)")
    }

    func seek(microseconds: Int) {
        run(["seek", String(microseconds)], label: "seek")
    }

    func appName(_ bundleIdentifier: String) -> String? {
        if let cached = names[bundleIdentifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        names[bundleIdentifier] = name
        return name
    }

    func artworkAspect(_ data: Data) -> Double? {
        guard let image = NSImage(data: data), image.size.height > 0 else { return nil }
        return Double(image.size.width / image.size.height)
    }

    func openApp(_ bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func run(_ arguments: [String], label: String) {
        guard let adapter = Self.adapter else { return }
        Subprocess.launch(Self.perl, [adapter.script.path, adapter.framework.path] + arguments) { [log] status in
            if status != 0 {
                log.error("Befehl \(label, privacy: .public) fehlgeschlagen, Status \(status)")
            }
        }
    }
}

private final class MediaLineReader: Sendable {
    private let buffer = OSAllocatedUnfairLock(initialState: MediaLineBuffer())

    func messages(from chunk: Data) -> [MediaStreamMessage] {
        let lines = buffer.withLock { $0.append(chunk) }
        return lines.compactMap(MediaStreamMessage.parse)
    }
}
