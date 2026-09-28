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
    static let maxBytes = 1 << 20

    public let file: URL
    private let lock = NSLock()
    private let writeLock = NSLock()
    private var values: Values

    public init(folder: URL) {
        file = folder.appendingPathComponent(Self.fileName)
        if let data = Self.contents(of: file) {
            values = (try? JSONDecoder().decode(Values.self, from: data)) ?? Values()
        } else if let data = Self.contents(of: folder.appendingPathComponent(Self.legacyFileName)),
                  let legacy = try? JSONDecoder().decode(LegacySettings.self, from: data) {
            values = Values(crashReportsHandledUntil: legacy.crashReports?.handledUntil, lastUpdateCheck: legacy.updates?.lastCheck)
        } else {
            values = Values()
        }
    }

    static func contents(of url: URL) -> Data? {
        let resolved = url.resolvingSymlinksInPath()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              let handle = try? FileHandle(forReadingFrom: resolved) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes else { return nil }
        return data
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
        lock.withLock { change(&values) }
        writeLock.withLock {
            let snapshot = lock.withLock { values }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}
