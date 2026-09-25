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
        return lines
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
        DispatchQueue.global(qos: .utility).async {
            let data = reader.readDataToEndOfFile()
            running.process.waitUntilExit()
            let status = running.process.terminationStatus
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in completion(status, text) }
        }
        return SystemScriptHandle(process)
    }

    func stream(_ command: String, onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void) -> (any ScriptHandle)? {
        let process = make(command)
        let pipe = Pipe()
        process.standardOutput = pipe
        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let lines = buffer.append(chunk)
            guard !lines.isEmpty else { return }
            Task { @MainActor in for line in lines { onLine(line) } }
        }
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor in onExit(status) }
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
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
