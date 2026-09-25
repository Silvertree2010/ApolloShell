import Foundation
import Synchronization
import ApolloBase
import ApolloKDL
import ApolloConfig

public final class StateWriter: Sendable {
    private struct State {
        var known: String?
        var lastWritten: String?
        var warned = false
        var warningHandler: (@Sendable (Diagnostic) -> Void)?
    }

    public let file: URL
    private let fileSystem: any ConfigFileSystem
    private let queue: DispatchQueue
    private let state: Mutex<State>

    public init(file: URL, fileSystem: any ConfigFileSystem) {
        self.file = file
        self.fileSystem = fileSystem
        self.queue = DispatchQueue(label: "ApolloRuntime.StateWriter")
        let initial = fileSystem.exists(file) ? (try? fileSystem.read(file)) : ""
        self.state = Mutex(State(known: initial))
    }

    public var lastWrittenText: String? {
        state.withLock { $0.lastWritten }
    }

    public func setWarningHandler(_ handler: @escaping @Sendable (Diagnostic) -> Void) {
        state.withLock { $0.warningHandler = handler }
    }

    public func enqueue(_ values: [String: Value]) {
        queue.async { [self] in
            if let diagnostic = write(values) {
                deliver(diagnostic)
            }
        }
    }

    public func acknowledgeExternal(_ text: String) {
        queue.async { [self] in
            state.withLock { $0.known = text }
        }
    }

    public func preserveUnreadable(_ text: String) {
        let backup = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".unreadable")
        queue.async { [self] in
            do {
                try fileSystem.write(text, to: backup)
            } catch {
                deliver(Diagnostic(.warning, "could not copy the unreadable state file '\(file.path)'", span: .synthetic(file.path)))
            }
        }
    }

    public func flushSync() {
        queue.sync {}
    }

    func write(_ values: [String: Value]) -> Diagnostic? {
        var existingText = fileSystem.exists(file) ? ((try? fileSystem.read(file)) ?? "") : ""
        var baseline = state.withLock { $0.known }
        var replaced: Diagnostic?
        if (try? KDLDocument.parse(existingText, file: file.path)) == nil {
            let backup = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".unreadable")
            do {
                try fileSystem.write(existingText, to: backup)
            } catch {
                return Diagnostic(.warning, "\(file.lastPathComponent) could not be read and its copy could not be saved, so it was left as it is.")
            }
            replaced = Diagnostic(.warning, "\(file.lastPathComponent) could not be read. It was saved as \(backup.lastPathComponent) and started anew.")
            existingText = ""
            baseline = nil
        }
        var accepted = values
        let foreign = baseline.map { $0 != existingText } ?? false
        if let baseline, baseline != existingText {
            let before = Self.rawValues(baseline)
            let now = Self.rawValues(existingText)
            accepted = values.filter { before[$0.key] == now[$0.key] }
        }
        do {
            let newText = try VarStateFile.writing(accepted, into: existingText, file: file.path)
            if newText != existingText {
                try fileSystem.write(newText, to: file)
            }
            state.withLock {
                $0.known = newText
                $0.lastWritten = foreign ? nil : newText
                $0.warned = false
            }
            return replaced
        } catch {
            let alreadyWarned = state.withLock { current -> Bool in
                let was = current.warned
                current.warned = true
                return was
            }
            if alreadyWarned { return nil }
            return Diagnostic(.warning, "\(file.lastPathComponent) could not be saved. The change only applies until the next restart.")
        }
    }

    private func deliver(_ diagnostic: Diagnostic) {
        let handler = state.withLock { $0.warningHandler }
        handler?(diagnostic)
    }

    private static func rawValues(_ text: String) -> [String: Value] {
        guard let document = try? KDLDocument.parse(text, file: "state") else { return [:] }
        var result: [String: Value] = [:]
        for node in document.nodes {
            result[node.name] = ValueKDLMapping.value(from: node)
        }
        return result
    }
}
