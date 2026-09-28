import Foundation
import ApolloProviders

@MainActor
final class SystemScriptHandle: ScriptHandle {
    let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        guard process.isRunning else { return }
        let descendants = ProcessTree.descendants(of: process.processIdentifier)
        process.terminate()
        for pid in descendants { kill(pid, SIGTERM) }
    }
}

enum ProcessTree {
    static func descendants(of root: pid_t) -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        size = processes.count * stride
        guard sysctl(&mib, 3, &processes, &size, nil, 0) == 0 else { return [] }
        var children: [pid_t: [pid_t]] = [:]
        for entry in processes.prefix(size / stride) {
            children[entry.kp_eproc.e_ppid, default: []].append(entry.kp_proc.p_pid)
        }
        var result: [pid_t] = []
        var pending = [root]
        while let current = pending.popLast() {
            for child in children[current] ?? [] where child != root {
                result.append(child)
                pending.append(child)
            }
        }
        return result
    }
}

final class LineBuffer: @unchecked Sendable {
    static let limit = 1 << 20
    private let lock = NSLock()
    private var pending = Data()

    func append(_ chunk: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        pending.append(chunk)
        var lines: [String] = []
        while let index = pending.firstIndex(of: 0x0A) {
            lines.append(String(decoding: pending[pending.startIndex..<index], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...index)
        }
        if pending.count > Self.limit {
            lines.append(String(decoding: pending, as: UTF8.self))
            pending.removeAll()
        }
        return lines
    }

    func finish() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else { return [] }
        let line = String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        return [line]
    }
}

final class StreamEnd: @unchecked Sendable {
    private let lock = NSLock()
    private var outputClosed = false
    private var status: Int32?
    private var reported = false

    func closeOutput() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        outputClosed = true
        return claim()
    }

    func exit(_ code: Int32) -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        status = code
        return outputClosed ? claim() : nil
    }

    func giveUpWaiting() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        return claim()
    }

    private func claim() -> Int32? {
        guard let status, !reported else { return nil }
        reported = true
        return status
    }
}

enum ScriptOutput {
    static let limit = 1 << 20

    static func read(_ handle: FileHandle) -> Data {
        var data = Data()
        while true {
            let chunk = handle.readData(ofLength: 65_536)
            if chunk.isEmpty { return data }
            if data.count < limit { data.append(chunk.prefix(limit - data.count)) }
        }
    }
}

@MainActor
final class SystemScriptRunner: ScriptRunner {
    private let socketPath: String?

    init(socketPath: String?) {
        self.socketPath = socketPath
    }

    var now: Date { Date() }

    func run(_ command: String, _ completion: @escaping @MainActor (Int32, String) -> Void) -> (any ScriptHandle)? {
        let process = make(command)
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let reader = pipe.fileHandleForReading
        let running = UnsafeProcess(process)
        let thread = Thread {
            let data = ScriptOutput.read(reader)
            running.process.waitUntilExit()
            let status = running.process.terminationStatus
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in completion(status, text) }
        }
        thread.qualityOfService = .utility
        thread.start()
        return SystemScriptHandle(process)
    }

    func stream(_ command: String, onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void) -> (any ScriptHandle)? {
        let process = make(command)
        let pipe = Pipe()
        process.standardOutput = pipe
        let buffer = LineBuffer()
        let end = StreamEnd()
        let reader = pipe.fileHandleForReading
        let thread = Thread {
            while true {
                let chunk = reader.readData(ofLength: 65_536)
                guard !chunk.isEmpty else { break }
                let lines = buffer.append(chunk)
                guard !lines.isEmpty else { continue }
                Task { @MainActor in for line in lines { onLine(line) } }
            }
            let rest = buffer.finish()
            let status = end.closeOutput()
            Task { @MainActor in
                for line in rest { onLine(line) }
                if let status { onExit(status) }
            }
        }
        thread.qualityOfService = .utility
        process.terminationHandler = { finished in
            if let status = end.exit(finished.terminationStatus) {
                Task { @MainActor in onExit(status) }
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                guard let status = end.giveUpWaiting() else { return }
                Task { @MainActor in onExit(status) }
            }
        }
        do {
            try process.run()
        } catch {
            return nil
        }
        thread.start()
        return SystemScriptHandle(process)
    }

    private func make(_ command: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        var environment = ProcessInfo.processInfo.environment
        if let socketPath { environment["APOLLO_SOCKET"] = socketPath }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}

final class UnsafeProcess: @unchecked Sendable {
    let process: Process

    init(_ process: Process) {
        self.process = process
    }
}
