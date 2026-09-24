import Foundation
import Synchronization
import ApolloBase
import ApolloConfig

public final class StateWriter: Sendable {
    private let file: URL
    private let fileSystem: any ConfigFileSystem
    private let lastWritten: Mutex<String?>
    private let warnedOnce: Mutex<Bool>

    public init(file: URL, fileSystem: any ConfigFileSystem) {
        self.file = file
        self.fileSystem = fileSystem
        self.lastWritten = Mutex(nil)
        self.warnedOnce = Mutex(false)
    }

    public var lastWrittenText: String? {
        lastWritten.withLock { $0 }
    }

    @discardableResult
    public func write(_ values: [String: Value]) -> Diagnostic? {
        let existingText = (try? fileSystem.read(file)) ?? ""
        do {
            let newText = try VarStateFile.writing(values, into: existingText, file: file.path)
            if newText != existingText {
                try fileSystem.write(newText, to: file)
            }
            lastWritten.withLock { $0 = newText }
            warnedOnce.withLock { $0 = false }
            return nil
        } catch {
            let alreadyWarned = warnedOnce.withLock { warned -> Bool in
                let was = warned
                warned = true
                return was
            }
            if alreadyWarned { return nil }
            return Diagnostic(.warning, "\(file.lastPathComponent) could not be saved. The change only applies until the next restart.")
        }
    }
}
