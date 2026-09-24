import ApolloShellCore
import Foundation
import os

enum Subprocess {
    struct Result: Sendable {
        let status: Int32
        let output: Data
        var text: String { String(decoding: output, as: UTF8.self) }
    }

    private static let log = Logger(category: "subprocess")

    @MainActor private static var alive: [ObjectIdentifier: Process] = [:]

    @MainActor
    @discardableResult
    static func launch(_ path: String, _ arguments: [String] = [],
                       onExit: (@MainActor (Int32) -> Void)? = nil) -> Process? {
        let process = make(path, arguments)
        process.standardOutput = FileHandle.nullDevice
        return start(process, onExit: onExit)
    }

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

    static func output(_ path: String, _ arguments: [String]) async -> Result? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runAndWait(path, arguments))
            }
        }
    }

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
