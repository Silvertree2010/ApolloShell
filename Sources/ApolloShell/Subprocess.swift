import ApolloShellCore
import Foundation
import os

/// The tools of the system (pmset, osascript, shortcuts ...) as processes of
/// their own - in one place instead of by hand in every file.
///
/// What nobody reads goes to /dev/null: an unread pipe would fill up and stop
/// the process.
enum Subprocess {
    struct Result: Sendable {
        let status: Int32
        let output: Data
        var text: String { String(decoding: output, as: UTF8.self) }
    }

    private static let log = Logger(category: "subprocess")

    /// The running processes out of `launch` and `stream`, until they end - so
    /// that nobody else has to hold on to them.
    @MainActor private static var alive: [ObjectIdentifier: Process] = [:]

    /// Start, do not wait. `onExit` gets the return value on the main thread.
    /// `nil`: it could not be started (which stands in the log), and then no
    /// `onExit` comes either.
    @MainActor
    @discardableResult
    static func launch(_ path: String, _ arguments: [String] = [],
                       onExit: (@MainActor (Int32) -> Void)? = nil) -> Process? {
        let process = make(path, arguments)
        process.standardOutput = FileHandle.nullDevice
        return start(process, onExit: onExit)
    }

    /// A tool that delivers output as it runs. `onData` gets every chunk off
    /// the main thread as soon as it is there.
    @MainActor
    static func stream(_ path: String, _ arguments: [String],
                       onData: @escaping @Sendable (Data) -> Void,
                       onExit: @escaping @MainActor (Int32) -> Void) -> Process? {
        let process = make(path, arguments)
        let pipe = Pipe()
        process.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            onData(chunk)
        }
        guard let started = start(process, onExit: onExit) else {
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        return started
    }

    /// Run it and fetch the output without blocking a thread. `nil`: it could
    /// not be started.
    static func output(_ path: String, _ arguments: [String]) async -> Result? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runAndWait(path, arguments))
            }
        }
    }

    /// Run it and wait for it. Only where waiting costs nothing: on a thread of
    /// its own, when the app quits, or for tools that are measured to be done
    /// in milliseconds.
    static func runAndWait(_ path: String, _ arguments: [String]) -> Result? {
        let process = make(path, arguments)
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            log.error("\(path, privacy: .public) nicht startbar: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: data)
    }

    private static func make(_ path: String, _ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    @MainActor
    private static func start(_ process: Process, onExit: (@MainActor (Int32) -> Void)?) -> Process? {
        let id = ObjectIdentifier(process)
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            // Runs after the entry below: both on the main thread, and `start`
            // only releases it afterwards.
            Task { @MainActor in
                alive[id] = nil
                onExit?(status)
            }
        }
        do {
            try process.run()
        } catch {
            let path = process.executableURL?.path ?? "?"
            log.error("\(path, privacy: .public) nicht startbar: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        alive[id] = process
        return process
    }
}
