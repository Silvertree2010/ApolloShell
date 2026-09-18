import ApolloShellCore
import Foundation
import os

/// Werkzeuge der Systeme (pmset, osascript, shortcuts ...) als eigene
/// Prozesse - an einer Stelle statt in jeder Datei von Hand.
///
/// Was niemand liest, geht nach /dev/null: eine ungelesene Pipe liefe voll
/// und hielte den Prozess an.
enum Subprocess {
    struct Result: Sendable {
        let status: Int32
        let output: Data
        var text: String { String(decoding: output, as: UTF8.self) }
    }

    private static let log = Logger(category: "subprocess")

    /// Laufende Prozesse aus `launch` und `stream`, bis sie enden - so muss
    /// sie niemand sonst festhalten.
    @MainActor private static var alive: [ObjectIdentifier: Process] = [:]

    /// Starten, nicht warten. `onExit` bekommt den Rueckgabewert auf dem
    /// Hauptthread. `nil`: liess sich nicht starten (steht im Log), dann
    /// kommt auch kein `onExit`.
    @MainActor
    @discardableResult
    static func launch(_ path: String, _ arguments: [String] = [],
                       onExit: (@MainActor (Int32) -> Void)? = nil) -> Process? {
        let process = make(path, arguments)
        process.standardOutput = FileHandle.nullDevice
        return start(process, onExit: onExit)
    }

    /// Ein Werkzeug, das laufend Ausgabe liefert. `onData` bekommt jeden
    /// Brocken abseits des Hauptthreads, sobald er da ist.
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

    /// Laufen lassen und die Ausgabe abholen, ohne einen Faden zu
    /// blockieren. `nil`: liess sich nicht starten.
    static func output(_ path: String, _ arguments: [String]) async -> Result? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runAndWait(path, arguments))
            }
        }
    }

    /// Laufen lassen und darauf warten. Nur, wo Warten nichts kostet: auf
    /// einem eigenen Faden, beim Beenden der App, oder fuer Werkzeuge, die
    /// gemessen nach Millisekunden fertig sind.
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
            // Laeuft nach dem Eintrag unten: beides auf dem Hauptthread, und
            // `start` gibt ihn erst danach frei.
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
