import Foundation
import ApolloBase

enum StateFiles {
    static func load(configID: String, declarations: [VarDecl], paths: ConfigPaths, fileSystem: any ConfigFileSystem) -> ([String: Value], [Diagnostic]) {
        let url = paths.stateDirectory.appendingPathComponent("\(configID).kdl")
        guard fileSystem.exists(url) else { return ([:], []) }
        guard let text = try? fileSystem.read(url) else { return ([:], []) }
        let (values, diagnostics) = VarStateFile.read(text, file: url.path, declarations: declarations)
        var result = diagnostics
        if needsBackup(diagnostics) {
            let backup = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".unreadable")
            do {
                try fileSystem.copyItem(url, to: backup)
            } catch {
                result.append(Diagnostic(.warning, "could not copy the unreadable state file '\(url.path)'", span: .synthetic(url.path)))
            }
        }
        return (values, result)
    }

    private static func needsBackup(_ diagnostics: [Diagnostic]) -> Bool {
        diagnostics.contains { $0.kind == .stateFileUnreadable || $0.kind == .valueDiscarded }
    }
}
