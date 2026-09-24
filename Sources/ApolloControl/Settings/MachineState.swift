import Foundation
import ApolloShellCore

public final class MachineState: @unchecked Sendable {
    struct Values: Codable, Equatable {
        var crashReportsHandledUntil: Date?
        var lastUpdateCheck: Date?
    }

    private struct LegacySettings: Decodable {
        var crashReports: CrashReportSettings?
        var updates: UpdateSettings?
    }

    public static let fileName = "control-state.json"
    public static let legacyFileName = "settings.json"

    public let file: URL
    private let lock = NSLock()
    private var values: Values

    public init(folder: URL) {
        file = folder.appendingPathComponent(Self.fileName)
        if let data = try? Data(contentsOf: file) {
            values = (try? JSONDecoder().decode(Values.self, from: data)) ?? Values()
        } else if let data = try? Data(contentsOf: folder.appendingPathComponent(Self.legacyFileName)),
                  let legacy = try? JSONDecoder().decode(LegacySettings.self, from: data) {
            values = Values(crashReportsHandledUntil: legacy.crashReports?.handledUntil, lastUpdateCheck: legacy.updates?.lastCheck)
        } else {
            values = Values()
        }
    }

    public var crashReportsHandledUntil: Date? {
        get { lock.withLock { values.crashReportsHandledUntil } }
        set { update { $0.crashReportsHandledUntil = newValue } }
    }

    public var lastUpdateCheck: Date? {
        get { lock.withLock { values.lastUpdateCheck } }
        set { update { $0.lastUpdateCheck = newValue } }
    }

    private func update(_ change: (inout Values) -> Void) {
        let snapshot = lock.withLock { () -> Values in
            change(&values)
            return values
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
